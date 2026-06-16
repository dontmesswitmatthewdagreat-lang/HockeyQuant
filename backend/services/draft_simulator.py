"""
Weekly first-round mock draft simulator.

No public mock-draft API exists, so we project natively from data we already
pull: pick order from current standings (reverse), prospect value from a merged
NHL Central Scouting board, and team needs (forward / defense / goalie) from
MoneyPuck team xG + goalie GSAx. Each pick = best-available with a need tilt.

Runs weekly via cron (idempotent per ISO week); stored in `mock_drafts`.
"""

import datetime
import json
import re
from typing import Dict, List, Optional

import requests

from services.constants import ALL_TEAMS, TEAM_FULL_NAMES
from services.data_loader import get_data_loader
from services.news_sources import _google_news, UA
from services.llm import groq_chat

_AI_MODEL = "llama-3.3-70b-versatile"

NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}

# Best-available with a gentle need tilt. Board value is ~1 unit per draft slot,
# so these bonuses only reach ~1 spot for need — never overriding a clear talent
# gap (the #1 pick stays the consensus #1).
_PRIMARY_BONUS = 1.5
_SECONDARY_BONUS = 0.75
_GOALIE_REACH_PENALTY = 6.0    # goalies essentially never reach round 1
_WINDOW = 5                    # consider the top-N available at each pick


def _ordinal(n: int) -> str:
    if 10 <= n % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suffix}"


def _group(position: Optional[str]) -> str:
    """Prospect position -> need group (F / D / G)."""
    p = (position or "").upper()
    if p == "G":
        return "G"
    if p == "D":
        return "D"
    return "F"


def _reason(group: str, rank: int) -> str:
    """Why a pick fills a team's need (rank 1 = best in that area, 32 = worst)."""
    o = _ordinal(rank)
    if group == "F":
        return f"{o} in offense (xGF) — needs scoring"
    if group == "D":
        return f"{o} in defense (xGA) — needs a defenseman"
    return f"{o} in goaltending (GSAx) — needs a goalie"


# MARK: - Draft order (reverse standings)

def _fetch_standings() -> List[dict]:
    try:
        data = requests.get("https://api-web.nhle.com/v1/standings/now", headers=NHL_HEADERS, timeout=15).json()
    except Exception:
        return []
    out = []
    for r in data.get("standings", []):
        abbrev = (r.get("teamAbbrev") or {}).get("default")
        if not abbrev:
            continue
        out.append({
            "abbrev": abbrev,
            "points": r.get("points") or 0,
            "regulationWins": r.get("regulationWins") or 0,
            "goalDifferential": r.get("goalDifferential") or 0,
            "gamesPlayed": r.get("gamesPlayed") or 0,
            "goalFor": r.get("goalFor") or 0,
            "goalAgainst": r.get("goalAgainst") or 0,
            "date": r.get("date"),
        })
    return out


def _draft_order(standings: List[dict]) -> List[str]:
    """Worst record picks first (points, then regulation wins, then goal diff)."""
    ordered = sorted(standings, key=lambda s: (s["points"], s["regulationWins"], s["goalDifferential"]))
    return [s["abbrev"] for s in ordered]


# MARK: - Consensus prospect board

def _consensus_pool(sb) -> List[dict]:
    """Draft prospects merged into one ordered board (lower value = picked sooner)."""
    rows = sb.table("prospects").select(
        "nhl_id,name,position,league,draft_year,ranking,notable,info"
    ).eq("notable", "true").execute().data or []

    pool = []
    for p in rows:
        info = p.get("info") or {}
        cat = info.get("category")
        rank = p.get("ranking") or 999
        if cat == "north-american-skater":
            value = rank * 2 - 1           # interleave NA / Intl skaters: NA1=1, Intl1=2, NA2=3…
        elif cat == "international-skater":
            value = rank * 2
        elif cat in ("north-american-goalie", "international-goalie"):
            value = 45 + rank * 3          # goalies discounted well down the board
        else:
            value = 500 + rank
        pool.append({
            "nhl_id": p.get("nhl_id"),
            "name": p.get("name"),
            "position": p.get("position"),
            "league": p.get("league"),
            "group": _group(p.get("position")),
            "ranking": p.get("ranking"),
            "value": value,
            "info": info,
        })
    pool.sort(key=lambda x: x["value"])
    return pool


# MARK: - Team needs (MoneyPuck xG + goalie GSAx, standings fallback)

def _team_needs(standings_by_abbrev: Dict[str, dict]) -> Dict[str, dict]:
    """For each team: primary/secondary need group + a short reason."""
    dl = get_data_loader()
    try:
        dl.load_all_data()
    except Exception:
        pass
    team_data = getattr(dl, "team_data", None)
    goalie_data = getattr(dl, "goalie_data", None)

    metrics: Dict[str, dict] = {}
    for abbrev in ALL_TEAMS:
        s = standings_by_abbrev.get(abbrev, {})
        gp = s.get("gamesPlayed") or 82

        off = deff = None
        if team_data is not None:
            row = team_data[team_data["team"] == abbrev]
            if not row.empty:
                r = row.iloc[0]
                mp_gp = float(r["games_played"]) or gp
                off = float(r["xGoalsFor"]) / mp_gp
                deff = float(r["xGoalsAgainst"]) / mp_gp
        if off is None:                       # standings fallback
            off = (s.get("goalFor") or 0) / gp
            deff = (s.get("goalAgainst") or 0) / gp

        gsax = 0.0
        if goalie_data is not None:
            tg = goalie_data[goalie_data["team"] == abbrev]
            if not tg.empty:
                g = tg.sort_values("games_played", ascending=False).iloc[0]
                gsax = float(g["xGoals"]) - float(g["goals"])
        metrics[abbrev] = {"off": off, "def": deff, "goalie": gsax}

    teams = [a for a in ALL_TEAMS if a in metrics]
    # Rank 1 = best in each area; a high rank number = a weakness.
    off_rank = {a: i + 1 for i, a in enumerate(sorted(teams, key=lambda a: -metrics[a]["off"]))}
    def_rank = {a: i + 1 for i, a in enumerate(sorted(teams, key=lambda a: metrics[a]["def"]))}
    gln_rank = {a: i + 1 for i, a in enumerate(sorted(teams, key=lambda a: -metrics[a]["goalie"]))}

    needs: Dict[str, dict] = {}
    for a in teams:
        ranked = sorted(
            [("F", off_rank[a]), ("D", def_rank[a]), ("G", gln_rank[a])],
            key=lambda x: -x[1],   # worst (highest rank number) first
        )
        needs[a] = {
            "primary": ranked[0][0],
            "secondary": ranked[1][0],
            "ranks": {"F": off_rank[a], "D": def_rank[a], "G": gln_rank[a]},
        }
    return needs


# MARK: - News + AI projection

def _fetch_draft_news(draft_year: int) -> List[dict]:
    """Recent draft news (lottery order, mock drafts, rumors) for the AI layer."""
    queries = [
        f"{draft_year} NHL Draft order lottery results",
        f"{draft_year} NHL Mock Draft first round",
        f"{draft_year} NHL Draft top prospects rankings",
    ]
    seen, items = set(), []
    for q in queries:
        try:
            for it in _google_news(q, "Google News", None, limit=10):
                key = it.get("url") or it.get("title")
                if key and key not in seen:
                    seen.add(key)
                    items.append(it)
        except Exception:
            continue
    return items[:40]


def _news_block(items: List[dict], limit: int = 30) -> str:
    return "\n".join(
        f"- {it.get('title', '')}" + (f" — {it['snippet']}" if it.get("snippet") else "")
        for it in items[:limit]
    )


def _ai_extract_order(items: List[dict], draft_year: int) -> List[str]:
    """Best-effort first-round order (team abbrevs) from lottery/order reporting."""
    if not items:
        return []
    system = (
        f"You extract the {draft_year} NHL Draft FIRST-ROUND pick order from news. Use the "
        "draft-lottery results and any reported/traded-pick order. List teams in pick order "
        "using official NHL abbreviations (TOR, SJS, CHI, …). Only include teams you can "
        "actually infer from the items — returning just the top few is fine.\n"
        'Return ONLY JSON: {"order": ["TOR", "SJS", ...]}'
    )
    try:
        raw = groq_chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": "News:\n" + _news_block(items)}],
            model=_AI_MODEL, max_tokens=400, temperature=0.1, response_json=True)
        order = json.loads(raw).get("order", [])
    except Exception:
        return []
    valid, out = set(ALL_TEAMS), []
    for a in order:
        a = str(a).upper().strip()
        if a in valid and a not in out:
            out.append(a)
    return out


def _ai_project_picks(order: List[str], pool: List[dict], needs: Dict[str, dict],
                      items: List[dict]) -> Dict[int, dict]:
    """AI picks a prospect (pool index) + rationale per slot from mock-draft/rumor news."""
    if not items or not order:
        return {}
    pool_lines = "\n".join(
        f"[{i}] {p['name']} ({p.get('position') or '?'}, {p.get('league') or '?'}, CS#{p.get('ranking') or '?'})"
        for i, p in enumerate(pool[:90]))
    order_lines = "\n".join(
        f"{i + 1}: {TEAM_FULL_NAMES.get(t, t)} ({t}) — needs {needs.get(t, {}).get('primary', '?')}"
        for i, t in enumerate(order))
    system = (
        "You are an NHL Draft analyst. Project a first-round pick ONLY when the provided news "
        "actually supports it — a reported team–prospect link, a GM statement, a mock-draft "
        "pairing, or a clear consensus #1. If the news does NOT tell you who a team takes, OMIT "
        "that slot entirely (it will be filled by consensus ranking + team need). Never guess a "
        "name to fill a slot. Goalies are almost never first-round picks — do not pick a goalie "
        "unless the news explicitly reports it. Each prospect may be picked at most once.\n"
        "- Only use prospect indices from the list.\n"
        "- rationale: one short clause grounded in the news (quote/paraphrase the actual report).\n"
        'Return ONLY JSON: {"picks": [{"slot": <int>, "idx": <int>, "rationale": "<text>"}]} '
        "(include only the slots the news supports — likely just a handful)."
    )
    user = f"Draft order:\n{order_lines}\n\nProspects:\n{pool_lines}\n\nRecent news:\n{_news_block(items)}"
    try:
        raw = groq_chat(
            [{"role": "system", "content": system}, {"role": "user", "content": user}],
            model=_AI_MODEL, max_tokens=2400, temperature=0.3, response_json=True)
        data = json.loads(raw)
    except Exception:
        return {}
    out, used = {}, set()
    for entry in data.get("picks", []):
        try:
            slot, idx = int(entry.get("slot")), int(entry.get("idx"))
        except (TypeError, ValueError):
            continue
        if not (1 <= slot <= len(order)) or not (0 <= idx < len(pool)) or idx in used or slot in out:
            continue
        used.add(idx)
        out[slot] = {"idx": idx, "rationale": str(entry.get("rationale") or "")[:140]}
    return out


# MARK: - Draft order resolution (official → news → standings)

def _nhl_api_order(draft_year: int) -> List[str]:
    """Official first-round order from the NHL API once published (lottery + traded picks).
    Empty until the NHL populates it near draft day."""
    for url in (f"https://api-web.nhle.com/v1/draft/picks/{draft_year}/1",
                "https://api-web.nhle.com/v1/draft/picks/now"):
        try:
            d = requests.get(url, headers=NHL_HEADERS, timeout=15).json()
        except Exception:
            continue
        if d.get("draftYear") != draft_year:
            continue
        r1 = [p for p in d.get("picks", []) if p.get("round") == 1 and p.get("teamAbbrev")]
        if len(r1) >= 16:
            r1.sort(key=lambda p: p.get("overallPick") or 0)
            return [p["teamAbbrev"] for p in r1]
    return []


def _order_article_text(draft_year: int) -> str:
    """Server-rendered NHL.com order-article text (has the full post-lottery order + trades)."""
    slugs = [
        f"{draft_year}-nhl-draft-1st-round-order",
        f"{draft_year}-nhl-draft-first-round-order",
        f"{draft_year}-nhl-draft-order",
    ]
    for slug in slugs:
        try:
            html = requests.get(f"https://www.nhl.com/news/{slug}",
                                headers={"User-Agent": UA}, timeout=15).text
        except Exception:
            continue
        txt = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", html, flags=re.S | re.I)
        txt = re.sub(r"<[^>]+>", " ", txt)
        txt = re.sub(r"\s+", " ", txt)
        if len(re.findall(r"\b\d{1,2}\.\s*[A-Z]", txt)) >= 10:   # looks like a numbered order
            return txt[:9000]
    return ""


def _ai_extract_order_from_text(text: str, draft_year: int) -> List[str]:
    """Full first-round order (owners, traded picks included) extracted from an order article."""
    if not text:
        return []
    system = (
        f"Extract the {draft_year} NHL Draft FIRST-ROUND pick order from this article. Return the "
        "team that OWNS each pick, in order (account for traded picks — the current owner, not the "
        "original team), as official NHL abbreviations.\n"
        'Return ONLY JSON: {"order": ["TOR", "SJS", ...]}'
    )
    try:
        raw = groq_chat(
            [{"role": "system", "content": system}, {"role": "user", "content": text[:9000]}],
            model=_AI_MODEL, max_tokens=700, temperature=0.0, response_json=True)
        order = json.loads(raw).get("order", [])
    except Exception:
        return []
    valid = set(ALL_TEAMS)
    return [a for a in (str(x).upper().strip() for x in order) if a in valid]  # dups OK (trades)


def _resolve_order(draft_year: int, standings: List[dict], news: List[dict]):
    """(order, basis). Official NHL API order if published; else the published post-lottery order
    read from an NHL.com order article (full, with traded picks); else the lottery winner(s) from
    news headlines padded by reverse standings; else a reverse-standings projection."""
    reverse = _draft_order(standings)
    official = _nhl_api_order(draft_year)
    if official:
        return official, "Official NHL draft order"
    from_article = _ai_extract_order_from_text(_order_article_text(draft_year), draft_year)
    if len(from_article) >= 28:
        return from_article, "Official post-lottery draft order"
    from_news = _ai_extract_order(news, draft_year)
    if from_news:
        order = list(from_news)
        for t in reverse:                      # fill remaining slots by reverse standings
            if len(order) >= len(reverse):
                break
            if t not in order:
                order.append(t)
        return order, "Post-lottery order, via recent reporting"
    as_of = standings[0].get("date") if standings else None
    return reverse, f"Projected from current standings{f' (as of {as_of})' if as_of else ''}"


# MARK: - Simulation

def _prospect_payload(choice: dict, draft_year: int, fallback_id) -> dict:
    """Shaped to match the iOS `Prospect` model so it reuses headshot/flag helpers."""
    info = choice.get("info") or {}
    return {
        "id": str(choice.get("nhl_id") or choice.get("name") or fallback_id),
        "nhl_id": choice.get("nhl_id"),
        "name": choice.get("name"),
        "team": None,
        "position": choice.get("position"),
        "draft_year": draft_year,
        "league": choice.get("league"),
        "ranking": choice.get("ranking"),
        "notable": True,
        "info": {
            "headshot": info.get("headshot"),
            "country": info.get("country"),
            "category": info.get("category"),
        },
    }


def build_mock_draft(sb) -> Optional[dict]:
    standings = _fetch_standings()
    if not standings:
        return None
    by_abbrev = {s["abbrev"]: s for s in standings}
    pool = _consensus_pool(sb)
    if not pool:
        return None
    needs = _team_needs(by_abbrev)

    # All notable rows are draft-eligible prospects and share the upcoming draft year.
    yr_rows = sb.table("prospects").select("draft_year").eq("notable", "true").limit(1).execute().data
    draft_year = (yr_rows[0].get("draft_year") if yr_rows else None) or datetime.date.today().year + 1

    news = _fetch_draft_news(draft_year)
    order, order_basis = _resolve_order(draft_year, standings, news)
    ai_picks = _ai_project_picks(order, pool, needs, news)

    picks = []
    available = list(pool)
    for i, abbrev in enumerate(order):
        if not available:
            break
        need = needs.get(abbrev, {"primary": "F", "secondary": "D", "ranks": {}})

        choice, reason, source = None, None, "heuristic"
        ai = ai_picks.get(i + 1)
        if ai and pool[ai["idx"]] in available:           # AI-led: news / mock-draft consensus
            choice = pool[ai["idx"]]
            reason = ai["rationale"] or "Projected in recent mock drafts"
            source = "ai"

        if choice is None:                                # heuristic fills the gap (need + BPA)
            window = available[:_WINDOW]

            def score(cand: dict) -> float:
                s = -cand["value"]
                if cand["group"] == need["primary"]:
                    s += _PRIMARY_BONUS
                elif cand["group"] == need["secondary"]:
                    s += _SECONDARY_BONUS
                if cand["group"] == "G" and need["primary"] != "G":
                    s -= _GOALIE_REACH_PENALTY
                return s

            choice = max(window, key=score)
            g = choice["group"]
            reason = _reason(g, need["ranks"].get(g, 16)) if g in (need["primary"], need["secondary"]) \
                else "Best player available"

        available.remove(choice)
        picks.append({
            "overall": i + 1,
            "round": 1,
            "team": abbrev,
            "team_name": TEAM_FULL_NAMES.get(abbrev, abbrev),
            "need": choice["group"],
            "reason": reason,
            "source": source,
            "prospect": _prospect_payload(choice, draft_year, i + 1),
        })

    now = datetime.datetime.now(datetime.timezone.utc)
    _, iso_week, _ = datetime.date.today().isocalendar()
    return {
        "draft_year": draft_year,
        "edition": f"{draft_year}-W{iso_week:02d}",
        "generated_at": now.isoformat(),
        "order_basis": order_basis,
        "picks": picks,
    }
