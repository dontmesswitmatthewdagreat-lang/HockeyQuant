"""HockeyQuant What-If Router — re-run the goal model with overridden inputs."""

from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel

from services.whatif import simulate, sim_inputs

router = APIRouter()


@router.get("/sim-inputs")
def sim_inputs_route(away: str, home: str):
    """Expected goals for both home orientations of a matchup (Monte-Carlo input)."""
    return sim_inputs(away.upper(), home.upper())


class TeamOverride(BaseModel):
    goalie: Optional[str] = None        # "starter" | "backup"
    fatigue_mult: Optional[float] = None
    injury_mult: Optional[float] = None
    st_mult: Optional[float] = None


class WhatIfRequest(BaseModel):
    away: str
    home: str
    away_overrides: Optional[TeamOverride] = None
    home_overrides: Optional[TeamOverride] = None


@router.post("/what-if")
def what_if(req: WhatIfRequest):
    """First call (no overrides) returns the base result + `applied` factor values
    the client uses to initialize its sliders; subsequent calls apply overrides."""
    away_ov = req.away_overrides.dict() if req.away_overrides else None
    home_ov = req.home_overrides.dict() if req.home_overrides else None
    return simulate(req.away.upper(), req.home.upper(), away_ov, home_ov)
