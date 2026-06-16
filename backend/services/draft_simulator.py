"""
Weekly first-round mock draft simulator.

No public mock-draft API exists, so we project natively from data we already
pull: pick order from current standings (reverse), prospect value from a merged
NHL Central Scouting board, and team needs (forward / defense / goalie) from
MoneyPuck team xG + goalie GSAx. Each pick = best-available with a need tilt.

Runs weekly via cron (idempotent per ISO week); stored in `mock_drafts`.
"""

import datetime
from typing import Dict, List, Optional

import requests

from services.constants import ALL_TEAMS, TEAM_FULL_NAMES
from services.data_loader import get_data_loader

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


# MARK: - Simulation

def build_mock_draft(sb) -> Optional[dict]:
    standings = _fetch_standings()
    if not standings:
        return None
    by_abbrev = {s["abbrev"]: s for s in standings}
    order = _draft_order(standings)
    pool = _consensus_pool(sb)
    if not pool:
        return None
    needs = _team_needs(by_abbrev)

    # All notable rows are draft-eligible prospects and share the upcoming draft year.
    yr_rows = sb.table("prospects").select("draft_year").eq("notable", "true").limit(1).execute().data
    draft_year = (yr_rows[0].get("draft_year") if yr_rows else None) or datetime.date.today().year + 1

    picks = []
    available = list(pool)
    for i, abbrev in enumerate(order):
        if not available:
            break
        need = needs.get(abbrev, {"primary": "F", "secondary": "D", "ranks": {}})
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
        available.remove(choice)
        info = choice.get("info") or {}
        # Reason reflects the actual pick: a need-fit, else best-player-available.
        g = choice["group"]
        if g in (need["primary"], need["secondary"]):
            pick_reason = _reason(g, need["ranks"].get(g, 16))
        else:
            pick_reason = "Best player available"
        picks.append({
            "overall": i + 1,
            "round": 1,
            "team": abbrev,
            "team_name": TEAM_FULL_NAMES.get(abbrev, abbrev),
            "need": g,
            "reason": pick_reason,
            # Shaped to match the iOS `Prospect` model so it reuses headshot/flag helpers.
            "prospect": {
                "id": str(choice.get("nhl_id") or choice.get("name") or (i + 1)),
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
            },
        })

    now = datetime.datetime.now(datetime.timezone.utc)
    iso_year, iso_week, _ = datetime.date.today().isocalendar()
    as_of = standings[0].get("date") or now.date().isoformat()
    return {
        "draft_year": draft_year,
        "edition": f"{draft_year}-W{iso_week:02d}",
        "generated_at": now.isoformat(),
        "order_basis": f"Projected from standings as of {as_of}",
        "picks": picks,
    }
