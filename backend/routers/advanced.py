"""Advanced metrics API: goal-differential decomposition and skater impact.

Plain `def`, not `async def`, on purpose: these handlers do blocking pandas work
and, on a cache miss, blocking HTTP. Declaring them async would run that on the
event loop and stall every other request on the worker.
"""

from typing import Optional

from fastapi import APIRouter, HTTPException

from services.advanced_metrics import (
    decomposition, team_skaters, player_impact, snapshot,
    team_goalies, goalie_impact,
)
from services.supabase_client import get_supabase

router = APIRouter()


@router.get("/advanced/team/{abbrev}")
def team_decomposition(abbrev: str):
    """A team's goal differential, split by strength state and by cause."""
    try:
        data = decomposition(abbrev)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Metrics unavailable: {e}")
    if not data:
        raise HTTPException(status_code=404, detail=f"No data for {abbrev.upper()}")
    return data


@router.get("/advanced/skaters/{abbrev}")
def team_skater_impact(abbrev: str):
    """Every skater on a team, best Game Score first."""
    try:
        rows = team_skaters(abbrev)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Metrics unavailable: {e}")
    return {"team": abbrev.upper(), "skaters": rows}


@router.get("/advanced/player/{player_id}")
def skater_impact_detail(player_id: int):
    """One skater's card, with league percentiles inside his position group."""
    try:
        data = player_impact(player_id)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Metrics unavailable: {e}")
    if not data:
        raise HTTPException(status_code=404, detail="Player not found")
    return data


@router.get("/advanced/goalies/{abbrev}")
def team_goalie_impact(abbrev: str):
    """A team's goalies, best goals-saved-above-expected first."""
    try:
        rows = team_goalies(abbrev)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Metrics unavailable: {e}")
    return {"team": abbrev.upper(), "goalies": rows}


@router.get("/advanced/goalie/{player_id}")
def goalie_impact_detail(player_id: int):
    """One goalie's card, with league percentiles."""
    try:
        data = goalie_impact(player_id)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Metrics unavailable: {e}")
    if not data:
        raise HTTPException(status_code=404, detail="Goalie not found")
    return data


@router.get("/advanced/lines/{abbrev}")
def team_line_chemistry(abbrev: str):
    """Forward lines and defence pairs, plus With/Without for the pairs.

    `available: false` when MoneyPuck's combination file can't be reached — it's
    a separate download from the rest of the metrics and is allowed to fail on
    its own without taking anything else down.
    """
    from services.line_metrics import line_chemistry, pair_wowy
    try:
        data = line_chemistry(abbrev)
        data["wowy"] = pair_wowy(abbrev) if data.get("available") else []
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Line data unavailable: {e}")
    return data


@router.post("/advanced/snapshot")
def store_snapshot(snap_date: Optional[str] = None):
    """Cron: store today's raw season totals.

    MoneyPuck serves only current cumulative totals, so windowed rates can only
    ever be recovered by differencing snapshots — a day not captured is a day
    that can't be reconstructed later.
    """
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    try:
        return snapshot(sb, snap_date)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Snapshot failed: {e}")
