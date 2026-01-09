"""
HockeyQuant Accuracy Router
Endpoints for tracking prediction accuracy
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List, Optional
from datetime import date, datetime, timedelta

from services import NHLAnalyzer, get_data_loader
from services.supabase_client import get_supabase
from services.results_fetcher import fetch_game_results, get_first_game_time

router = APIRouter()


# Pydantic models
class PredictionRecord(BaseModel):
    game_date: str
    game_id: str
    away_team: str
    home_team: str
    away_score: float
    home_score: float
    pick: str
    confidence: str
    diff: float
    away_final: Optional[int] = None
    home_final: Optional[int] = None
    actual_winner: Optional[str] = None
    correct: Optional[bool] = None


class AccuracyStats(BaseModel):
    total_games: int
    correct_picks: int
    accuracy_pct: float
    strong_total: int
    strong_correct: int
    strong_pct: float
    moderate_total: int
    moderate_correct: int
    moderate_pct: float
    close_total: int
    close_correct: int
    close_pct: float


class AccuracyResponse(BaseModel):
    stats: AccuracyStats
    recent_predictions: List[PredictionRecord]


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


@router.post("/accuracy/store-predictions/{date_str}")
async def store_predictions(date_str: str):
    """
    Store predictions for a specific date.
    Called by cron job 15 min before first game.

    - **date_str**: Date in YYYY-MM-DD format
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    # Get predictions from analyzer
    analyzer = get_analyzer()
    results = analyzer.analyze_date(date_str)

    if not results:
        return {"message": f"No games found for {date_str}", "stored": 0}

    # Connect to Supabase
    supabase = get_supabase()

    # Check if predictions already exist for this date
    existing = supabase.table("predictions").select("id").eq("game_date", date_str).execute()

    if existing.data and len(existing.data) > 0:
        return {"message": f"Predictions already stored for {date_str}", "stored": 0}

    # Prepare records for insertion
    records = []
    for r in results:
        # Determine confidence level
        diff = r['diff']
        if diff >= 10:
            confidence = "STRONG"
        elif diff >= 5:
            confidence = "MODERATE"
        else:
            confidence = "CLOSE"

        # Create a game_id from teams and date
        game_id = f"{date_str}_{r['away']['team']}_{r['home']['team']}"

        records.append({
            "game_date": date_str,
            "game_id": game_id,
            "away_team": r['away']['team'],
            "home_team": r['home']['team'],
            "away_score": r['away']['final_score'],
            "home_score": r['home']['final_score'],
            "pick": r['pick'],
            "confidence": confidence,
            "diff": round(diff, 2),
        })

    # Insert records
    try:
        result = supabase.table("predictions").insert(records).execute()
        return {"message": f"Stored {len(records)} predictions for {date_str}", "stored": len(records)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to store predictions: {str(e)}")


@router.post("/accuracy/update-results/{date_str}")
async def update_results(date_str: str):
    """
    Fetch game results and update predictions for a specific date.
    Called by nightly cron job.

    - **date_str**: Date in YYYY-MM-DD format
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    # Fetch results from NHL API
    results = fetch_game_results(date_str)

    if not results:
        return {"message": f"No completed games found for {date_str}", "updated": 0}

    # Connect to Supabase
    supabase = get_supabase()

    updated_count = 0

    for game_result in results:
        # Find matching prediction
        game_id = f"{date_str}_{game_result['away_team']}_{game_result['home_team']}"

        # Get the prediction record
        pred = supabase.table("predictions").select("*").eq("game_id", game_id).execute()

        if not pred.data or len(pred.data) == 0:
            continue

        prediction = pred.data[0]

        # Determine if prediction was correct
        correct = prediction['pick'] == game_result['actual_winner']

        # Update the record
        update_data = {
            "away_final": game_result['away_final'],
            "home_final": game_result['home_final'],
            "actual_winner": game_result['actual_winner'],
            "correct": correct,
        }

        try:
            supabase.table("predictions").update(update_data).eq("game_id", game_id).execute()
            updated_count += 1
        except Exception as e:
            print(f"Error updating {game_id}: {e}")

    return {"message": f"Updated {updated_count} results for {date_str}", "updated": updated_count}


@router.post("/accuracy/update-all-pending")
async def update_all_pending():
    """
    Update results for all predictions that don't have results yet.
    Useful for catching up on missed updates.
    """
    supabase = get_supabase()

    # Get all predictions without results
    pending = supabase.table("predictions").select("game_date").is_("correct", "null").execute()

    if not pending.data:
        return {"message": "No pending predictions to update", "updated": 0}

    # Get unique dates
    dates = list(set([p['game_date'] for p in pending.data]))

    total_updated = 0
    for date_str in dates:
        result = await update_results(date_str)
        total_updated += result.get("updated", 0)

    return {"message": f"Updated {total_updated} results across {len(dates)} dates", "updated": total_updated}


@router.get("/accuracy/stats", response_model=AccuracyResponse)
async def get_accuracy_stats(
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    team: Optional[str] = Query(None, description="Filter by team picked to win"),
    confidence: Optional[str] = Query(None, description="Filter by confidence level"),
):
    """
    Get accuracy statistics with optional filters.

    - **start_date**: Filter predictions from this date
    - **end_date**: Filter predictions until this date
    - **team**: Filter by team that was picked to win
    - **confidence**: Filter by confidence level (STRONG, MODERATE, CLOSE)
    """
    supabase = get_supabase()

    # Build query - only include predictions with results
    query = supabase.table("predictions").select("*").not_is("correct", "null")

    if start_date:
        query = query.gte("game_date", start_date)
    if end_date:
        query = query.lte("game_date", end_date)
    if team:
        query = query.eq("pick", team.upper())
    if confidence:
        query = query.eq("confidence", confidence.upper())

    # Order by date descending
    query = query.order("game_date", desc=True)

    result = query.execute()
    predictions = result.data or []

    # Calculate stats
    total = len(predictions)
    correct = sum(1 for p in predictions if p.get('correct'))

    strong = [p for p in predictions if p.get('confidence') == 'STRONG']
    moderate = [p for p in predictions if p.get('confidence') == 'MODERATE']
    close = [p for p in predictions if p.get('confidence') == 'CLOSE']

    stats = AccuracyStats(
        total_games=total,
        correct_picks=correct,
        accuracy_pct=round((correct / total * 100) if total > 0 else 0, 1),
        strong_total=len(strong),
        strong_correct=sum(1 for p in strong if p.get('correct')),
        strong_pct=round((sum(1 for p in strong if p.get('correct')) / len(strong) * 100) if strong else 0, 1),
        moderate_total=len(moderate),
        moderate_correct=sum(1 for p in moderate if p.get('correct')),
        moderate_pct=round((sum(1 for p in moderate if p.get('correct')) / len(moderate) * 100) if moderate else 0, 1),
        close_total=len(close),
        close_correct=sum(1 for p in close if p.get('correct')),
        close_pct=round((sum(1 for p in close if p.get('correct')) / len(close) * 100) if close else 0, 1),
    )

    # Get recent predictions (limit to 50)
    recent = predictions[:50]
    recent_records = [
        PredictionRecord(
            game_date=p['game_date'],
            game_id=p['game_id'],
            away_team=p['away_team'],
            home_team=p['home_team'],
            away_score=p['away_score'],
            home_score=p['home_score'],
            pick=p['pick'],
            confidence=p['confidence'],
            diff=p['diff'],
            away_final=p.get('away_final'),
            home_final=p.get('home_final'),
            actual_winner=p.get('actual_winner'),
            correct=p.get('correct'),
        )
        for p in recent
    ]

    return AccuracyResponse(stats=stats, recent_predictions=recent_records)


@router.get("/accuracy/first-game-time/{date_str}")
async def get_first_game_time_endpoint(date_str: str):
    """
    Get the start time of the first game on a given date.
    Useful for scheduling the prediction storage job.

    - **date_str**: Date in YYYY-MM-DD format
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    first_game = get_first_game_time(date_str)

    if first_game:
        return {
            "date": date_str,
            "first_game_utc": first_game.isoformat(),
            "store_predictions_at": (first_game - timedelta(minutes=15)).isoformat(),
        }
    else:
        return {"date": date_str, "first_game_utc": None, "message": "No games scheduled"}
