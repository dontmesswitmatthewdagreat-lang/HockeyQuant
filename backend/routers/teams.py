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


class TeamListItem(BaseModel):
    abbrev: str
    name: str
    division: str
    conference: str
    wins: int = 0
    losses: int = 0
    otl: int = 0
    points: int = 0
    points_pct: float = 0.0
    goals_for: int = 0
    goals_against: int = 0


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


class SkaterStats(BaseModel):
    name: str
    position: str
    games_played: int
    goals: int
    assists: int
    points: int
    xgoals: float
    shots: int
    toi_per_game: float  # minutes per game


class AdvancedStats(BaseModel):
    corsi_for: float
    corsi_against: float
    corsi_pct: float
    fenwick_for: float
    fenwick_against: float
    fenwick_pct: float
    xg_for: float
    xg_against: float
    xg_pct: float
    pdo: float
    shooting_pct: float
    save_pct: float
    hd_chances_for: int
    hd_chances_against: int
    hd_goals_for: int
    hd_goals_against: int
    hd_cf_pct: float
    pp_pct: float
    pk_pct: float
    shots_for_pg: float
    shots_against_pg: float
    shot_attempts_for_pg: float
    shot_attempts_against_pg: float
    games_played: int


class TeamDetailResponse(BaseModel):
    team: TeamBasicInfo
    stats: TeamStats
    goalies: List[GoalieStats]
    injuries: List[str]
    recent_form: str
    advanced_stats: Optional[AdvancedStats] = None


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


def calculate_advanced_stats(data_loader, team_abbrev: str) -> Optional[AdvancedStats]:
    """Calculate advanced analytics from MoneyPuck data."""
    team_data = data_loader.team_data
    pp_data = data_loader.pp_data
    pk_data = data_loader.pk_data

    if team_data is None:
        return None

    row = team_data[team_data['team'] == team_abbrev]
    if row.empty:
        return None

    r = row.iloc[0]
    games = int(r['games_played'])
    if games == 0:
        return None

    # Possession (Corsi = shot attempts, Fenwick = unblocked shot attempts)
    cf = float(r['shotAttemptsFor'])
    ca = float(r['shotAttemptsAgainst'])
    corsi_pct = (cf / (cf + ca) * 100) if (cf + ca) > 0 else 50.0

    ff = float(r['unblockedShotAttemptsFor'])
    fa = float(r['unblockedShotAttemptsAgainst'])
    fenwick_pct = (ff / (ff + fa) * 100) if (ff + fa) > 0 else 50.0

    # Expected Goals
    xgf = float(r['xGoalsFor'])
    xga = float(r['xGoalsAgainst'])
    xg_pct = (xgf / (xgf + xga) * 100) if (xgf + xga) > 0 else 50.0

    # PDO = Sh% + Sv%
    gf = float(r['goalsFor'])
    ga = float(r['goalsAgainst'])
    sog_for = float(r['shotsOnGoalFor'])
    sog_against = float(r['shotsOnGoalAgainst'])

    sh_pct = (gf / sog_for * 100) if sog_for > 0 else 8.0
    sv_pct = ((sog_against - ga) / sog_against * 100) if sog_against > 0 else 91.0
    pdo = sh_pct + sv_pct

    # High Danger
    hd_for = int(r['highDangerShotsFor'])
    hd_against = int(r['highDangerShotsAgainst'])
    hd_gf = int(r['highDangerGoalsFor'])
    hd_ga = int(r['highDangerGoalsAgainst'])
    hd_cf_pct = (hd_for / (hd_for + hd_against) * 100) if (hd_for + hd_against) > 0 else 50.0

    # Special Teams (from PP/PK situation data)
    pp_pct_val = 0.0
    pk_pct_val = 0.0
    if pp_data is not None and pk_data is not None:
        team_pp = pp_data[pp_data['team'] == team_abbrev]
        team_pk = pk_data[pk_data['team'] == team_abbrev]

        if not team_pp.empty:
            pp_goals = float(team_pp.iloc[0]['goalsFor'])
            pp_shots = float(team_pp.iloc[0]['shotsOnGoalFor'])
            # Use a reasonable PP opportunity estimate from games and penalties
            pp_gp = float(team_pp.iloc[0]['games_played'])
            if pp_gp > 0 and pp_shots > 0:
                # PP% approximation: goals / (shots / ~3 shots per opportunity)
                pp_opps = pp_shots / 3.0  # rough estimate
                pp_pct_val = (pp_goals / pp_opps) * 100 if pp_opps > 0 else 0.0

        if not team_pk.empty:
            pk_ga = float(team_pk.iloc[0]['goalsAgainst'])
            pk_shots_against = float(team_pk.iloc[0]['shotsOnGoalAgainst'])
            if pk_shots_against > 0:
                pk_opps = pk_shots_against / 3.0
                pk_pct_val = (1 - pk_ga / pk_opps) * 100 if pk_opps > 0 else 0.0

    return AdvancedStats(
        corsi_for=round(cf, 0),
        corsi_against=round(ca, 0),
        corsi_pct=round(corsi_pct, 1),
        fenwick_for=round(ff, 0),
        fenwick_against=round(fa, 0),
        fenwick_pct=round(fenwick_pct, 1),
        xg_for=round(xgf, 1),
        xg_against=round(xga, 1),
        xg_pct=round(xg_pct, 1),
        pdo=round(pdo, 1),
        shooting_pct=round(sh_pct, 1),
        save_pct=round(sv_pct, 1),
        hd_chances_for=hd_for,
        hd_chances_against=hd_against,
        hd_goals_for=hd_gf,
        hd_goals_against=hd_ga,
        hd_cf_pct=round(hd_cf_pct, 1),
        pp_pct=round(pp_pct_val, 1),
        pk_pct=round(pk_pct_val, 1),
        shots_for_pg=round(sog_for / games, 1),
        shots_against_pg=round(sog_against / games, 1),
        shot_attempts_for_pg=round(cf / games, 1),
        shot_attempts_against_pg=round(ca / games, 1),
        games_played=games,
    )


@router.get("/teams", response_model=List[TeamListItem])
async def list_teams():
    """Get list of all NHL teams with standings stats"""
    data_loader = get_data_loader()
    data_loader.load_all_data()
    analyzer = NHLAnalyzer(data_loader)

    teams = []
    for abbrev in ALL_TEAMS:
        item = TeamListItem(
            abbrev=abbrev,
            name=TEAM_FULL_NAMES.get(abbrev, abbrev),
            division=get_team_division(abbrev),
            conference=get_team_conference(abbrev),
        )
        stats = analyzer.get_team_stats(abbrev)
        if stats:
            wins = stats.get('wins', 0)
            losses = stats.get('losses', 0)
            otl = stats.get('otLosses', 0)
            gf = stats.get('goalFor', 0)
            ga = stats.get('goalAgainst', 0)
            points = stats.get('points', 0)
            total_games = wins + losses + otl
            item.wins = wins
            item.losses = losses
            item.otl = otl
            item.points = points
            item.points_pct = round(points / (total_games * 2), 3) if total_games > 0 else 0.0
            item.goals_for = gf
            item.goals_against = ga
        teams.append(item)

    teams.sort(key=lambda t: (-t.points, -t.points_pct, t.name))
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

    # Calculate advanced stats from MoneyPuck data
    advanced = calculate_advanced_stats(data_loader, abbrev)

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
        advanced_stats=advanced,
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


@router.get("/teams/{abbrev}/skaters", response_model=List[SkaterStats])
async def get_team_skaters(abbrev: str):
    """
    Get all skaters for a team from MoneyPuck season data.

    - **abbrev**: Team abbreviation (e.g., TOR, BOS, EDM)

    Returns skaters sorted by points (leaders first).
    """
    abbrev = abbrev.upper()
    if abbrev not in ALL_TEAMS:
        raise HTTPException(
            status_code=404,
            detail=f"Team '{abbrev}' not found. Valid abbreviations: {', '.join(sorted(ALL_TEAMS))}"
        )

    data_loader = get_data_loader()
    data_loader.load_all_data()

    skater_data = data_loader.skater_data
    if skater_data is None:
        raise HTTPException(status_code=500, detail="Failed to load skater data")

    team_skaters = skater_data[skater_data['team'] == abbrev]
    if team_skaters.empty:
        return []

    skaters = []
    for _, s in team_skaters.iterrows():
        goals = int(float(s.get('I_F_goals', 0)))
        assists = int(float(s.get('I_F_primaryAssists', 0)) + float(s.get('I_F_secondaryAssists', 0)))
        games = int(s.get('games_played', 0))
        icetime = float(s.get('icetime', 0))
        skaters.append(SkaterStats(
            name=str(s['name']),
            position=str(s.get('position', '?')).upper(),
            games_played=games,
            goals=goals,
            assists=assists,
            points=goals + assists,
            xgoals=round(float(s.get('I_F_xGoals', 0)), 1),
            shots=int(float(s.get('I_F_shotsOnGoal', 0))),
            toi_per_game=round((icetime / 60) / games, 1) if games > 0 else 0.0,
        ))

    skaters.sort(key=lambda sk: sk.points, reverse=True)
    return skaters


@router.get("/divisions")
async def get_divisions():
    """Get NHL division structure"""
    return {
        "divisions": NHL_DIVISIONS,
        "conferences": NHL_CONFERENCES,
    }
