"""
HockeyQuant Predictions Router
Endpoints for game predictions
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict
from datetime import date, datetime, timedelta, timezone
import asyncio
import json
import time as _time
import httpx

from services import NHLAnalyzer, get_data_loader
from services.supabase_client import get_supabase

router = APIRouter()


# Pydantic models for API requests
class GoalieOverridesRequest(BaseModel):
    """Request body for predictions with custom goalie selections"""
    goalie_overrides: Dict[str, str] = {}

    class Config:
        json_schema_extra = {
            "example": {
                "goalie_overrides": {
                    "TOR": "Joseph Woll",
                    "MTL": "Sam Montembeault"
                }
            }
        }


# Pydantic models for API responses
class GoalieInfo(BaseModel):
    name: str
    gsax: float
    sv_pct: float
    gaa: float


class TeamAnalysis(BaseModel):
    team: str
    final_score: float
    base_score: float
    goalie: str
    goalie_gsax: float
    goalie_sv_pct: float
    goalie_gaa: float
    backup_goalie: Optional[str]
    backup_goalie_gsax: Optional[float] = 0.0
    backup_goalie_sv_pct: Optional[float] = 0.900
    backup_goalie_gaa: Optional[float] = 3.0
    fatigue: str
    fatigue_mult: float
    streak: str
    streak_mult: float
    special_teams: str
    st_mult: float
    injuries: str
    injury_mult: float
    h2h: str
    h2h_mult: float


class BettingLines(BaseModel):
    """Puck line and over/under predictions with Poisson probabilities"""
    away_expected_goals: float
    home_expected_goals: float
    predicted_total: float
    predicted_margin: float          # home - away (positive = home favored)
    # Puck Line
    puck_line: float                 # official spread (home perspective, e.g., -1.5)
    puck_line_source: str            # "DraftKings", "FanDuel", or "Standard"
    puck_line_home_cover_prob: float # percentage (0-100)
    puck_line_away_cover_prob: float # percentage (0-100)
    # Optimal alternate spread
    optimal_spread: float
    optimal_spread_prob: float       # percentage (0-100)
    optimal_spread_side: str         # "home" or "away"
    # Over/Under
    over_under: float                # official total line (e.g., 6.5)
    over_under_source: str           # "DraftKings", "FanDuel", or "Model"
    over_prob: float                 # percentage (0-100)
    under_prob: float                # percentage (0-100)
    push_prob: float = 0.0           # percentage (0-100), nonzero for whole-number lines
    # Optimal alternate total
    optimal_total: float
    optimal_total_prob: float        # percentage (0-100)
    optimal_total_rec: str           # "OVER" or "UNDER"
    # Moneyline win probabilities (regulation)
    ml_home_prob: float = 0.0        # regulation win probability for home team (0-100)
    ml_away_prob: float = 0.0        # regulation win probability for away team (0-100)


class GamePrediction(BaseModel):
    away: TeamAnalysis
    home: TeamAnalysis
    pick: str
    diff: float
    confidence: str
    factors: List[str]
    # Per-game prediction timing
    game_time: Optional[str] = None           # ISO timestamp of game start (UTC)
    is_official: bool = False                 # True if within 15-min window (locked)
    official_at: Optional[str] = None         # ISO timestamp when prediction becomes official
    goalie_status_away: str = "expected"      # "confirmed" | "expected"
    goalie_status_home: str = "expected"      # "confirmed" | "expected"
    # Betting lines (puck line + over/under)
    betting_lines: Optional[BettingLines] = None


class PredictionStatus(BaseModel):
    """Status information for prediction updates"""
    last_updated: Optional[str] = None
    next_update: Optional[str] = None
    first_game_time: Optional[str] = None
    is_cached: bool = False


class PredictionsResponse(BaseModel):
    date: str
    games_count: int
    predictions: List[GamePrediction]
    status: Optional[PredictionStatus] = None


# Shared analyzer instance
_analyzer: Optional[NHLAnalyzer] = None

# date_str -> (stored_at, payload) for GET /games/{date}
_GAMES_CACHE: dict = {}
_GAMES_TTL = 900


def calculate_next_update(first_game_time_str: Optional[str], last_updated_str: Optional[str]) -> Optional[str]:
    """
    Calculate the next scheduled update time.
    Updates run every 30 min starting at 6 AM ET until 30 min before first game.
    """
    if not first_game_time_str:
        return None

    try:
        # Parse first game time (stored as UTC ISO string)
        first_game = datetime.fromisoformat(first_game_time_str.replace('Z', '+00:00'))
        cutoff = first_game - timedelta(minutes=30)
        now = datetime.utcnow()

        # If we're past the cutoff, no more updates scheduled
        if now >= cutoff:
            return None

        # Calculate next 30-min interval
        # Updates run on the :00 and :30 marks
        next_update = now.replace(second=0, microsecond=0)
        if now.minute < 30:
            next_update = next_update.replace(minute=30)
        else:
            next_update = next_update.replace(minute=0) + timedelta(hours=1)

        # Don't schedule past the cutoff
        if next_update >= cutoff:
            return None

        return next_update.isoformat() + 'Z'
    except Exception:
        return None


def get_analyzer() -> NHLAnalyzer:
    """Get or create analyzer instance"""
    global _analyzer
    if _analyzer is None:
        data_loader = get_data_loader()
        data_loader.load_all_data()
        _analyzer = NHLAnalyzer(data_loader)
    return _analyzer


@router.get("/predictions/{date_str}", response_model=PredictionsResponse)
async def get_predictions(date_str: str):
    """
    Get predictions for all games on a specific date.
    First checks for pre-computed predictions in database, then falls back to on-demand computation.

    - **date_str**: Date in YYYY-MM-DD format (e.g., 2025-01-06)
    """
    # Validate date format
    try:
        parsed_date = datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="Invalid date format. Use YYYY-MM-DD (e.g., 2025-01-06)"
        )

    # Check for pre-computed predictions in database first
    supabase = get_supabase()
    if supabase:
        try:
            result = supabase.table("daily_predictions").select("*").eq("game_date", date_str).execute()
            if result.data and len(result.data) > 0:
                cached = result.data[0]
                cached_predictions = cached.get("predictions", [])

                # Build status info
                last_updated = cached.get("updated_at")
                first_game_time = cached.get("first_game_time")
                next_update = calculate_next_update(first_game_time, last_updated)

                status = PredictionStatus(
                    last_updated=last_updated,
                    next_update=next_update,
                    first_game_time=first_game_time,
                    is_cached=True,
                )

                # Recalculate is_official based on current time for each prediction
                now = datetime.now(timezone.utc)
                updated_predictions = []
                for p in cached_predictions:
                    game_time_str = p.get('game_time')
                    is_official = p.get('is_official', False)
                    official_at_str = p.get('official_at')

                    # Recalculate is_official if we have game_time
                    if game_time_str:
                        try:
                            game_time = datetime.fromisoformat(game_time_str.replace('Z', '+00:00'))
                            official_at = game_time - timedelta(minutes=15)
                            official_at_str = official_at.isoformat().replace('+00:00', 'Z')
                            is_official = now >= official_at
                        except Exception:
                            pass

                    # Update the prediction with recalculated values
                    p['is_official'] = is_official
                    p['official_at'] = official_at_str
                    updated_predictions.append(GamePrediction(**p))

                # Return pre-computed predictions with updated official status
                return PredictionsResponse(
                    date=date_str,
                    games_count=cached.get("games_count", len(cached_predictions)),
                    predictions=updated_predictions,
                    status=status,
                )
        except Exception as e:
            # Log error but continue to on-demand computation
            print(f"Error fetching cached predictions: {e}")

    # Fall back to on-demand computation
    analyzer = get_analyzer()
    results = analyzer.analyze_date(date_str)

    if not results:
        raise HTTPException(
            status_code=404,
            detail=f"No games found for {date_str}"
        )

    # Current time for determining official status
    now = datetime.now(timezone.utc)

    # Transform results to API response format
    predictions = []
    for r in results:
        # Determine confidence level
        if r['diff'] >= 10:
            confidence = "STRONG"
        elif r['diff'] >= 5:
            confidence = "MODERATE"
        else:
            confidence = "CLOSE"

        # Get game time and calculate official status
        game_time_str = r.get('game_time')
        is_official = False
        official_at_str = None

        if game_time_str:
            try:
                game_time = datetime.fromisoformat(game_time_str.replace('Z', '+00:00'))
                official_at = game_time - timedelta(minutes=15)
                official_at_str = official_at.isoformat().replace('+00:00', 'Z')
                is_official = now >= official_at
            except Exception:
                pass

        # Build betting lines if available
        betting_lines_data = r.get('betting_lines')
        betting_lines = BettingLines(**betting_lines_data) if betting_lines_data else None

        predictions.append(GamePrediction(
            away=TeamAnalysis(**r['away']),
            home=TeamAnalysis(**r['home']),
            pick=r['pick'],
            diff=round(r['diff'], 2),
            confidence=confidence,
            factors=r.get('factors', []),
            game_time=game_time_str,
            is_official=is_official,
            official_at=official_at_str,
            goalie_status_away=r.get('goalie_status_away', 'expected'),
            goalie_status_home=r.get('goalie_status_home', 'expected'),
            betting_lines=betting_lines,
        ))

    return PredictionsResponse(
        date=date_str,
        games_count=len(predictions),
        predictions=predictions,
    )


@router.get("/predictions/today", response_model=PredictionsResponse)
async def get_today_predictions():
    """Get predictions for today's games"""
    today = date.today().strftime("%Y-%m-%d")
    return await get_predictions(today)


@router.post("/predictions/{date_str}")
async def get_predictions_with_goalies(date_str: str, request: GoalieOverridesRequest):
    """
    DISABLED: Goalie overrides are not available for the official model.
    Custom models with goalie selection coming soon.
    """
    raise HTTPException(
        status_code=403,
        detail="Goalie overrides are disabled for the official model. Custom models coming soon."
    )


@router.get("/games/{date_str}")
async def get_games(date_str: str):
    """
    Get list of games scheduled for a specific date (without full predictions).

    - **date_str**: Date in YYYY-MM-DD format
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="Invalid date format. Use YYYY-MM-DD"
        )

    # A date's schedule barely moves once published, but every call here was a
    # fresh NHL API round-trip — including the repeat hits from scrubbing the
    # date strip in the UI. Short TTL so a postponement still lands same-day.
    cached = _GAMES_CACHE.get(date_str)
    if cached and _time.time() - cached[0] < _GAMES_TTL:
        return cached[1]

    analyzer = get_analyzer()
    games = analyzer.get_games_for_date(date_str)

    payload = {
        "date": date_str,
        "games_count": len(games),
        "games": [
            {"away": g['away'], "home": g['home']}
            for g in games
        ]
    }
    if games:              # never cache an empty slate from a failed fetch
        _GAMES_CACHE[date_str] = (_time.time(), payload)
    return payload


@router.get("/predictions/status/{date_str}", response_model=PredictionStatus)
async def get_prediction_status(date_str: str):
    """
    Get status information for predictions on a specific date.
    Lightweight endpoint for polling update times.

    - **date_str**: Date in YYYY-MM-DD format
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="Invalid date format. Use YYYY-MM-DD"
        )

    supabase = get_supabase()
    if not supabase:
        return PredictionStatus(is_cached=False)

    try:
        result = supabase.table("daily_predictions").select(
            "updated_at, first_game_time"
        ).eq("game_date", date_str).execute()

        if result.data and len(result.data) > 0:
            cached = result.data[0]
            last_updated = cached.get("updated_at")
            first_game_time = cached.get("first_game_time")
            next_update = calculate_next_update(first_game_time, last_updated)

            return PredictionStatus(
                last_updated=last_updated,
                next_update=next_update,
                first_game_time=first_game_time,
                is_cached=True,
            )
    except Exception as e:
        print(f"Error fetching prediction status: {e}")

    return PredictionStatus(is_cached=False)


# ---------------------------------------------------------------------------
# Live / final scores
# ---------------------------------------------------------------------------
_SCORE_CACHE: dict = {}
_SCORE_TTL = 30  # seconds

# Month -> (fetched_at, payload). A month's schedule barely moves, so this is
# cached far longer than live scores. Bounded because the key comes from the
# request path: a caller walking years would otherwise grow it without limit.
_MONTH_COUNT_CACHE: dict = {}
_MONTH_COUNT_TTL = 3600
_MONTH_COUNT_MAX = 64


@router.get("/games/counts/{month}")
async def get_month_game_counts(month: str):
    """How many games fall on each day of a month, in a single request.

    The Schedule tab draws a dot on every day that has games, and it used to
    answer that one request per day — 21 for the day strip and ~31 more for
    every month the calendar scrolled, all fired at once. That saturated the
    worker pool and starved the prediction request the screen was actually
    waiting on, so the screen hung on placeholders.

    The NHL's schedule endpoint already answers a whole week at a time, so a
    month costs about five upstream calls made concurrently here instead of 31
    made serially from a phone.

    Days the upstream never mentions are reported as 0 rather than omitted, so
    the client can tell "no games" apart from "not loaded yet".
    """
    try:
        start = datetime.strptime(month, "%Y-%m").date()
    except ValueError:
        raise HTTPException(status_code=400,
                            detail="Use YYYY-MM (e.g. 2026-05)")

    now = _time.time()
    hit = _MONTH_COUNT_CACHE.get(month)
    if hit and now - hit[0] < _MONTH_COUNT_TTL:
        return hit[1]

    # Last day of the month, without pulling in calendar just for this.
    next_month = (start.replace(day=28) + timedelta(days=4)).replace(day=1)
    last_day = (next_month - timedelta(days=1)).day

    # The endpoint returns the week *containing* the date it's given, so step a
    # week at a time from the 1st until the month is covered.
    anchors, cursor = [], start
    while cursor.month == start.month:
        anchors.append(cursor.isoformat())
        cursor += timedelta(days=7)

    counts: Dict[str, int] = {}
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            responses = await asyncio.gather(
                *(client.get(f"https://api-web.nhle.com/v1/schedule/{a}")
                  for a in anchors),
                return_exceptions=True,
            )
    except Exception as e:
        print(f"Error fetching month counts for {month}: {e}")
        responses = []

    for resp in responses:
        # One bad week shouldn't blank the whole month — take what came back.
        if isinstance(resp, BaseException) or resp.status_code != 200:
            continue
        try:
            week = resp.json().get("gameWeek", [])
        except Exception:
            continue
        for day in week:
            day_str = day.get("date")
            if day_str and day_str.startswith(month):
                counts[day_str] = day.get("numberOfGames", 0)

    result = {
        "month": month,
        "counts": {
            start.replace(day=d).isoformat(): counts.get(
                start.replace(day=d).isoformat(), 0)
            for d in range(1, last_day + 1)
        },
    }
    if len(_MONTH_COUNT_CACHE) >= _MONTH_COUNT_MAX:
        _MONTH_COUNT_CACHE.clear()
    _MONTH_COUNT_CACHE[month] = (now, result)
    return result


@router.get("/games/{date_str}/scores")
async def get_game_scores(date_str: str):
    """
    Live and final scores for all games on a date, sourced from the NHL API.
    Results are cached for 30 seconds to avoid hammering the upstream API.
    """
    now = _time.time()
    if date_str in _SCORE_CACHE:
        ts, data = _SCORE_CACHE[date_str]
        if now - ts < _SCORE_TTL:
            return data

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"https://api-web.nhle.com/v1/score/{date_str}",
                timeout=10,
            )
        if resp.status_code != 200:
            return {"games": []}
        raw = resp.json()
    except Exception as e:
        print(f"Error fetching live scores for {date_str}: {e}")
        return {"games": []}

    games = []
    for g in raw.get("games", []):
        state = g.get("gameState", "SCHEDULED")
        away = g.get("awayTeam", {})
        home = g.get("homeTeam", {})
        period_desc = g.get("periodDescriptor", {})
        clock = g.get("clock", {})
        games.append({
            "away_team": away.get("abbrev"),
            "home_team": home.get("abbrev"),
            "away_score": away.get("score", 0),
            "home_score": home.get("score", 0),
            "game_state": state,
            "period": period_desc.get("number"),
            "period_type": period_desc.get("periodType", "REG"),
            "time_remaining": clock.get("timeRemaining"),
            "in_intermission": clock.get("inIntermission", False),
        })

    result = {"games": games}
    _SCORE_CACHE[date_str] = (now, result)
    return result
