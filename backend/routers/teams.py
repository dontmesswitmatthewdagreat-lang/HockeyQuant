"""
HockeyQuant Teams Router
Endpoints for team statistics
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

from services import (
    NHLAnalyzer,
    get_data_loader,
    ALL_TEAMS,
    TEAM_FULL_NAMES,
    NHL_DIVISIONS,
    NHL_CONFERENCES,
)

router = APIRouter()


class TeamBasicInfo(BaseModel):
    abbrev: str
    name: str
    division: str
    conference: str


class TeamStats(BaseModel):
    abbrev: str
    name: str
    wins: int
    losses: int
    otl: int
    points: int
    points_pct: float
    goals_for: int
    goals_against: int
    goal_diff: int
    xgf: Optional[float]
    xga: Optional[float]


class GoalieStats(BaseModel):
    name: str
    games_played: int
    gsax: float
    sv_pct: float
    gaa: float
    is_starter: bool


class TeamDetailResponse(BaseModel):
    team: TeamBasicInfo
    stats: TeamStats
    goalies: List[GoalieStats]
    injuries: List[str]
    recent_form: str


def get_team_division(abbrev: str) -> str:
    for div, teams in NHL_DIVISIONS.items():
        if abbrev in teams:
            return div
    return "Unknown"


def get_team_conference(abbrev: str) -> str:
    div = get_team_division(abbrev)
    for conf, divs in NHL_CONFERENCES.items():
        if div in divs:
            return conf
    return "Unknown"


@router.get("/teams", response_model=List[TeamBasicInfo])
async def list_teams():
    """Get list of all NHL teams"""
    teams = []
    for abbrev in ALL_TEAMS:
        teams.append(TeamBasicInfo(
            abbrev=abbrev,
            name=TEAM_FULL_NAMES.get(abbrev, abbrev),
            division=get_team_division(abbrev),
            conference=get_team_conference(abbrev),
        ))

    # Sort by division, then name
    teams.sort(key=lambda t: (t.conference, t.division, t.name))
    return teams


@router.get("/teams/{abbrev}", response_model=TeamDetailResponse)
async def get_team(abbrev: str):
    """
    Get detailed stats for a specific team.

    - **abbrev**: Team abbreviation (e.g., TOR, BOS, EDM)
    """
    abbrev = abbrev.upper()
    if abbrev not in ALL_TEAMS:
        raise HTTPException(
            status_code=404,
            detail=f"Team '{abbrev}' not found. Valid abbreviations: {', '.join(sorted(ALL_TEAMS))}"
        )

    data_loader = get_data_loader()
    data_loader.load_all_data()
    analyzer = NHLAnalyzer(data_loader)

    # Get team standings
    team_stats = analyzer.get_team_stats(abbrev)
    if not team_stats:
        raise HTTPException(
            status_code=500,
            detail="Failed to fetch team stats from NHL API"
        )

    # Get xG data
    xg = analyzer.get_team_xg(abbrev)

    # Get goalies
    starter = analyzer.get_starting_goalie(abbrev)
    backup = analyzer.get_backup_goalie(abbrev)
    goalies = []
    if starter:
        goalies.append(GoalieStats(
            name=starter['name'],
            games_played=0,  # Would need to fetch from goalie_data
            gsax=round(starter['gsax'], 2),
            sv_pct=round(starter['sv_pct'], 3),
            gaa=round(starter['gaa'], 2),
            is_starter=True,
        ))
    if backup:
        goalies.append(GoalieStats(
            name=backup['name'],
            games_played=0,
            gsax=round(backup['gsax'], 2),
            sv_pct=round(backup['sv_pct'], 3),
            gaa=round(backup['gaa'], 2),
            is_starter=False,
        ))

    # Get injuries
    injuries = data_loader.get_injuries(abbrev)

    # Get recent form
    streak_mult, streak_summary, _ = analyzer.calculate_streak_multiplier(abbrev, team_stats)

    wins = team_stats.get('wins', 0)
    losses = team_stats.get('losses', 0)
    otl = team_stats.get('otLosses', 0)
    gf = team_stats.get('goalFor', 0)
    ga = team_stats.get('goalAgainst', 0)
    points = team_stats.get('points', 0)
    total_games = wins + losses + otl

    return TeamDetailResponse(
        team=TeamBasicInfo(
            abbrev=abbrev,
            name=TEAM_FULL_NAMES.get(abbrev, abbrev),
            division=get_team_division(abbrev),
            conference=get_team_conference(abbrev),
        ),
        stats=TeamStats(
            abbrev=abbrev,
            name=TEAM_FULL_NAMES.get(abbrev, abbrev),
            wins=wins,
            losses=losses,
            otl=otl,
            points=points,
            points_pct=round(points / (total_games * 2), 3) if total_games > 0 else 0,
            goals_for=gf,
            goals_against=ga,
            goal_diff=gf - ga,
            xgf=round(xg['xGoalsFor'], 2) if xg else None,
            xga=round(xg['xGoalsAgainst'], 2) if xg else None,
        ),
        goalies=goalies,
        injuries=injuries,
        recent_form=streak_summary,
    )


@router.get("/teams/{abbrev}/goalies", response_model=List[GoalieStats])
async def get_team_goalies(abbrev: str):
    """
    Get all available goalies for a team.

    - **abbrev**: Team abbreviation (e.g., TOR, BOS, EDM)

    Returns goalies sorted by games played (starter first).
    """
    abbrev = abbrev.upper()
    if abbrev not in ALL_TEAMS:
        raise HTTPException(
            status_code=404,
            detail=f"Team '{abbrev}' not found. Valid abbreviations: {', '.join(sorted(ALL_TEAMS))}"
        )

    data_loader = get_data_loader()
    data_loader.load_all_data()

    goalie_data = data_loader.goalie_data
    if goalie_data is None:
        raise HTTPException(status_code=500, detail="Failed to load goalie data")

    team_goalies = goalie_data[goalie_data['team'] == abbrev]
    if team_goalies.empty:
        return []

    # Sort by games played (most first)
    team_goalies = team_goalies.sort_values('games_played', ascending=False)

    goalies = []
    for i, (_, goalie) in enumerate(team_goalies.iterrows()):
        xGoals = float(goalie['xGoals'])
        goals = float(goalie['goals'])
        ongoal = float(goalie['ongoal'])
        icetime = float(goalie['icetime'])
        games = int(goalie['games_played'])

        gsax = xGoals - goals
        sv_pct = (ongoal - goals) / ongoal if ongoal > 0 else 0.900
        gaa = (goals / (icetime/60)) * 60 if icetime > 0 else 3.0

        goalies.append(GoalieStats(
            name=goalie['name'],
            games_played=games,
            gsax=round(gsax, 2),
            sv_pct=round(sv_pct, 3),
            gaa=round(gaa, 2),
            is_starter=(i == 0),  # First goalie by GP is starter
        ))

    return goalies


@router.get("/divisions")
async def get_divisions():
    """Get NHL division structure"""
    return {
        "divisions": NHL_DIVISIONS,
        "conferences": NHL_CONFERENCES,
    }
