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
                    out[_norm(name)] = {"age": age, "position": p.get("positionCode")}
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
                        "team": cells[2].strip().upper(), "years": years, "aav": aav})
    except Exception:
        return entry["data"] if entry else []
    _cache["signings"] = {"ts": time.time(), "data": out}
    return out


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
        age = (ages.get(key) or ages_fuzzy.get(_fuzzy_key(p["name"])) or {}).get("age")
        if age is None or p["gp"] < 10 or p["position"] == "G":
            continue
        c = contracts.get(key) or contracts_fuzzy.get(_fuzzy_key(p["name"]))
        players[key] = {**p, "age": round(age, 1), "aav": c["aav"] if c else None,
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
        age = (ages.get(key) or ages_fuzzy.get(_fuzzy_key(gp_row["name"])) or {}).get("age")
        if age is None or gp_row["gp"] < 5:
            continue
        c = contracts.get(key) or contracts_fuzzy.get(_fuzzy_key(gp_row["name"]))
        goalies[key] = {**gp_row, "age": round(age, 1),
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
