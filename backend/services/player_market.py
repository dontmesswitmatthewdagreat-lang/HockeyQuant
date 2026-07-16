"""
Player market: a fair-value model for every NHL skater, plus a market-heat
layer driven by actual signings.

- Fair value: ridge regression, production → cap%, trained on real contracts
  (Spotrac rosters joined to MoneyPuck production + NHL API ages). ELC/league-
  minimum deals and tiny samples are excluded from training so they don't drag
  the curve, but everyone still gets a predicted value.
- Market heat: how far recent signings are landing above/below model value,
  per position group. One Carlsson-sized overpay moves the *market* line, not
  the fundamentals line.
"""

import re
import time
import unicodedata
from typing import Dict, List, Optional

import numpy as np
import requests

from services.offseason_data import fetch_roster, TEAM_SLUGS, _get as _spotrac_get, _FA_URL, _cells, _dollars

CAP = 104_000_000.0
NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}

_cache: Dict[str, dict] = {}
_TTL = 6 * 3600


def _norm(name: str) -> str:
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z ]", "", s.lower()).strip()


def _fuzzy_key(name: str) -> str:
    """Loosened join key: last name + first-3 of first name (catches
    Alex/Alexander, Matt/Matthew, accent variants already stripped by _norm)."""
    parts = _norm(name).split()
    if len(parts) < 2:
        return _norm(name)
    return f"{parts[-1]}|{parts[0][:3]}"


def _with_fuzzy(primary: Dict[str, dict]) -> Dict[str, dict]:
    """Secondary index on the loosened key; ambiguous keys are dropped."""
    fuzzy: Dict[str, Optional[dict]] = {}
    for v in primary.values():
        k = _fuzzy_key(v.get("name") or "")
        fuzzy[k] = None if k in fuzzy else v
    return {k: v for k, v in fuzzy.items() if v is not None}


def _group(pos: Optional[str]) -> str:
    p = (pos or "").upper()
    if p.startswith("G"):
        return "G"
    return "D" if p.startswith("D") else "F"


# MARK: - Data assembly

def _nhl_ages() -> Dict[str, dict]:
    """name -> {age, position} from NHL API rosters (cached)."""
    entry = _cache.get("ages")
    if entry and time.time() - entry["ts"] < 24 * 3600:
        return entry["data"]
    import datetime
    out: Dict[str, dict] = {}
    today = datetime.date.today()
    for team in TEAM_SLUGS:
        try:
            data = requests.get(f"https://api-web.nhle.com/v1/roster/{team}/current",
                                headers=NHL_HEADERS, timeout=15).json()
        except Exception:
            continue
        for grp in ("forwards", "defensemen", "goalies"):
            for p in data.get(grp, []):
                name = f"{(p.get('firstName') or {}).get('default', '')} {(p.get('lastName') or {}).get('default', '')}".strip()
                bd = p.get("birthDate")
                age = None
                if bd:
                    try:
                        b = datetime.date.fromisoformat(bd)
                        age = (today - b).days / 365.25
                    except ValueError:
                        pass
                if name:
                    out[_norm(name)] = {"age": age, "position": p.get("positionCode"),
                                        "id": p.get("id") or p.get("playerId"),
                                        "headshot": p.get("headshot")}
    _cache["ages"] = {"ts": time.time(), "data": out}
    return out


def _production() -> Dict[str, dict]:
    """name -> per-game production from MoneyPuck (skaters only)."""
    from services.data_loader import get_data_loader
    loader = get_data_loader()
    loader.load_all_data()
    df = loader.skater_data
    out: Dict[str, dict] = {}
    if df is None:
        return out
    for _, s in df.iterrows():
        gp = int(s.get("games_played", 0) or 0)
        if gp <= 0:
            continue
        goals = float(s.get("I_F_goals", 0) or 0)
        assists = float(s.get("I_F_primaryAssists", 0) or 0) + float(s.get("I_F_secondaryAssists", 0) or 0)
        out[_norm(str(s["name"]))] = {
            "name": str(s["name"]),
            "team": str(s.get("team", "")),
            "position": str(s.get("position", "?")).upper(),
            "gp": gp,
            "ppg": (goals + assists) / gp,
            "xg_pg": float(s.get("I_F_xGoals", 0) or 0) / gp,
            "toi_pg": float(s.get("icetime", 0) or 0) / gp / 60.0,   # minutes
        }
    return out


def _goalie_production() -> Dict[str, dict]:
    """name -> goalie value signals from MoneyPuck (GSAX, SV%, workload)."""
    from services.data_loader import get_data_loader
    loader = get_data_loader()
    loader.load_all_data()
    df = loader.goalie_data
    out: Dict[str, dict] = {}
    if df is None:
        return out
    for _, s in df.iterrows():
        gp = int(s.get("games_played", 0) or 0)
        if gp <= 0:
            continue
        xg = float(s.get("xGoals", 0) or 0)         # expected goals against
        ga = float(s.get("goals", 0) or 0)          # actual goals against
        shots = float(s.get("ongoal", 0) or 0)
        gsax = xg - ga                              # goals saved above expected
        out[_norm(str(s["name"]))] = {
            "name": str(s["name"]),
            "team": str(s.get("team", "")),
            "position": "G",
            "gp": gp,
            "gsax": gsax,
            "gsax_pg": gsax / gp,
            "sv_pct": (1 - ga / shots) if shots > 0 else 0.0,
            # Skater-shaped keys kept nil so goalies coexist in one players dict.
            "ppg": 0.0, "xg_pg": 0.0, "toi_pg": 0.0,
        }
    return out


def _goalie_features(p: dict, age: float) -> List[float]:
    # Total GSAX captures quality×volume; games_played separates starters from
    # backups (the biggest AAV driver); SV% adds save efficiency.
    return [p["gsax"], p["gsax_pg"], min(p["gp"], 65), p["sv_pct"] * 100, age]


def fetch_signings() -> List[dict]:
    """This offseason's actual signings from Spotrac's signed-FA table."""
    entry = _cache.get("signings")
    if entry and time.time() - entry["ts"] < _TTL:
        return entry["data"]
    out = []
    try:
        html = _spotrac_get(_FA_URL)
        section = html[:max(html.find("Prev Team"), 0) or len(html)]
        for row in re.findall(r"<tr[^>]*>(.*?)</tr>", section, re.S):
            if "/nhl/player/" not in row:
                continue
            cells = _cells(row)
            # [from, arrow, to, player, pos, yrs, total, aav]
            if len(cells) < 8:
                continue
            aav = _dollars(cells[7])
            if not aav:
                continue
            try:
                years = int(re.search(r"\d+", cells[5]).group(0))
            except Exception:
                years = None
            out.append({"name": cells[3], "position": cells[4][:2].upper(),
                        "team": cells[2].strip().upper(),
                        "from_team": cells[0].strip().upper(),
                        "years": years, "aav": aav})
    except Exception:
        return entry["data"] if entry else []
    _cache["signings"] = {"ts": time.time(), "data": out}
    return out


_TRADES_URL = "https://www.spotrac.com/nhl/transactions/"
_TRADE_ROW = re.compile(
    r'/nhl/player/_/id/\d+/[^"]+"[^>]*>([^<]+)</a>\s*<small[^>]*>(.*?)</small>', re.S)
_TRADE_DESC = re.compile(r"Traded to .+?\(([A-Z]{2,3})\)\s*from .+?\(([A-Z]{2,3})\)")
_PICK = re.compile(r"(conditional\s+)?(\d{4})\s+(\d)(?:st|nd|rd|th)\s+round\s+pick", re.I)


def _parse_trade_page(html: str, players: list, seen: set, picks: dict) -> None:
    for name_raw, desc in _TRADE_ROW.findall(html):
        text = re.sub(r"<[^>]+>", "", desc)
        if "traded to" not in text.lower():
            continue
        m = _TRADE_DESC.search(text)
        if not m:
            continue
        to, frm = m.group(1).upper(), m.group(2).upper()
        name = re.sub(r"\s*\([^)]*\)\s*$", "", name_raw).strip()   # drop trailing " (C)"
        key = (name.lower(), to, frm)
        if name and key not in seen:
            seen.add(key)
            players.append({"name": name, "to_team": to, "from_team": frm})
        # Picks: "with" clause moves with the player (frm→to); "for" return (to→frm).
        after = text.split(" from ", 1)[-1]
        with_part, _, for_part = after.partition(" for ")
        for cond, yr, rd in _PICK.findall(with_part):
            picks[(frm, to, yr, rd)] = bool(cond.strip())
        for cond, yr, rd in _PICK.findall(for_part):
            picks[(to, frm, yr, rd)] = bool(cond.strip())


def fetch_trades(max_pages: int = 15) -> dict:
    """This offseason's trades from Spotrac's transactions feed.

    Returns {"players": [...], "picks": [...]}: each traded player with the
    team that acquired him (`to_team`) and dealt him (`from_team`), plus the
    draft picks that changed hands (deduped by from/to/year/round — the same
    pick appears in every player-row of its trade). A pick in the "with" clause
    travels with the player (from→to); one in the "for" return goes the other
    way (to→from).

    The feed is chronological, so as summer signings pile up the offseason's
    trades get pushed onto later pages — we walk `/_/page/N` to recover them."""
    entry = _cache.get("trades")
    if entry and time.time() - entry["ts"] < _TTL:
        return entry["data"]
    players, seen, picks = [], set(), {}
    try:
        from concurrent.futures import ThreadPoolExecutor
        from services.offseason_data import _get

        def page(n):
            url = _TRADES_URL if n == 1 else f"{_TRADES_URL}_/page/{n}"
            try:
                return _get(url)
            except Exception:
                return ""

        with ThreadPoolExecutor(max_workers=5) as pool:
            pages = list(pool.map(page, range(1, max_pages + 1)))
        for html in pages:
            if html:
                _parse_trade_page(html, players, seen, picks)
    except Exception:
        return entry["data"] if entry else {"players": [], "picks": []}
    data = {"players": players,
            "picks": [{"from": f, "to": t, "year": int(y), "round": int(r), "conditional": c}
                      for (f, t, y, r), c in picks.items()]}
    _cache["trades"] = {"ts": time.time(), "data": data}
    return data


# Rough asset value of a draft pick in fair-value dollars (surplus a pick
# tends to return), discounted for "conditional". Used to value the pick side
# of a trade — the report card's futures ledger.
_PICK_VALUE = {1: 3_000_000, 2: 1_200_000, 3: 600_000, 4: 350_000,
               5: 200_000, 6: 120_000, 7: 80_000}


def _pick_value(rd: int, conditional: bool) -> float:
    return _PICK_VALUE.get(rd, 100_000) * (0.6 if conditional else 1.0)


def _pick_summary(pl: list) -> str:
    from collections import Counter
    names = {1: "first", 2: "second", 3: "third", 4: "fourth",
             5: "fifth", 6: "sixth", 7: "seventh"}
    c = Counter(p["round"] for p in pl)
    return ", ".join(f"{c[r]} {names.get(r, f'{r}th')}{'s' if c[r] > 1 else ''}"
                     for r in sorted(c))


# MARK: - Valuation model

def _ridge(X: np.ndarray, y: np.ndarray, lam: float = 1.0):
    mu, sd = X.mean(axis=0), X.std(axis=0) + 1e-9
    Xs = (X - mu) / sd
    Xb = np.hstack([Xs, np.ones((len(Xs), 1))])
    A = Xb.T @ Xb + lam * np.eye(Xb.shape[1])
    w = np.linalg.solve(A, Xb.T @ y)
    return w, mu, sd


def _features(p: dict, age: float) -> List[float]:
    return [p["ppg"], p["xg_pg"], p["toi_pg"], age, age * age,
            1.0 if _group(p["position"]) == "D" else 0.0, min(p["gp"], 82)]


def build_market() -> dict:
    """Join contracts + production + ages, fit the model, compute heat.
    Cached; this is the single source every endpoint reads."""
    entry = _cache.get("market")
    if entry and time.time() - entry["ts"] < _TTL:
        return entry["data"]

    prod = _production()
    ages = _nhl_ages()
    ages_fuzzy = _with_fuzzy({k: {**v, "name": k} for k, v in ages.items()})

    contracts: Dict[str, dict] = {}
    for team in TEAM_SLUGS:
        try:
            for pl in fetch_roster(team):
                contracts.setdefault(_norm(pl["name"]), {**pl, "team": team})
        except Exception:
            continue
    contracts_fuzzy = _with_fuzzy(contracts)

    # Assemble every skater we can value (has production + an age).
    players: Dict[str, dict] = {}
    for key, p in prod.items():
        meta = ages.get(key) or ages_fuzzy.get(_fuzzy_key(p["name"])) or {}
        age = meta.get("age")
        if age is None or p["gp"] < 10 or p["position"] == "G":
            continue
        c = contracts.get(key) or contracts_fuzzy.get(_fuzzy_key(p["name"]))
        players[key] = {**p, "age": round(age, 1), "nhl_id": meta.get("id"),
                        "headshot": meta.get("headshot"),
                        "aav": c["aav"] if c else None,
                        "contract_team": c["team"] if c else None}

    # Train on real, non-ELC contracts with a meaningful sample.
    train = [p for p in players.values()
             if p["aav"] and p["aav"] >= 1_500_000 and p["gp"] >= 20]
    if len(train) < 60:
        raise RuntimeError(f"Not enough joined contracts to fit ({len(train)})")
    X = np.array([_features(p, p["age"]) for p in train])
    y = np.array([p["aav"] / CAP for p in train])
    w, mu, sd = _ridge(X, y)

    def predict(p: dict) -> float:
        x = (np.array(_features(p, p["age"])) - mu) / sd
        v = float(np.append(x, 1.0) @ w) * CAP
        return float(min(max(v, 775_000.0), 17_000_000.0))

    # Residual spread per group → honest value ranges.
    resid = {"F": [], "D": []}
    for p in train:
        resid[_group(p["position"])].append(p["aav"] - predict(p))
    spread = {g: float(np.std(v)) if v else 1_500_000.0 for g, v in resid.items()}

    for p in players.values():
        p["model_value"] = predict(p)
        p["value_low"] = max(p["model_value"] - spread[_group(p["position"])], 775_000.0)
        p["value_high"] = p["model_value"] + spread[_group(p["position"])]

    # Goalies: a separate GSAX-based model (their economics don't resemble
    # skaters'). Small sample, so heavily regularized + a wider honest range.
    goalies: Dict[str, dict] = {}
    gprod = _goalie_production()
    for key, gp_row in gprod.items():
        meta = ages.get(key) or ages_fuzzy.get(_fuzzy_key(gp_row["name"])) or {}
        age = meta.get("age")
        if age is None or gp_row["gp"] < 5:
            continue
        c = contracts.get(key) or contracts_fuzzy.get(_fuzzy_key(gp_row["name"]))
        goalies[key] = {**gp_row, "age": round(age, 1), "nhl_id": meta.get("id"),
                        "headshot": meta.get("headshot"),
                        "aav": c["aav"] if c else None,
                        "contract_team": c["team"] if c else None}
    gtrain = [g for g in goalies.values() if g["aav"] and g["aav"] >= 1_500_000 and g["gp"] >= 12]
    if len(gtrain) >= 12:
        GX = np.array([_goalie_features(g, g["age"]) for g in gtrain])
        gy = np.array([g["aav"] / CAP for g in gtrain])
        gw, gmu, gsd = _ridge(GX, gy, lam=1.8)

        def gpredict(g: dict) -> float:
            x = (np.array(_goalie_features(g, g["age"])) - gmu) / gsd
            v = float(np.append(x, 1.0) @ gw) * CAP
            return float(min(max(v, 775_000.0), 11_000_000.0))

        gresid = float(np.std([g["aav"] - gpredict(g) for g in gtrain])) or 2_000_000.0
        for g in goalies.values():
            g["model_value"] = gpredict(g)
            g["value_low"] = max(g["model_value"] - gresid, 775_000.0)
            g["value_high"] = g["model_value"] + gresid
        players.update(goalies)

    # Market heat: how recent signings priced vs model, per group.
    heat = {"F": 0.0, "D": 0.0, "G": 0.0}
    heat_n = {"F": 0, "D": 0, "G": 0}
    graded_signings = []
    for s in fetch_signings():
        pl = players.get(_norm(s["name"]))
        fair = pl["model_value"] if pl else None
        verdict = None
        if fair and s["aav"] >= 1_500_000:
            prem = (s["aav"] - fair) / fair
            g = _group(s["position"])
            # Goalies keep per-signing verdicts but don't feed a market-heat
            # trend: the summer goalie-signing pool is a handful of noisy
            # backup deals, and one outlier shouldn't reprice every goalie.
            if s["aav"] >= 2_000_000 and g != "G":
                heat[g] += prem
                heat_n[g] += 1
            verdict = "steal" if prem < -0.15 else ("overpay" if prem > 0.15 else "fair")
        graded_signings.append({**s, "fair_value": fair, "verdict": verdict})
    # Need a few signings before claiming a market trend — 1-2 deals (common
    # for goalies) shouldn't swing a whole position group's market value.
    for g in heat:
        heat[g] = float(min(max(heat[g] / heat_n[g], -0.25), 0.50)) if heat_n[g] >= 3 else 0.0

    for p in players.values():
        p["market_value"] = p["model_value"] * (1 + heat[_group(p["position"])])

    data = {
        "players": players,
        "heat": heat,
        "trained_on": len(train),
        "signings": graded_signings,
        "built_at": time.time(),
    }
    _cache["market"] = {"ts": time.time(), "data": data}
    return data


def values_for_names(names: List[str]) -> Dict[str, dict]:
    """name -> {model_value, market_value} for the offseason FA payload."""
    try:
        market = build_market()
    except Exception:
        return {}
    out = {}
    for n in names:
        p = market["players"].get(_norm(n))
        if p:
            out[n] = {"model_value": p["model_value"], "market_value": p["market_value"]}
    return out


# MARK: - Action photos

_ACTION_URL = "https://assets.nhle.com/mugs/actionshots/1296x729/{}.jpg"
_etag_cache: Dict[int, Optional[str]] = {}
_team_fallback_etag: Dict[str, Optional[str]] = {}   # team -> shared fallback ETag
_photo_cache: Dict[int, Optional[str]] = {}


def _actionshot_etag(nhl_id) -> Optional[str]:
    """The NHL serves a shared team-arena fallback (identical ETag) for players
    without a personal action shot; a real shot has a unique ETag."""
    if nhl_id in _etag_cache:
        return _etag_cache[nhl_id]
    etag = None
    try:
        r = requests.head(_ACTION_URL.format(nhl_id), timeout=8, allow_redirects=True)
        etag = r.headers.get("ETag") if r.status_code == 200 else None
    except Exception:
        etag = None
    _etag_cache[nhl_id] = etag
    return etag


def resolve_action_photo(player: dict, market: dict) -> Optional[str]:
    """The player's in-game action photo, or None when the NHL only has the
    generic team-arena fallback for them (detected via the shared ETag)."""
    nhl_id = player.get("nhl_id")
    if not nhl_id:
        return None
    if nhl_id in _photo_cache:
        return _photo_cache[nhl_id]

    url = _ACTION_URL.format(nhl_id)
    etag = _actionshot_etag(nhl_id)
    if not etag:                          # couldn't check → assume it's real
        _photo_cache[nhl_id] = url
        return url

    team = player.get("contract_team") or player.get("team") or ""
    fallback = _team_fallback_etag.get(team, "__unset__")
    if fallback == "__unset__":
        # The ETag shared by 2+ of a team's players is that team's arena fallback.
        from collections import Counter
        mates = [p["nhl_id"] for p in market["players"].values()
                 if (p.get("contract_team") or p.get("team") or "") == team and p.get("nhl_id")][:15]
        counts = Counter(e for e in (_actionshot_etag(m) for m in mates) if e)
        top = counts.most_common(1)
        fallback = top[0][0] if top and top[0][1] >= 2 else None
        _team_fallback_etag[team] = fallback

    # A real NHL shot is landscape (1296x729) and looks best full-bleed; the
    # arena fallback → None (the caller uses a portrait photo instead).
    result = None if (fallback and etag == fallback) else url
    _photo_cache[nhl_id] = result
    return result


_wiki_photo_cache: Dict[str, Optional[str]] = {}


def wikimedia_photo(name: str) -> Optional[str]:
    """A validated Wikipedia photo (usually in-uniform) — the portrait hero when
    the NHL has no real action shot, preferred over the plain headshot."""
    if not name:
        return None
    if name in _wiki_photo_cache:
        return _wiki_photo_cache[name]
    try:
        from services.prospect_headshots import wikimedia_lead_photo
        url = wikimedia_lead_photo(name)
    except Exception:
        url = None
    _wiki_photo_cache[name] = url
    return url


def comparables(key: str, market: dict, limit: int = 5) -> List[dict]:
    """Nearest same-group players by market value."""
    me = market["players"].get(key)
    if not me:
        return []
    g = _group(me["position"])
    floor = 12 if g == "G" else 20
    pool = [p for k, p in market["players"].items()
            if k != key and _group(p["position"]) == g and p["gp"] >= floor]
    pool.sort(key=lambda p: abs(p["market_value"] - me["market_value"]))
    return pool[:limit]


# MARK: - Offseason report card

def _letter(score: float) -> str:
    # Bands fit the report card's 35–95 range: an average summer lands C+/B-,
    # a clear overpay in the D's, only a genuine value coup reaches A.
    for cutoff, letter in ((92, "A+"), (88, "A"), (85, "A-"), (82, "B+"), (78, "B"),
                           (75, "B-"), (72, "C+"), (68, "C"), (64, "C-"),
                           (60, "D+"), (56, "D"), (52, "D-")):
        if score >= cutoff:
            return letter
    return "F"


def _mm(v: float) -> str:
    return f"${v / 1e6:.1f}M"


def offseason_report_card(team: str) -> dict:
    """Grade a team's real offseason: signings vs model value, talent in/out,
    what rivals paid the departures, and the draft desk. Fully deterministic —
    every point on the grade traces to a factor row."""
    import datetime
    from services.offseason_data import fetch_team_caps, fetch_roster, _norm_abbrev
    from services.draft_results import team_picks

    team = _norm_abbrev(team)
    market = build_market()
    signings = market["signings"]

    def nt(t):
        return _norm_abbrev(t or "")

    players = market["players"]
    additions = [s for s in signings if nt(s.get("team")) == team]
    arrivals = [s for s in additions if nt(s.get("from_team")) != team]
    resigned = [s for s in additions if nt(s.get("from_team")) == team]
    departures = [s for s in signings
                  if nt(s.get("from_team")) == team and nt(s.get("team")) != team]

    # Trades: an acquired player brings his existing contract. Taking on a bad
    # contract (or shedding one) is a value decision, graded like a signing —
    # this is how the Korpisalo/Nurse-type deals reach the report card, which
    # the free-agent feed alone never sees. Picks/prospects aren't valued.
    trade_data = fetch_trades()
    trade_players, pick_moves = trade_data["players"], trade_data["picks"]

    def trade_move(t, other_key):
        p = players.get(_norm(t["name"]))
        if not p or not p.get("aav"):
            return None
        aav, fair = float(p["aav"]), p["model_value"]
        prem = (aav - fair) / fair if fair else 0.0
        return {"name": t["name"], "position": p.get("position", "?"),
                "aav": aav, "years": None, "fair_value": fair,
                "verdict": "steal" if prem < -0.15 else ("overpay" if prem > 0.15 else "fair"),
                "other_team": nt(t[other_key])}

    trades_in = [m for m in (trade_move(t, "from_team") for t in trade_players
                             if nt(t["to_team"]) == team) if m]
    trades_out = [m for m in (trade_move(t, "to_team") for t in trade_players
                              if nt(t["from_team"]) == team) if m]

    # Draft-pick capital that changed hands in trades — a futures ledger.
    picks_in = [p for p in pick_moves if nt(p["to"]) == team]
    picks_out = [p for p in pick_moves if nt(p["from"]) == team]
    pick_gain = sum(_pick_value(p["round"], p["conditional"]) for p in picks_in)
    pick_cost = sum(_pick_value(p["round"], p["conditional"]) for p in picks_out)
    net_picks = pick_gain - pick_cost

    committed = sum(s["aav"] for s in additions) + sum(m["aav"] for m in trades_in)

    # Value discipline runs over every contract the team chose to add — graded
    # signings plus trade acquisitions. Below the threshold, the model values
    # even a league-minimum body above his AAV, booking fake "surplus".
    GRADED_MIN = 1_500_000

    def _prem(aav, fair):
        # Per-contract premium, clamped: the model wildly over-values cheap
        # young players (a $1.75M kid "worth" $4M), and one such contract
        # shouldn't swing a grade. Overpays have more room than "steals".
        if aav <= 0 or not fair:
            return None
        return max(-0.35, min(0.55, (aav - fair) / aav))

    def graded_stats(sig_adds, tr_adds):
        rows = [(s["aav"], s["fair_value"]) for s in sig_adds
                if s.get("fair_value") and s["aav"] >= GRADED_MIN]
        rows += [(m["aav"], m["fair_value"]) for m in tr_adds if m["aav"] >= GRADED_MIN]
        spend = paid = 0.0
        for aav, fair in rows:
            p = _prem(aav, fair)
            if p is None:
                continue
            spend += aav
            paid += p * aav                               # clamped $ over model
        return len(rows), spend, paid

    n_graded, spend_graded, paid_over = graded_stats(additions, trades_in)
    surplus = -paid_over                                  # + = under model
    prem_ratio = (paid_over / spend_graded) if spend_graded else None

    # League baseline: the same contract pool across every team (the model
    # values players above their AAV, so grade against the market, not zero).
    all_tr = [m for m in (trade_move(t, "from_team") for t in trade_players) if m]
    _, lg_spend, lg_paid = graded_stats(signings, all_tr)
    league_prem = (lg_paid / lg_spend) if lg_spend else 0.0
    rel_prem = (prem_ratio - league_prem) if prem_ratio is not None else None  # + = worse than market

    matched_deps = [s for s in departures if s.get("fair_value")]
    dodged = sum(max(0.0, s["aav"] - s["fair_value"]) for s in matched_deps)
    lost_value = sum(s["fair_value"] for s in matched_deps) + sum(m["fair_value"] for m in trades_out)
    gained_value = sum(s["fair_value"] for s in arrivals if s.get("fair_value")) \
        + sum(m["fair_value"] for m in trades_in)
    net_talent = gained_value - lost_value

    # Draft desk (this year's class; before the draft, last year's).
    year = datetime.date.today().year
    picks = team_picks(year, team) or team_picks(year - 1, team)
    first = min(picks, key=lambda p: p["overall"]) if picks else None
    elc = 0
    if picks:
        try:
            roster = fetch_roster(team)
            names = {_norm(p["name"]) for p in roster}
            fuzzy = {_fuzzy_key(p["name"]) for p in roster}
            elc = sum(1 for p in picks
                      if _norm(p["player"]) in names or _fuzzy_key(p["player"]) in fuzzy)
        except Exception:
            elc = 0

    # Grade: value discipline on the significant signings is the spine; the
    # draft desk, exits, and net talent are small capped nudges. Centered so an
    # average summer lands C+/B- and a clear overpay drops into the D's.
    moves = (len(additions) + len(departures) + len(trades_in) + len(trades_out)
             + len(picks_in) + len(picks_out))
    score = None
    if moves:
        raw = 68.0   # neutral base (C)
        # Two co-equal lenses — "did you get better?" and "did you pay well?"
        # Talent added (net fair value in vs out) is a major term: paying a
        # little over market for real talent is still a good summer. A pure
        # value audit used to punish every win-now team.
        talent = max(-14.0, min(19.0, net_talent / 1e6 * 1.3))
        raw += talent
        if rel_prem is not None:
            # Value discipline still bites for a genuine overpay, but no longer
            # defines the grade on its own.
            val = -rel_prem * (78 if rel_prem >= 0 else 52)
            raw += max(-15.0, min(10.0, val))
        # Futures: pick capital dealt for win-now help is a real cost; selling
        # veterans for a pick haul is real value. Moderate, capped both ways.
        raw += max(-8.0, min(8.0, net_picks / 1e6 * 0.9))
        # Draft desk centered on an ordinary class — only a genuinely strong
        # one (ELCs under contract, a top-5 pick) is a net positive.
        draft_pts = elc * 0.6 + (1.0 if first and first["overall"] <= 5 else 0.0) - 0.8
        raw += max(-1.0, min(2.5, draft_pts))
        score = round(max(35.0, min(94.0, raw)))

    grade = _letter(score) if score is not None else "INC"

    STRONG_TALENT = 6_000_000
    over = prem_ratio if prem_ratio is not None else 0.0
    # A weak grade leads with what dragged it down; the forgiving "added talent,
    # paid over" framing is reserved for summers that actually graded out well.
    weak = score is not None and score < 68
    if not moves:
        headline = "A quiet summer so far — no moves in or out."
    elif weak and over >= 0.12:
        headline = f"Overpaid this summer — about {round(over * 100)}% above model on the contracts it added."
    elif weak and net_talent <= -3_000_000:
        headline = f"More talent left than arrived ({_mm(-net_talent)} of fair value)."
    elif net_talent >= STRONG_TALENT and over >= 0.10:
        headline = f"Added real talent ({_mm(net_talent)} of fair value), but paid over market to do it."
    elif net_talent >= STRONG_TALENT:
        headline = f"Got meaningfully better — {_mm(net_talent)} of fair value added, at a fair price."
    elif over >= 0.12:
        headline = f"Took on about {round(over * 100)}% over model on the contracts it added."
    elif surplus >= 800_000:
        headline = f"Banked {_mm(surplus)} of surplus value across {n_graded} graded moves."
    elif net_talent <= -3_000_000:
        headline = f"More talent left than arrived ({_mm(-net_talent)} of fair value)."
    elif dodged >= 2_000_000:
        headline = f"Let rivals overpay the departures by {_mm(dodged)}."
    elif not n_graded:
        headline = "A quiet summer of depth moves so far."
    else:
        headline = "A measured summer — close-to-fair value on both sides."

    factors = []
    if n_graded:
        n_sig = sum(1 for s in additions if s.get("fair_value") and s["aav"] >= GRADED_MIN)
        n_trade = sum(1 for m in trades_in if m["aav"] >= GRADED_MIN)
        kinds = ([f"{n_sig} signing{'s' if n_sig != 1 else ''}"] if n_sig else []) \
            + ([f"{n_trade} trade{'s' if n_trade != 1 else ''}"] if n_trade else [])
        factors.append({
            "label": "VALUE DISCIPLINE",
            "detail": f"{'+' if surplus >= 0 else '−'}{_mm(abs(surplus))} vs model across "
                      + " + ".join(kinds),
            "positive": surplus >= 0})
    if arrivals or trades_in or matched_deps or trades_out:
        factors.append({
            "label": "TALENT FLOW",
            "detail": f"{_mm(gained_value)} of fair value in · {_mm(lost_value)} out",
            "positive": net_talent >= 0})
    if matched_deps:
        factors.append({
            "label": "EXITS",
            "detail": (f"Rivals paid {_mm(dodged)} over model for the departures"
                       if dodged > 500_000 else "Departures signed near model value elsewhere"),
            "positive": dodged > 500_000})
    elif not departures:
        factors.append({"label": "EXITS", "detail": "No notable departures", "positive": True})
    if picks_in or picks_out:
        parts = []
        if picks_out:
            parts.append(f"Dealt {_pick_summary(picks_out)}")
        if picks_in:
            parts.append(f"added {_pick_summary(picks_in)}")
        factors.append({"label": "FUTURES", "detail": " · ".join(parts),
                        "positive": net_picks >= 0})
    if picks:
        factors.append({
            "label": "DRAFT DESK",
            "detail": f"{len(picks)} picks · first at #{first['overall']} ({first['player']}) · "
                      f"{elc} ELC{'s' if elc != 1 else ''} signed",
            "positive": elc > 0 or len(picks) >= 6})

    cap_space = None
    try:
        cap_space = next((c["cap_space"] for c in fetch_team_caps()
                          if _norm_abbrev(c["abbrev"]) == team), None)
    except Exception:
        pass

    def row(s, other_key):
        return {"name": s["name"], "position": s["position"], "aav": s["aav"],
                "years": s.get("years"),
                "fair_value": round(s["fair_value"]) if s.get("fair_value") else None,
                "verdict": s.get("verdict"),
                "other_team": nt(s.get(other_key)) or None}

    def trow(m):   # trade rows already carry other_team from trade_move
        return {**m, "fair_value": round(m["fair_value"]) if m.get("fair_value") else None}

    return {
        "team": team, "grade": grade, "score": score, "headline": headline,
        "committed": round(committed), "surplus": round(surplus),
        "factors": factors,
        "arrivals": [row(s, "from_team") for s in sorted(arrivals, key=lambda s: -s["aav"])],
        "resigned": [row(s, "from_team") for s in sorted(resigned, key=lambda s: -s["aav"])],
        "departures": [row(s, "team") for s in sorted(departures, key=lambda s: -s["aav"])],
        "trades_in": [trow(m) for m in sorted(trades_in, key=lambda m: -m["aav"])],
        "trades_out": [trow(m) for m in sorted(trades_out, key=lambda m: -m["aav"])],
        "draft": {"picks": len(picks),
                  "first_overall": first["overall"] if first else None,
                  "first_player": first["player"] if first else None,
                  "elc_signed": elc},
        "cap_space": round(cap_space) if cap_space else None,
    }
