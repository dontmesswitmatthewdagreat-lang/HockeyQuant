"""HockeyQuant Shot Map Router — per-game shot locations from NHL play-by-play."""

from fastapi import APIRouter

from services.shot_map import fetch_shot_map, fetch_team_shot_map

router = APIRouter()


@router.get("/shot-map")
def shot_map(date: str, away: str, home: str):
    """Shots for a game (by date + team abbrevs). available=False for games
    that haven't started or have no play-by-play yet."""
    return fetch_shot_map(date, away, home)


@router.get("/team-shot-map")
def team_shot_map(team: str, games: int = 20):
    """A team's shots aggregated over its most recent completed games."""
    return fetch_team_shot_map(team, max(1, min(games, 40)))
