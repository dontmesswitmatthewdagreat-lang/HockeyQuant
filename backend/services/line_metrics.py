"""
Line and defence-pair chemistry, from MoneyPuck's 5-on-5 combination data.

Two things live here:

**Chemistry** — how a real line or pair performs, and whether that's better or
worse than its members manage in their *other* minutes. A trio that out-chances
opponents only because it contains a star isn't chemistry; a trio that beats what
its members do apart might be.

**With / Without (defence pairs only)** — the classic WOWY comparison, and the
reason it's restricted to pairs is worth stating because it looks like an
omission otherwise. MoneyPuck only lists combinations that played 10+ minutes
together, so a player's listed time doesn't add up to his total. For defencemen
that gap is small (~2% of ice time), because pairs are stable. For forwards it's
~17-21%, because a locked-in duo gets rotated through many short-lived third-man
trios — and every one of those minutes is genuinely "with" his partner but lands
in the "without" bucket. That inflates the apart-side by up to half for exactly
the star duos people want to look up, always in the same direction. It isn't
noise that averages out, and no amount of plumbing fixes it, so forwards get
chemistry only and no without-leg.
"""

import time
from typing import Dict, List, Optional

from services.advanced_metrics import _num
from services.data_loader import get_data_loader, line_player_ids

_cache: Dict[str, dict] = {}
_TTL = 6 * 3600

# A unit needs this much time together before its rates mean anything.
MIN_UNIT_ICETIME = 100 * 60

# Share of a player's 5-on-5 ice time that must be accounted for by listed
# combinations before his "without" number is trustworthy. Defence pairs clear
# this comfortably; forwards essentially never do, which is the point.
MIN_COVERAGE = 0.90


def _skater_index() -> Dict[int, dict]:
    """5-on-5 totals per player id, for baselines and WOWY."""
    loader = get_data_loader()
    loader.load_all_data()
    frame = loader.skater_5on5
    if frame is None:
        return {}
    return {int(_num(r, "playerId")): {
        "name": r["name"],
        "team": r["team"],
        "position": r["position"],
        "icetime": _num(r, "icetime"),
        "xgf": _num(r, "OnIce_F_xGoals"),
        "xga": _num(r, "OnIce_A_xGoals"),
    } for _, r in frame.iterrows()}


def _unit_rows(team: Optional[str] = None) -> List[dict]:
    """Every listed combination, decoded to player ids."""
    loader = get_data_loader()
    frame = loader.lines_data
    if frame is None:
        return []
    if team:
        frame = frame[frame["team"] == team.upper()]
    out = []
    for _, r in frame.iterrows():
        ids = line_player_ids(r["lineId"])
        if not ids:
            continue                    # upstream format changed — skip, don't guess
        out.append({
            "ids": ids,
            "kind": r["position"],      # line | pairing
            "team": r["team"],
            "icetime": _num(r, "icetime"),
            "games_played": int(_num(r, "games_played")),
            "xgf": _num(r, "xGoalsFor"),
            "xga": _num(r, "xGoalsAgainst"),
            "gf": _num(r, "goalsFor"),
            "ga": _num(r, "goalsAgainst"),
            "hdcf": _num(r, "highDangerShotsFor"),
            "hdca": _num(r, "highDangerShotsAgainst"),
        })
    return out


def _share(f: float, a: float) -> Optional[float]:
    return round(f / (f + a) * 100, 1) if (f + a) > 0 else None


def _per60(v: float, seconds: float) -> float:
    return round(v / (seconds / 3600), 2) if seconds > 0 else 0.0


def _chemistry(unit: dict, skaters: Dict[int, dict]) -> Optional[float]:
    """Unit xGF% minus what its members manage in their other minutes.

    Each member's baseline excludes this unit's own minutes — otherwise the unit
    partly predicts itself and every combination looks average. The baselines are
    still contaminated by the members' *other* shared units, which is why the UI
    calls this "vs. their other minutes" rather than a clean chemistry effect.
    """
    unit_pct = _share(unit["xgf"], unit["xga"])
    if unit_pct is None:
        return None

    base_f, base_a = [], []
    for pid in unit["ids"]:
        s = skaters.get(pid)
        if not s:
            return None
        rest = s["icetime"] - unit["icetime"]
        if rest < 20 * 60:              # almost all his time is on this unit
            return None
        base_f.append((s["xgf"] - unit["xgf"]) / rest)
        base_a.append((s["xga"] - unit["xga"]) / rest)
    if not base_f:
        return None

    mf, ma = sum(base_f) / len(base_f), sum(base_a) / len(base_a)
    expected = _share(mf, ma)
    if expected is None:
        return None
    # A small sample can produce absurd deltas; clamp so the UI stays readable.
    return round(max(-15.0, min(15.0, unit_pct - expected)), 1)


def line_chemistry(team: str) -> dict:
    """A team's forward lines and defence pairs, best xGF% first."""
    team = team.upper()
    key = f"chem:{team}"
    hit = _cache.get(key)
    if hit and time.time() - hit["ts"] < _TTL:
        return hit["data"]

    units = _unit_rows(team)
    if not units:
        return {"available": False, "team": team, "lines": [], "pairs": []}
    skaters = _skater_index()

    lines, pairs = [], []
    for u in units:
        if u["icetime"] < MIN_UNIT_ICETIME:
            continue
        players = [{
            "player_id": pid,
            "name": skaters.get(pid, {}).get("name", f"#{pid}"),
            "position": skaters.get(pid, {}).get("position", ""),
        } for pid in u["ids"]]
        row = {
            "players": players,
            "icetime": u["icetime"],
            "minutes": round(u["icetime"] / 60),
            "games_played": u["games_played"],
            "xgf_pct": _share(u["xgf"], u["xga"]),
            "xgf_per60": _per60(u["xgf"], u["icetime"]),
            "xga_per60": _per60(u["xga"], u["icetime"]),
            "gf_pct": _share(u["gf"], u["ga"]),
            "hdcf_pct": _share(u["hdcf"], u["hdca"]),
            # Goals above or below what the unit's chances were worth.
            "finishing": round(u["gf"] - u["xgf"], 1),
            "chemistry": _chemistry(u, skaters),
        }
        (lines if u["kind"] == "line" else pairs).append(row)

    lines.sort(key=lambda r: -(r["icetime"]))
    pairs.sort(key=lambda r: -(r["icetime"]))
    data = {"available": True, "team": team, "lines": lines, "pairs": pairs}
    _cache[key] = {"ts": time.time(), "data": data}
    return data


def pair_wowy(team: str) -> List[dict]:
    """Defence pairs, together vs apart.

    Forwards are deliberately excluded — see the module docstring. Pairs whose
    members have too much unlisted ice time are dropped rather than shown with a
    caveat, because a number next to a warning still gets read as a number.
    """
    team = team.upper()
    key = f"wowy:{team}"
    hit = _cache.get(key)
    if hit and time.time() - hit["ts"] < _TTL:
        return hit["data"]

    skaters = _skater_index()
    all_units = _unit_rows()            # league-wide: a player's listed time
    if not all_units or not skaters:    # includes units from before a trade
        return []

    # How much of each player's 5-on-5 time the listed pairings account for.
    listed: Dict[int, float] = {}
    for u in all_units:
        if u["kind"] != "pairing":
            continue
        for pid in u["ids"]:
            listed[pid] = listed.get(pid, 0.0) + u["icetime"]

    out = []
    for u in _unit_rows(team):
        if u["kind"] != "pairing" or u["icetime"] < MIN_UNIT_ICETIME:
            continue
        a_id, b_id = u["ids"][0], u["ids"][1]
        a, b = skaters.get(a_id), skaters.get(b_id)
        if not a or not b:
            continue

        cov_a = listed.get(a_id, 0) / a["icetime"] if a["icetime"] else 0
        cov_b = listed.get(b_id, 0) / b["icetime"] if b["icetime"] else 0
        if min(cov_a, cov_b) < MIN_COVERAGE:
            continue

        together = _share(u["xgf"], u["xga"])
        # Apart = his own totals minus this pairing's. Both are counting stats
        # over disjoint time, so this is arithmetic, not an estimate — the only
        # error is the sub-10-minute combinations MoneyPuck never listed.
        a_apart = _share(a["xgf"] - u["xgf"], a["xga"] - u["xga"])
        b_apart = _share(b["xgf"] - u["xgf"], b["xga"] - u["xga"])
        if together is None or a_apart is None or b_apart is None:
            continue

        out.append({
            "players": [
                {"player_id": a_id, "name": a["name"], "apart_xgf_pct": a_apart,
                 "apart_minutes": round((a["icetime"] - u["icetime"]) / 60)},
                {"player_id": b_id, "name": b["name"], "apart_xgf_pct": b_apart,
                 "apart_minutes": round((b["icetime"] - u["icetime"]) / 60)},
            ],
            "together_xgf_pct": together,
            "together_minutes": round(u["icetime"] / 60),
            "coverage": round(min(cov_a, cov_b) * 100),
            # Positive = the pair is better than either man is away from it.
            "lift": round(together - max(a_apart, b_apart), 1),
        })

    out.sort(key=lambda r: -r["together_minutes"])
    _cache[key] = {"ts": time.time(), "data": out}
    return out
