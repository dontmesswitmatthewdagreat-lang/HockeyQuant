"""
Offseason GM playground data: real free-agent pool + team cap sheets so users
can build hypothetical signings/trades client-side. Read-only; moves live on
the device.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException

from services.offseason_data import (
    TEAM_SLUGS,
    fetch_free_agents,
    fetch_team_caps,
    fetch_roster,
)

router = APIRouter()


@router.get("/offseason/market")
def market():
    """Everything the market hub needs in one call: league cap ceiling,
    each team's cap space, and the available FA pool."""
    try:
        teams = fetch_team_caps()
        agents = fetch_free_agents()
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Cap data unavailable: {e}")
    if not teams or not agents:
        raise HTTPException(status_code=503, detail="Cap data unavailable")
    # Fair values from the market model (best-effort — the hub renders without them).
    try:
        from services.player_market import values_for_names
        fair = values_for_names([a["name"] for a in agents])
    except Exception:
        fair = {}
    # Space + allocations sums to the upper limit for non-LTIR teams. Spotrac
    # sometimes serves the cap table without the allocations column, so fall
    # back to the announced 2026-27 upper limit.
    with_total = [t["cap_space"] + t["cap_total"] for t in teams if t["cap_total"] is not None]
    ceiling = max(with_total) if with_total else 104_000_000.0
    return {
        "capCeiling": ceiling,
        "teams": [
            {
                "abbrev": t["abbrev"],
                "capSpace": t["cap_space"],
                "capHit": t["cap_total"] if t["cap_total"] is not None
                          else max(ceiling - t["cap_space"], 0.0),
            }
            for t in teams
        ],
        "freeAgents": [
            {
                "name": a["name"],
                "position": a["position"],
                "age": a["age"],
                "prevTeam": a["prev_team"],
                "prevAav": a["prev_aav"],
                "type": a["type"],
                "fairAav": (fair.get(a["name"]) or {}).get("market_value"),
            }
            for a in agents
        ],
        "updated": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/offseason/roster/{abbrev}")
def roster(abbrev: str):
    """Contracted players for one team (fetched lazily — trades only need the
    two teams involved)."""
    ab = abbrev.upper()
    if ab not in TEAM_SLUGS:
        raise HTTPException(status_code=404, detail="Unknown team")
    try:
        players = fetch_roster(ab)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Roster unavailable: {e}")
    return {
        "abbrev": ab,
        "players": [
            {"name": p["name"], "position": p["position"], "aav": p["aav"]}
            for p in players
        ],
    }
