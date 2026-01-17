"""
HockeyQuant Predictions Router
Endpoints for game predictions
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict
from datetime import date, datetime, timedelta, timezone
import json

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


class GamePrediction(BaseModel):
    away: TeamAnalysis
    home: TeamAnalysis
    pick: str
    diff: float
    confidence: str
    factors: List[str]
    # New fields for per-game prediction timing
    game_time: Optional[str] = None           # ISO timestamp of game start (UTC)
    is_official: bool = False                 # True if within 15-min window (locked)
    official_at: Optional[str] = None         # ISO timestamp when prediction becomes official
    goalie_status_away: str = "expected"      # "confirmed" | "expected"
    goalie_status_home: str = "expected"      # "confirmed" | "expected"


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

    analyzer = get_analyzer()
    games = analyzer.get_games_for_date(date_str)

    return {
        "date": date_str,
        "games_count": len(games),
        "games": [
            {"away": g['away'], "home": g['home']}
            for g in games
        ]
    }


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
