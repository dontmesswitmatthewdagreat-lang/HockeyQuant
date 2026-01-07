"""
HockeyQuant Predictions Router
Endpoints for game predictions
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict
from datetime import date, datetime

from services import NHLAnalyzer, get_data_loader

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


class PredictionsResponse(BaseModel):
    date: str
    games_count: int
    predictions: List[GamePrediction]


# Shared analyzer instance
_analyzer: Optional[NHLAnalyzer] = None


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

    analyzer = get_analyzer()
    results = analyzer.analyze_date(date_str)

    if not results:
        raise HTTPException(
            status_code=404,
            detail=f"No games found for {date_str}"
        )

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

        predictions.append(GamePrediction(
            away=TeamAnalysis(**r['away']),
            home=TeamAnalysis(**r['home']),
            pick=r['pick'],
            diff=round(r['diff'], 2),
            confidence=confidence,
            factors=r.get('factors', []),
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


@router.post("/predictions/{date_str}", response_model=PredictionsResponse)
async def get_predictions_with_goalies(date_str: str, request: GoalieOverridesRequest):
    """
    Get predictions for all games on a specific date with custom goalie selections.

    - **date_str**: Date in YYYY-MM-DD format (e.g., 2025-01-06)
    - **goalie_overrides**: Dict mapping team abbreviation to goalie name
      - Example: {"TOR": "Joseph Woll", "MTL": "Sam Montembeault"}
      - Only include teams you want to override; others use auto-selected starter
    """
    # Validate date format
    try:
        parsed_date = datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="Invalid date format. Use YYYY-MM-DD (e.g., 2025-01-06)"
        )

    analyzer = get_analyzer()
    results = analyzer.analyze_date(date_str, goalie_overrides=request.goalie_overrides)

    if not results:
        raise HTTPException(
            status_code=404,
            detail=f"No games found for {date_str}"
        )

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

        predictions.append(GamePrediction(
            away=TeamAnalysis(**r['away']),
            home=TeamAnalysis(**r['home']),
            pick=r['pick'],
            diff=round(r['diff'], 2),
            confidence=confidence,
            factors=r.get('factors', []),
        ))

    return PredictionsResponse(
        date=date_str,
        games_count=len(predictions),
        predictions=predictions,
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
