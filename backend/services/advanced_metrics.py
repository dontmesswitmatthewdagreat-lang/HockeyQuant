"""
Advanced team and skater metrics, derived from MoneyPuck data the app already
downloads every hour.

Two things live here:

**Team goal-differential decomposition.** A team's goal differential splits
into *why*, first by strength state and then, within each state, into process
(did you out-chance them), finishing (did your shooters beat the chances) and
goaltending (did your goalie beat the shots he faced). This is an exact
algebraic identity, not a model — the three parts reconstruct the actual goal
differential to the cent. `decomposition()` returns the residual so a MoneyPuck
schema change surfaces loudly instead of quietly drifting.

**Skater Game Score and on-ice impact.** Game Score is the standard linear-weight
summary of a skater's season; on-ice impact is what happens to the run of play
while he's out there, relative to when he isn't.

⚠️ MoneyPuck publishes its own `gameScore` column and it is not usable: it is
byte-identical between the 'all' and '5on5' rows for 98% of skaters, and credits
a goalie-less 49.42 to a player with 153 shorthanded seconds. Every input to the
standard formula is present, so it is computed here instead.

⚠️ Never build team totals by summing skater rows. A traded player appears once
with his season total attributed to one team, which inflates summed team ice
time by ~7%. Team numbers always come from the team frame.
"""

import time
from typing import Dict, List, Optional

import pandas as pd

from services.data_loader import get_data_loader

_cache: Dict[str, dict] = {}
_TTL = 3600

# Game Score linear weights (Luszczyszyn). Each is the goal-value equivalent of
# one event, derived from how often that event precedes a goal.
_GS_WEIGHTS = {
    "goals": 0.75,
    "primary_assists": 0.70,
    "secondary_assists": 0.55,
    "shots": 0.075,
    "blocks": 0.05,
    "penalties_drawn": 0.15,
    "penalties_taken": -0.15,
    "faceoffs_won": 0.01,
    "faceoffs_lost": -0.01,
    "corsi": 0.05,
    "on_ice_goals": 0.15,
}

# Strength states, in the order they're shown. 'other' is 3-on-3 overtime,
# 4-on-4 and empty net — small, but the identity is only exact with it.
_STATES = [
    ("5on5", "Even strength"),
    ("5on4", "Power play"),
    ("4on5", "Penalty kill"),
    ("other", "OT & empty net"),
]

# A skater needs this much ice time before he's ranked against the league —
# below it, rate stats are noise and a percentile would be a lie.
#
# 300 minutes is the usual cutoff for rate stats, and it's calibrated: it ranks
# ~73% of skaters while excluding zero players with 55+ games. A stricter floor
# (20 hours) dropped Brayden Point, Brady Tkachuk and Mark Stone, which makes
# the card look broken for exactly the players people look up.
MIN_ICETIME = 300 * 60


def _num(row, column: str, default: float = 0.0) -> float:
    """A MoneyPuck cell as a float, tolerating absent columns and NaN."""
    try:
        value = row[column]
    except (KeyError, IndexError, TypeError):
        return default
    if value is None or pd.isna(value):
        return default
    return float(value)


# --------------------------------------------------------------- team metrics

def _state_split(row, label: str, state: str) -> dict:
    """One strength state's goal differential, split into its three causes."""
    gf, ga = _num(row, "goalsFor"), _num(row, "goalsAgainst")
    xgf, xga = _num(row, "xGoalsFor"), _num(row, "xGoalsAgainst")

    process = xgf - xga           # out-chancing: territory and shot quality
    finishing = gf - xgf          # shooters beating the chances they got
    goaltending = -(ga - xga)     # goalie beating the shots he faced

    actual = gf - ga
    return {
        "state": state,
        "label": label,
        "goals_for": gf,
        "goals_against": ga,
        "differential": actual,
        "process": round(process, 2),
        "finishing": round(finishing, 2),
        "goaltending": round(goaltending, 2),
        # Should be 0 by construction; carried so the caller can prove it.
        "residual": round(actual - (process + finishing + goaltending), 4),
        "ice_time": _num(row, "iceTime"),
    }


def decomposition(abbrev: str) -> Optional[dict]:
    """Goal differential for one team, split by strength state and by cause.

    The split is exact: within a state, (xGF−xGA) + (GF−xGF) − (GA−xGA)
    collapses to GF−GA algebraically. `residual` is carried at both levels so a
    caller — or a test — can assert that rather than take it on faith.
    """
    abbrev = abbrev.upper()
    key = f"decomp:{abbrev}"
    hit = _cache.get(key)
    if hit and time.time() - hit["ts"] < _TTL:
        return hit["data"]

    loader = get_data_loader()
    loader.load_all_data()

    frames = {
        "5on5": loader.team_5on5,
        "5on4": loader.pp_data,
        "4on5": loader.pk_data,
        "other": loader.team_other,
    }
    overall = loader.team_data
    if overall is None:
        return None
    team_row = overall[overall["team"] == abbrev]
    if team_row.empty:
        return None
    team_row = team_row.iloc[0]

    splits = []
    for state, label in _STATES:
        frame = frames.get(state)
        if frame is None:
            continue
        rows = frame[frame["team"] == abbrev]
        if rows.empty:
            continue
        splits.append(_state_split(rows.iloc[0], label, state))

    total_gf, total_ga = _num(team_row, "goalsFor"), _num(team_row, "goalsAgainst")
    total_diff = total_gf - total_ga
    states_sum = sum(s["differential"] for s in splits)

    data = {
        "team": abbrev,
        "games_played": int(_num(team_row, "games_played")),
        "goals_for": total_gf,
        "goals_against": total_ga,
        "differential": total_diff,
        "splits": splits,
        # Totals across every state, which is what the summary bars show.
        "process": round(sum(s["process"] for s in splits), 2),
        "finishing": round(sum(s["finishing"] for s in splits), 2),
        "goaltending": round(sum(s["goaltending"] for s in splits), 2),
        # The states should account for the whole differential. If MoneyPuck
        # adds a strength state or renames one, this stops being 0 and the app
        # can say so instead of showing a breakdown that doesn't add up.
        "residual": round(total_diff - states_sum, 4),
    }
    _cache[key] = {"ts": time.time(), "data": data}
    return data


# ------------------------------------------------------------ skater metrics

def _game_score(row) -> float:
    """Season Game Score from its components.

    Kept in one place so the live read and the nightly snapshot can never
    disagree about what a Game Score is.
    """
    w = _GS_WEIGHTS
    corsi = _num(row, "OnIce_F_shotAttempts") - _num(row, "OnIce_A_shotAttempts")
    on_ice_goals = _num(row, "OnIce_F_goals") - _num(row, "OnIce_A_goals")
    return (
        w["goals"] * _num(row, "I_F_goals")
        + w["primary_assists"] * _num(row, "I_F_primaryAssists")
        + w["secondary_assists"] * _num(row, "I_F_secondaryAssists")
        + w["shots"] * _num(row, "I_F_shotsOnGoal")
        + w["blocks"] * _num(row, "shotsBlockedByPlayer")
        + w["penalties_drawn"] * _num(row, "penaltiesDrawn")
        + w["penalties_taken"] * _num(row, "penalties")
        + w["faceoffs_won"] * _num(row, "faceoffsWon")
        + w["faceoffs_lost"] * _num(row, "faceoffsLost")
        + w["corsi"] * corsi
        + w["on_ice_goals"] * on_ice_goals
    )


def _per60(value: float, icetime_seconds: float) -> float:
    hours = icetime_seconds / 3600.0
    return value / hours if hours > 0 else 0.0


def _position_group(position: str) -> str:
    """Forwards are ranked against forwards, defencemen against defencemen —
    a blueliner shouldn't read as a bottom-percentile player for scoring less
    than a winger."""
    return "D" if (position or "").upper() == "D" else "F"


def _skater_row(all_row, ev_row) -> dict:
    """One skater's card: all-situations production, 5-on-5 run of play."""
    icetime_all = _num(all_row, "icetime")
    gs = _game_score(all_row)

    row = {
        "player_id": int(_num(all_row, "playerId")),
        "name": all_row["name"],
        "team": all_row["team"],
        "position": all_row["position"],
        "position_group": _position_group(all_row["position"]),
        "games_played": int(_num(all_row, "games_played")),
        "icetime": icetime_all,
        "toi_per_game": (icetime_all / max(_num(all_row, "games_played"), 1)) / 60.0,
        "game_score": round(gs, 2),
        "game_score_per60": round(_per60(gs, icetime_all), 3),
        "goals": _num(all_row, "I_F_goals"),
        "primary_assists": _num(all_row, "I_F_primaryAssists"),
        "secondary_assists": _num(all_row, "I_F_secondaryAssists"),
        "points": _num(all_row, "I_F_points"),
        # Goals above/below what his shots were worth — finishing talent or luck.
        "finishing": round(_num(all_row, "I_F_goals") - _num(all_row, "I_F_xGoals"), 2),
        "penalty_differential": _num(all_row, "penaltiesDrawn") - _num(all_row, "penalties"),
    }

    if ev_row is not None:
        ev_ice = _num(ev_row, "icetime")
        xgf, xga = _num(ev_row, "OnIce_F_xGoals"), _num(ev_row, "OnIce_A_xGoals")
        on_pct = _num(ev_row, "onIce_xGoalsPercentage")
        off_pct = _num(ev_row, "offIce_xGoalsPercentage")
        ozone = _num(ev_row, "I_F_oZoneShiftStarts")
        dzone = _num(ev_row, "I_F_dZoneShiftStarts")
        row.update({
            "ev_icetime": ev_ice,
            "xgf_per60": round(_per60(xgf, ev_ice), 3),
            "xga_per60": round(_per60(xga, ev_ice), 3),
            "xgf_pct": round(on_pct * 100, 1),
            # The honest one: the run of play with him on vs. off the ice.
            "xgf_pct_rel": round((on_pct - off_pct) * 100, 1),
            "corsi_pct": round(_num(ev_row, "onIce_corsiPercentage") * 100, 1),
            "zone_start_pct": round(ozone / (ozone + dzone) * 100, 1) if (ozone + dzone) > 0 else None,
        })
    return row


def _ranked(rows: List[dict]) -> List[dict]:
    """Attach league percentiles within position group.

    Only players over the ice-time floor are ranked against each other; the
    rest still get their raw numbers, just no percentile.
    """
    metrics = ["game_score_per60", "xgf_pct_rel", "xgf_per60", "finishing", "penalty_differential"]
    for group in ("F", "D"):
        pool = [r for r in rows if r["position_group"] == group and r["icetime"] >= MIN_ICETIME]
        if len(pool) < 5:
            continue
        for metric in metrics:
            values = sorted(r[metric] for r in pool if r.get(metric) is not None)
            if not values:
                continue
            for r in pool:
                v = r.get(metric)
                if v is None:
                    continue
                # Fraction of the pool this player is at or above.
                below = sum(1 for x in values if x < v)
                same = sum(1 for x in values if x == v)
                r.setdefault("percentiles", {})[metric] = round(
                    (below + same / 2) / len(values) * 100
                )
        # xGA is the one metric where lower is better.
        values = sorted(r["xga_per60"] for r in pool if r.get("xga_per60") is not None)
        if values:
            for r in pool:
                v = r.get("xga_per60")
                if v is None:
                    continue
                above = sum(1 for x in values if x > v)
                same = sum(1 for x in values if x == v)
                r.setdefault("percentiles", {})["xga_per60"] = round(
                    (above + same / 2) / len(values) * 100
                )
    return rows


def _all_skaters() -> List[dict]:
    """Every skater, merged across the all-situations and 5-on-5 frames."""
    hit = _cache.get("skaters")
    if hit and time.time() - hit["ts"] < _TTL:
        return hit["data"]

    loader = get_data_loader()
    loader.load_all_data()
    all_frame, ev_frame = loader.skater_data, loader.skater_5on5
    if all_frame is None:
        return []

    ev_by_id = {}
    if ev_frame is not None:
        ev_by_id = {int(r["playerId"]): r for _, r in ev_frame.iterrows()}

    rows = [_skater_row(r, ev_by_id.get(int(r["playerId"])))
            for _, r in all_frame.iterrows()]
    rows = _ranked(rows)
    _cache["skaters"] = {"ts": time.time(), "data": rows}
    return rows


def team_skaters(abbrev: str) -> List[dict]:
    """One team's skaters, best Game Score first."""
    abbrev = abbrev.upper()
    rows = [r for r in _all_skaters() if r["team"] == abbrev]
    return sorted(rows, key=lambda r: -r["game_score"])


def player_impact(player_id: int) -> Optional[dict]:
    """One skater's full card, with his league percentiles."""
    return next((r for r in _all_skaters() if r["player_id"] == player_id), None)


# ------------------------------------------------------------ goalie metrics

# Goalies play far fewer minutes than skaters, so they need their own floor.
# 500 minutes is roughly 8-9 starts — enough that a save percentage means
# something, low enough to still rank a genuine backup.
MIN_GOALIE_ICETIME = 500 * 60


def _goalie_row(row) -> dict:
    """One goalie's season. GSAx is the headline: goals saved above what the
    shots he actually faced were worth, which is the only fair way to compare
    a goalie behind a good defence to one behind a bad one."""
    icetime = _num(row, "icetime")
    xg, ga = _num(row, "xGoals"), _num(row, "goals")
    on_goal = _num(row, "ongoal")
    hd_shots, hd_goals = _num(row, "highDangerShots"), _num(row, "highDangerGoals")
    hd_xg = _num(row, "highDangerxGoals")
    rebounds, x_rebounds = _num(row, "rebounds"), _num(row, "xRebounds")

    return {
        "player_id": int(_num(row, "playerId")),
        "name": row["name"],
        "team": row["team"],
        "position": "G",
        "games_played": int(_num(row, "games_played")),
        "icetime": icetime,
        "toi_per_game": (icetime / max(_num(row, "games_played"), 1)) / 60.0,
        # The headline number.
        "gsax": round(xg - ga, 2),
        "gsax_per60": round(_per60(xg - ga, icetime), 3),
        "shots_against": on_goal,
        "goals_against": ga,
        "save_pct": round((1 - ga / on_goal) * 100, 2) if on_goal > 0 else None,
        # High-danger is where goalies actually separate from each other.
        "hd_shots": hd_shots,
        "hd_save_pct": round((1 - hd_goals / hd_shots) * 100, 2) if hd_shots > 0 else None,
        "hd_gsax": round(hd_xg - hd_goals, 2),
        # ⚠️ RANK-ONLY METRIC — do not display the raw value. MoneyPuck's
        # xRebounds is not calibrated against actual rebounds the way xGoals is
        # against goals: this comes out negative for 71 of 72 qualified goalies
        # (median −45), so showing it would tell every user their goalie is
        # terrible at rebounds. The ordering between goalies is still meaningful,
        # so it's ranked into a percentile and the number itself stays hidden.
        "rebound_control": round(x_rebounds - rebounds, 2),
        # How busy he was — context for everything above.
        "workload_per60": round(_per60(on_goal, icetime), 2),
    }


def _rank_goalies(rows: List[dict]) -> List[dict]:
    """League percentiles among goalies over the ice-time floor."""
    higher_better = ["gsax", "gsax_per60", "save_pct", "hd_save_pct",
                     "hd_gsax", "rebound_control", "workload_per60"]
    pool = [r for r in rows if r["icetime"] >= MIN_GOALIE_ICETIME]
    if len(pool) < 5:
        return rows
    for metric in higher_better:
        values = sorted(r[metric] for r in pool if r.get(metric) is not None)
        if not values:
            continue
        for r in pool:
            v = r.get(metric)
            if v is None:
                continue
            below = sum(1 for x in values if x < v)
            same = sum(1 for x in values if x == v)
            r.setdefault("percentiles", {})[metric] = round(
                (below + same / 2) / len(values) * 100)
    return rows


def _all_goalies() -> List[dict]:
    hit = _cache.get("goalies")
    if hit and time.time() - hit["ts"] < _TTL:
        return hit["data"]

    loader = get_data_loader()
    loader.load_all_data()
    frame = loader.goalie_data
    if frame is None:
        return []
    rows = _rank_goalies([_goalie_row(r) for _, r in frame.iterrows()])
    _cache["goalies"] = {"ts": time.time(), "data": rows}
    return rows


def team_goalies(abbrev: str) -> List[dict]:
    """One team's goalies, best GSAx first."""
    abbrev = abbrev.upper()
    rows = [r for r in _all_goalies() if r["team"] == abbrev]
    return sorted(rows, key=lambda r: -r["gsax"])


def goalie_impact(player_id: int) -> Optional[dict]:
    return next((r for r in _all_goalies() if r["player_id"] == player_id), None)


# ------------------------------------------------------------------ snapshots

# Raw counting columns to preserve, per situation. Deliberately NOT the derived
# metrics: Game Score weights and percentile baselines will be retuned, and if
# the archive stored `game_score` every retune would silently invalidate its own
# history. Storing the components means the whole archive can be recomputed —
# the same reasoning that makes fork_count a cache of model_forks, not a source.
_SKATER_SNAPSHOT_COLUMNS = {
    "games_played": "games_played",
    "icetime": "icetime",
    "i_f_goals": "I_F_goals",
    "i_f_primary_assists": "I_F_primaryAssists",
    "i_f_secondary_assists": "I_F_secondaryAssists",
    "i_f_shots_on_goal": "I_F_shotsOnGoal",
    "i_f_xgoals": "I_F_xGoals",
    "shots_blocked_by_player": "shotsBlockedByPlayer",
    "penalties": "penalties",
    "penalties_drawn": "penaltiesDrawn",
    "faceoffs_won": "faceoffsWon",
    "faceoffs_lost": "faceoffsLost",
    "on_ice_f_shot_attempts": "OnIce_F_shotAttempts",
    "on_ice_a_shot_attempts": "OnIce_A_shotAttempts",
    "on_ice_f_goals": "OnIce_F_goals",
    "on_ice_a_goals": "OnIce_A_goals",
    "on_ice_f_xgoals": "OnIce_F_xGoals",
    "on_ice_a_xgoals": "OnIce_A_xGoals",
    "off_ice_f_xgoals": "OffIce_F_xGoals",
    "off_ice_a_xgoals": "OffIce_A_xGoals",
}

_TEAM_SNAPSHOT_COLUMNS = {
    "games_played": "games_played",
    "ice_time": "iceTime",
    "goals_for": "goalsFor",
    "goals_against": "goalsAgainst",
    "xgoals_for": "xGoalsFor",
    "xgoals_against": "xGoalsAgainst",
    "shot_attempts_for": "shotAttemptsFor",
    "shot_attempts_against": "shotAttemptsAgainst",
    "unblocked_shot_attempts_for": "unblockedShotAttemptsFor",
    "unblocked_shot_attempts_against": "unblockedShotAttemptsAgainst",
    "high_danger_xgoals_for": "highDangerxGoalsFor",
    "high_danger_xgoals_against": "highDangerxGoalsAgainst",
}


def snapshot(sb, snap_date: Optional[str] = None) -> dict:
    """Store today's raw season-to-date totals for skaters and teams.

    MoneyPuck only ever serves current cumulative totals, so a windowed rate
    ("last 14 days") can only be recovered by differencing two snapshots. That
    makes this the only path to form for these metrics — and it means history
    cannot be backfilled, so a missed day is gone.
    """
    import datetime as _dt

    day = snap_date or _dt.date.today().isoformat()
    loader = get_data_loader()
    loader.load_all_data()

    skater_rows = []
    for situation, frame in (("all", loader.skater_data), ("5on5", loader.skater_5on5)):
        if frame is None:
            continue
        for _, r in frame.iterrows():
            row = {
                "snap_date": day,
                "player_id": int(_num(r, "playerId")),
                "name": r["name"],
                "team": r["team"],
                "position": r["position"],
                "situation": situation,
            }
            row.update({col: _num(r, src) for col, src in _SKATER_SNAPSHOT_COLUMNS.items()})
            skater_rows.append(row)

    team_rows = []
    team_frames = {
        "all": loader.team_data, "5on5": loader.team_5on5,
        "5on4": loader.pp_data, "4on5": loader.pk_data, "other": loader.team_other,
    }
    for situation, frame in team_frames.items():
        if frame is None:
            continue
        for _, r in frame.iterrows():
            row = {"snap_date": day, "team": r["team"], "situation": situation}
            row.update({col: _num(r, src) for col, src in _TEAM_SNAPSHOT_COLUMNS.items()})
            team_rows.append(row)

    for i in range(0, len(skater_rows), 300):
        sb.table("skater_snapshots").upsert(
            skater_rows[i:i + 300], on_conflict="player_id,snap_date,situation").execute()
    for i in range(0, len(team_rows), 300):
        sb.table("team_snapshots").upsert(
            team_rows[i:i + 300], on_conflict="team,snap_date,situation").execute()

    return {"date": day, "skaters": len(skater_rows), "teams": len(team_rows)}
