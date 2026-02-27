"""
HockeyQuant Accuracy Router
Endpoints for tracking prediction accuracy
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Any, Dict, List, Optional
from datetime import date, datetime, timedelta, timezone

from services import NHLAnalyzer, get_data_loader
from services.supabase_client import get_supabase
from services.results_fetcher import fetch_game_results, get_first_game_time, get_last_game_time
from services.goal_predictor import calc_spread_prob, calc_over_under_prob

router = APIRouter()


@router.get("/accuracy/debug")
async def debug_supabase():
    """Debug endpoint to test Supabase connection"""
    import os
    url = os.getenv("SUPABASE_URL", "NOT SET")
    key = os.getenv("SUPABASE_SERVICE_KEY", "NOT SET")

    result = {
        "url_set": url != "NOT SET" and len(url) > 0,
        "key_set": key != "NOT SET" and len(key) > 0,
        "url_len": len(url) if url != "NOT SET" else 0,
        "key_len": len(key) if key != "NOT SET" else 0,
    }

    if result["url_set"] and result["key_set"]:
        try:
            from services.supabase_client import get_supabase
            client = get_supabase()
            result["client_created"] = True

            # Try a simple query
            test = client.table("predictions").select("id").limit(1).execute()
            result["query_success"] = True
            result["query_result"] = len(test.data)
        except Exception as e:
            result["error"] = str(e)

    return result


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
    # Puck line tracking
    puck_line_pick: Optional[str] = None      # "home" or "away"
    puck_line_line: Optional[float] = None    # home-perspective line (e.g., -1.5)
    puck_line_correct: Optional[bool] = None
    # Over/Under tracking
    ou_pick: Optional[str] = None             # "over" or "under"
    ou_line: Optional[float] = None           # total line (e.g., 6.5)
    ou_correct: Optional[bool] = None


class WindowStats(BaseModel):
    correct: int
    total: int
    pct: float


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
    # Multi-window stats
    rolling_30: Optional[WindowStats] = None
    current_season: Optional[WindowStats] = None
    all_time: Optional[WindowStats] = None
    # Puck line accuracy
    puck_line_total: int = 0
    puck_line_correct_count: int = 0
    puck_line_pct: float = 0.0
    puck_line_strong_total: int = 0
    puck_line_strong_correct: int = 0
    puck_line_strong_pct: float = 0.0
    puck_line_moderate_total: int = 0
    puck_line_moderate_correct: int = 0
    puck_line_moderate_pct: float = 0.0
    puck_line_close_total: int = 0
    puck_line_close_correct: int = 0
    puck_line_close_pct: float = 0.0
    # Over/Under accuracy
    ou_total: int = 0
    ou_correct_count: int = 0
    ou_pct: float = 0.0
    ou_strong_total: int = 0
    ou_strong_correct: int = 0
    ou_strong_pct: float = 0.0
    ou_moderate_total: int = 0
    ou_moderate_correct: int = 0
    ou_moderate_pct: float = 0.0
    ou_close_total: int = 0
    ou_close_correct: int = 0
    ou_close_pct: float = 0.0


class AccuracyResponse(BaseModel):
    stats: AccuracyStats
    recent_predictions: List[PredictionRecord]


class TrendDataPoint(BaseModel):
    date: str
    rolling_accuracy: float
    games_in_window: int
    cumulative_accuracy: float
    cumulative_games: int


class TrendResponse(BaseModel):
    window_size: int
    total_games: int
    data_points: List[TrendDataPoint]


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
    Store official predictions for games within the 15-min window.
    Called by cron job every 10 minutes.

    For each game:
    - If current_time >= game_time - 15 minutes AND not already stored:
      - Store to predictions table (locked for accuracy tracking)
    - Always updates daily_predictions cache with ALL games (for API serving)

    - **date_str**: Date in YYYY-MM-DD format
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    try:
        # Get predictions from analyzer (includes game_time and goalie_status)
        analyzer = get_analyzer()
        results = analyzer.analyze_date(date_str)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analyzer error: {str(e)}")

    if not results:
        return {"message": f"No games found for {date_str}", "stored": 0}

    # Connect to Supabase
    try:
        supabase = get_supabase()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase init error: {str(e)}")

    # Get current time for 15-min window check
    now = datetime.now(timezone.utc)

    # Get existing predictions for this date (to avoid duplicates)
    try:
        existing_preds = supabase.table("predictions").select("game_id").eq("game_date", date_str).execute()
        existing_game_ids = set(p['game_id'] for p in existing_preds.data) if existing_preds.data else set()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase query error: {str(e)}")

    # Check if cache exists
    try:
        existing_cache = supabase.table("daily_predictions").select("id").eq("game_date", date_str).execute()
        cache_exists = existing_cache.data and len(existing_cache.data) > 0
    except Exception as e:
        cache_exists = False

    # Process each game - only store to flat table if within 15-min window
    stored_flat = 0
    full_predictions = []

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

        # Check if within 15-min window
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

        # Store to flat predictions table ONLY if:
        # 1. Within 15-min window (is_official)
        # 2. Not already stored
        if is_official and game_id not in existing_game_ids:
            # Extract puck line pick from betting_lines
            bl = r.get('betting_lines') or {}
            if not bl:
                print(f"WARNING: No betting_lines for {game_id} — puck line and O/U picks will be NULL")
            puck_line_pick = None
            puck_line_line = None
            if bl:
                puck_line_line = bl.get('puck_line')
                home_cover_prob = bl.get('puck_line_home_cover_prob', 0)
                away_cover_prob = bl.get('puck_line_away_cover_prob', 0)
                puck_line_pick = 'home' if home_cover_prob >= away_cover_prob else 'away'

            # Extract O/U pick from betting_lines
            ou_pick = None
            ou_line = None
            if bl:
                ou_line = bl.get('over_under')
                over_prob = bl.get('over_prob', 0)
                under_prob = bl.get('under_prob', 0)
                ou_pick = 'over' if over_prob >= under_prob else 'under'

            record = {
                "game_date": date_str,
                "game_id": game_id,
                "away_team": r['away']['team'],
                "home_team": r['home']['team'],
                "away_score": r['away']['final_score'],
                "home_score": r['home']['final_score'],
                "pick": r['pick'],
                "confidence": confidence,
                "diff": round(diff, 2),
                "predicted_at": now.isoformat(),
                "goalie_confirmed_away": r.get('goalie_status_away') == 'confirmed',
                "goalie_confirmed_home": r.get('goalie_status_home') == 'confirmed',
                "puck_line_pick": puck_line_pick,
                "puck_line_line": puck_line_line,
                "ou_pick": ou_pick,
                "ou_line": ou_line,
            }
            try:
                supabase.table("predictions").insert([record])
                stored_flat += 1
                existing_game_ids.add(game_id)  # Track to avoid duplicate attempts
            except Exception as e:
                print(f"Failed to store prediction for {game_id}: {e}")

        # Always include in full predictions for cache (regardless of official status)
        full_predictions.append({
            "away": r['away'],
            "home": r['home'],
            "pick": r['pick'],
            "diff": round(diff, 2),
            "confidence": confidence,
            "factors": r.get('factors', []),
            "game_time": game_time_str,
            "is_official": is_official,
            "official_at": official_at_str,
            "goalie_status_away": r.get('goalie_status_away', 'expected'),
            "goalie_status_home": r.get('goalie_status_home', 'expected'),
            "betting_lines": r.get('betting_lines'),
        })

    # Get first game time for this date
    first_game_time = get_first_game_time(date_str)
    first_game_iso = first_game_time.isoformat() if first_game_time else None

    # Insert or update daily_predictions table for instant API responses
    # Always update to refresh the cache with latest predictions and statuses
    stored_cache = False
    try:
        daily_record = {
            "game_date": date_str,
            "games_count": len(full_predictions),
            "predictions": full_predictions,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "first_game_time": first_game_iso,
        }
        if cache_exists:
            # Update existing record
            supabase.table("daily_predictions").update(daily_record).eq("game_date", date_str).execute()
        else:
            # Insert new record
            supabase.table("daily_predictions").insert([daily_record])
        stored_cache = True
    except Exception as e:
        # Log but don't fail - the flat predictions are more important
        print(f"Warning: Failed to store daily_predictions cache: {str(e)}")

    # Count official games
    official_count = sum(1 for p in full_predictions if p.get('is_official'))
    pending_count = len(full_predictions) - official_count

    message_parts = []
    if stored_flat > 0:
        message_parts.append(f"locked {stored_flat} official predictions")
    if stored_cache:
        if cache_exists:
            message_parts.append("cache updated")
        else:
            message_parts.append("cache created")
    message_parts.append(f"{official_count} official, {pending_count} pending")

    return {
        "message": f"{date_str}: {', '.join(message_parts)}",
        "stored": stored_flat,
        "official_count": official_count,
        "pending_count": pending_count,
        "cached": stored_cache,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "first_game_time": first_game_iso,
    }


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

        # Determine if moneyline prediction was correct
        correct = prediction['pick'] == game_result['actual_winner']

        home_final = game_result['home_final']
        away_final = game_result['away_final']

        # Determine puck line correctness
        # margin + line > 0 means home covered (e.g., margin=2, line=-1.5 → 0.5 > 0)
        puck_line_correct = None
        if prediction.get('puck_line_pick') and prediction.get('puck_line_line') is not None:
            margin = home_final - away_final
            line = float(prediction['puck_line_line'])
            home_covers = (margin + line) > 0
            puck_line_correct = home_covers if prediction['puck_line_pick'] == 'home' else not home_covers

        # Determine O/U correctness (push = null, not counted)
        ou_correct = None
        if prediction.get('ou_pick') and prediction.get('ou_line') is not None:
            total = home_final + away_final
            ou_line = float(prediction['ou_line'])
            if total != ou_line:
                ou_correct = (total > ou_line) if prediction['ou_pick'] == 'over' else (total < ou_line)

        # Update the record
        update_data = {
            "away_final": away_final,
            "home_final": home_final,
            "actual_winner": game_result['actual_winner'],
            "correct": correct,
            "puck_line_correct": puck_line_correct,
            "ou_correct": ou_correct,
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
    Update results for all predictions that don't have results yet,
    and backfill any missing puck line/O/U grades.
    """
    supabase = get_supabase()

    # Step 1: Grade predictions missing moneyline results
    pending = supabase.table("predictions").select("game_date").is_("correct", "null").execute()

    dates = list(set([p['game_date'] for p in pending.data])) if pending.data else []

    total_updated = 0
    for date_str in dates:
        result = await update_results(date_str)
        total_updated += result.get("updated", 0)

    # Step 2: Backfill any predictions with results but missing PL/O/U grades
    backfill_result = {"updated_picks": 0, "updated_grades": 0}
    try:
        backfill_result = await backfill_predictions()
    except Exception as e:
        print(f"Backfill error during update-all-pending: {e}")

    return {
        "message": f"Updated {total_updated} results across {len(dates)} dates. Backfill: {backfill_result.get('updated_picks', 0)} picks, {backfill_result.get('updated_grades', 0)} grades.",
        "updated": total_updated,
        "backfill_picks": backfill_result.get("updated_picks", 0),
        "backfill_grades": backfill_result.get("updated_grades", 0),
    }


@router.get("/accuracy/stats")
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
    try:
        supabase = get_supabase()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase init error: {str(e)}")

    # Build query - only include predictions with results
    try:
        query = supabase.table("predictions").select("*").not_is("correct", "null")

        if start_date:
            query = query.gte("game_date", start_date)
        if end_date:
            query = query.lte("game_date", end_date)
        if team:
            t = team.upper()
            query = query.or_(f"away_team.eq.{t},home_team.eq.{t}")
        if confidence:
            query = query.eq("confidence", confidence.upper())

        # Order by date descending
        query = query.order("game_date", desc=True)

        result = query.execute()
        predictions = result.data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase query error: {str(e)}")

    # Calculate stats
    total = len(predictions)
    correct = sum(1 for p in predictions if p.get('correct'))

    strong = [p for p in predictions if p.get('confidence') == 'STRONG']
    moderate = [p for p in predictions if p.get('confidence') == 'MODERATE']
    close = [p for p in predictions if p.get('confidence') == 'CLOSE']

    # Calculate multi-window stats (respects team filter, ignores other filters)
    try:
        all_completed_query = supabase.table("predictions").select("*").not_is("correct", "null").order("game_date", desc=True)
        if team:
            t = team.upper()
            all_completed_query = all_completed_query.or_(f"away_team.eq.{t},home_team.eq.{t}")
        all_preds = all_completed_query.execute().data or []
    except Exception:
        all_preds = predictions

    # All-time stats
    all_time_total = len(all_preds)
    all_time_correct = sum(1 for p in all_preds if p.get('correct'))
    all_time_stats = WindowStats(
        correct=all_time_correct,
        total=all_time_total,
        pct=round((all_time_correct / all_time_total * 100) if all_time_total > 0 else 0, 1)
    )

    # Rolling 30 games (most recent 30)
    last_30 = all_preds[:30]
    rolling_30_correct = sum(1 for p in last_30 if p.get('correct'))
    rolling_30_stats = WindowStats(
        correct=rolling_30_correct,
        total=len(last_30),
        pct=round((rolling_30_correct / len(last_30) * 100) if last_30 else 0, 1)
    )

    # Current season stats (Oct 1 - Jun 30)
    today = date.today()
    if today.month >= 10:
        season_start = date(today.year, 10, 1)
        season_end = date(today.year + 1, 6, 30)
    else:
        season_start = date(today.year - 1, 10, 1)
        season_end = date(today.year, 6, 30)

    season_preds = [p for p in all_preds if season_start.isoformat() <= p['game_date'] <= season_end.isoformat()]
    season_correct = sum(1 for p in season_preds if p.get('correct'))
    current_season_stats = WindowStats(
        correct=season_correct,
        total=len(season_preds),
        pct=round((season_correct / len(season_preds) * 100) if season_preds else 0, 1)
    )

    def _pct(correct_count, total_count):
        return round((correct_count / total_count * 100) if total_count > 0 else 0, 1)

    # Puck line stats — only predictions where puck_line_correct is not null
    pl_preds = [p for p in predictions if p.get('puck_line_correct') is not None]
    pl_strong = [p for p in pl_preds if p.get('confidence') == 'STRONG']
    pl_moderate = [p for p in pl_preds if p.get('confidence') == 'MODERATE']
    pl_close = [p for p in pl_preds if p.get('confidence') == 'CLOSE']

    # O/U stats — only predictions where ou_correct is not null
    ou_preds = [p for p in predictions if p.get('ou_correct') is not None]
    ou_strong = [p for p in ou_preds if p.get('confidence') == 'STRONG']
    ou_moderate = [p for p in ou_preds if p.get('confidence') == 'MODERATE']
    ou_close = [p for p in ou_preds if p.get('confidence') == 'CLOSE']

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
        rolling_30=rolling_30_stats,
        current_season=current_season_stats,
        all_time=all_time_stats,
        # Puck line
        puck_line_total=len(pl_preds),
        puck_line_correct_count=sum(1 for p in pl_preds if p.get('puck_line_correct')),
        puck_line_pct=_pct(sum(1 for p in pl_preds if p.get('puck_line_correct')), len(pl_preds)),
        puck_line_strong_total=len(pl_strong),
        puck_line_strong_correct=sum(1 for p in pl_strong if p.get('puck_line_correct')),
        puck_line_strong_pct=_pct(sum(1 for p in pl_strong if p.get('puck_line_correct')), len(pl_strong)),
        puck_line_moderate_total=len(pl_moderate),
        puck_line_moderate_correct=sum(1 for p in pl_moderate if p.get('puck_line_correct')),
        puck_line_moderate_pct=_pct(sum(1 for p in pl_moderate if p.get('puck_line_correct')), len(pl_moderate)),
        puck_line_close_total=len(pl_close),
        puck_line_close_correct=sum(1 for p in pl_close if p.get('puck_line_correct')),
        puck_line_close_pct=_pct(sum(1 for p in pl_close if p.get('puck_line_correct')), len(pl_close)),
        # Over/Under
        ou_total=len(ou_preds),
        ou_correct_count=sum(1 for p in ou_preds if p.get('ou_correct')),
        ou_pct=_pct(sum(1 for p in ou_preds if p.get('ou_correct')), len(ou_preds)),
        ou_strong_total=len(ou_strong),
        ou_strong_correct=sum(1 for p in ou_strong if p.get('ou_correct')),
        ou_strong_pct=_pct(sum(1 for p in ou_strong if p.get('ou_correct')), len(ou_strong)),
        ou_moderate_total=len(ou_moderate),
        ou_moderate_correct=sum(1 for p in ou_moderate if p.get('ou_correct')),
        ou_moderate_pct=_pct(sum(1 for p in ou_moderate if p.get('ou_correct')), len(ou_moderate)),
        ou_close_total=len(ou_close),
        ou_close_correct=sum(1 for p in ou_close if p.get('ou_correct')),
        ou_close_pct=_pct(sum(1 for p in ou_close if p.get('ou_correct')), len(ou_close)),
    )

    # Get ALL recent predictions (including pending) for the table
    try:
        all_query = supabase.table("predictions").select("*").order("game_date", desc=True).limit(50)
        if start_date:
            all_query = all_query.gte("game_date", start_date)
        if end_date:
            all_query = all_query.lte("game_date", end_date)
        if team:
            t = team.upper()
            all_query = all_query.or_(f"away_team.eq.{t},home_team.eq.{t}")
        if confidence:
            all_query = all_query.eq("confidence", confidence.upper())
        all_result = all_query.execute()
        all_predictions = all_result.data or []
    except Exception as e:
        all_predictions = predictions  # Fallback to completed only

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
            puck_line_pick=p.get('puck_line_pick'),
            puck_line_line=p.get('puck_line_line'),
            puck_line_correct=p.get('puck_line_correct'),
            ou_pick=p.get('ou_pick'),
            ou_line=p.get('ou_line'),
            ou_correct=p.get('ou_correct'),
        )
        for p in all_predictions[:50]
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


@router.get("/accuracy/last-game-time/{date_str}")
async def get_last_game_time_endpoint(date_str: str):
    """
    Get the start time of the last game on a given date.
    Useful for determining when to stop the prediction update loop.

    - **date_str**: Date in YYYY-MM-DD format
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    last_game = get_last_game_time(date_str)

    if last_game:
        return {
            "date": date_str,
            "last_game_utc": last_game.isoformat(),
            "cutoff_time": (last_game - timedelta(minutes=30)).isoformat(),
        }
    else:
        return {"date": date_str, "last_game_utc": None, "message": "No games scheduled"}


@router.get("/accuracy/trend", response_model=TrendResponse)
async def get_accuracy_trend(
    window: int = Query(30, description="Rolling window size (number of games)", ge=5, le=100),
    prediction_type: str = Query("moneyline", description="Type: moneyline, puck_line, or ou"),
    team: Optional[str] = Query(None, description="Filter by team (home or away)"),
):
    """
    Get rolling accuracy data for graphing.

    - **window**: Number of games in the rolling window (default 30)
    - **prediction_type**: moneyline (default), puck_line, or ou
    - **team**: Optional team abbreviation to filter (games where team was home or away)
    """
    try:
        supabase = get_supabase()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase init error: {str(e)}")

    # Choose which correctness column to use
    if prediction_type == "puck_line":
        correct_col = "puck_line_correct"
    elif prediction_type == "ou":
        correct_col = "ou_correct"
    else:
        correct_col = "correct"

    # Fetch all completed predictions for this type (not null), oldest first
    try:
        query = (
            supabase.table("predictions")
            .select("*")
            .not_is(correct_col, "null")
            .order("game_date", desc=False)
        )
        if team:
            t = team.upper()
            query = query.or_(f"away_team.eq.{t},home_team.eq.{t}")
        predictions = query.execute().data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase query error: {str(e)}")

    if not predictions:
        return TrendResponse(window_size=window, total_games=0, data_points=[])

    # Calculate rolling accuracy at each point
    data_points = []
    cumulative_correct = 0

    for i, pred in enumerate(predictions):
        # Update cumulative
        if pred.get(correct_col):
            cumulative_correct += 1
        cumulative_total = i + 1
        cumulative_pct = round((cumulative_correct / cumulative_total) * 100, 1)

        # Calculate rolling window
        window_start = max(0, i - window + 1)
        window_preds = predictions[window_start:i + 1]
        window_correct = sum(1 for p in window_preds if p.get(correct_col))
        window_total = len(window_preds)
        rolling_pct = round((window_correct / window_total) * 100, 1) if window_total > 0 else 0

        data_points.append(TrendDataPoint(
            date=pred['game_date'],
            rolling_accuracy=rolling_pct,
            games_in_window=window_total,
            cumulative_accuracy=cumulative_pct,
            cumulative_games=cumulative_total,
        ))

    return TrendResponse(
        window_size=window,
        total_games=len(predictions),
        data_points=data_points
    )


@router.get("/accuracy/leaderboard")
async def get_accuracy_leaderboard():
    """Per-team accuracy stats for all teams, ranked by moneyline accuracy."""
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase not configured")

    try:
        all_preds = (
            supabase.table("predictions")
            .select("*")
            .not_is("correct", "null")
            .execute()
            .data or []
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase query error: {str(e)}")

    # Aggregate per team — each game counted once for each team involved
    team_stats: Dict[str, Any] = {}
    for pred in all_preds:
        for t in [pred.get('away_team'), pred.get('home_team')]:
            if not t:
                continue
            if t not in team_stats:
                team_stats[t] = {
                    'ml_correct': 0, 'ml_total': 0,
                    'pick_correct': 0, 'pick_total': 0,
                    'pl_correct': 0, 'pl_total': 0,
                    'ou_correct': 0, 'ou_total': 0,
                }
            s = team_stats[t]
            s['ml_total'] += 1
            if pred.get('correct'):
                s['ml_correct'] += 1
            if pred.get('pick') == t:
                s['pick_total'] += 1
                if pred.get('correct'):
                    s['pick_correct'] += 1
            if pred.get('puck_line_correct') is not None:
                s['pl_total'] += 1
                if pred['puck_line_correct']:
                    s['pl_correct'] += 1
            if pred.get('ou_correct') is not None:
                s['ou_total'] += 1
                if pred['ou_correct']:
                    s['ou_correct'] += 1

    result = []
    for team_abbrev, s in team_stats.items():
        result.append({
            'team': team_abbrev,
            'ml_pct': round(s['ml_correct'] / s['ml_total'] * 100, 1) if s['ml_total'] else 0,
            'ml_correct': s['ml_correct'],
            'ml_total': s['ml_total'],
            'pick_pct': round(s['pick_correct'] / s['pick_total'] * 100, 1) if s['pick_total'] else None,
            'pick_correct': s['pick_correct'],
            'pick_total': s['pick_total'],
            'pl_pct': round(s['pl_correct'] / s['pl_total'] * 100, 1) if s['pl_total'] else None,
            'pl_correct': s['pl_correct'],
            'pl_total': s['pl_total'],
            'ou_pct': round(s['ou_correct'] / s['ou_total'] * 100, 1) if s['ou_total'] else None,
            'ou_correct': s['ou_correct'],
            'ou_total': s['ou_total'],
        })

    return sorted(result, key=lambda x: (-x['ml_pct'], -x['ml_total']))


@router.post("/accuracy/backfill")
async def backfill_predictions():
    """
    Backfill puck line and O/U picks and grades for existing predictions.

    For predictions that have results (correct IS NOT NULL) but are missing
    puck_line_pick/ou_pick or puck_line_correct/ou_correct, this endpoint
    re-derives the picks from stored predicted scores and grades them.
    """
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase not configured")

    # Fetch all predictions that have results
    try:
        all_preds = (
            supabase.table("predictions")
            .select("*")
            .not_is("correct", "null")
            .execute()
            .data or []
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase query error: {str(e)}")

    updated_picks = 0
    updated_grades = 0
    errors = []

    for pred in all_preds:
        game_id = pred['game_id']
        away_final = pred.get('away_final')
        home_final = pred.get('home_final')
        update_data = {}

        # Skip if no actual results to grade against
        if away_final is None or home_final is None:
            continue

        # --- Backfill missing picks using stored predicted scores ---
        if pred.get('puck_line_pick') is None or pred.get('ou_pick') is None:
            # Use stored predicted scores as proxy for expected goals
            pred_away = pred.get('away_score', 3.0)
            pred_home = pred.get('home_score', 3.0)

            if pred.get('puck_line_pick') is None:
                # Derive puck line pick from Poisson model
                # Use standard -1.5 puck line
                puck_line = -1.5
                spread_probs = calc_spread_prob(pred_away, pred_home, puck_line)
                home_cover_prob = spread_probs['home_cover']
                away_cover_prob = spread_probs['away_cover']
                puck_line_pick = 'home' if home_cover_prob >= away_cover_prob else 'away'
                update_data['puck_line_pick'] = puck_line_pick
                update_data['puck_line_line'] = puck_line

            if pred.get('ou_pick') is None:
                # Derive O/U pick from Poisson model
                predicted_total = pred_away + pred_home
                # Use nearest half-line as the O/U line
                ou_line = round(predicted_total * 2) / 2
                if ou_line == int(ou_line):
                    ou_line = ou_line - 0.5 if predicted_total >= ou_line else ou_line + 0.5
                ou_probs = calc_over_under_prob(pred_away, pred_home, ou_line)
                ou_pick = 'over' if ou_probs['over'] >= ou_probs['under'] else 'under'
                update_data['ou_pick'] = ou_pick
                update_data['ou_line'] = ou_line

            updated_picks += 1

        # --- Grade puck line ---
        pl_pick = update_data.get('puck_line_pick', pred.get('puck_line_pick'))
        pl_line = update_data.get('puck_line_line', pred.get('puck_line_line'))

        if pl_pick and pl_line is not None and pred.get('puck_line_correct') is None:
            margin = home_final - away_final
            home_covers = (margin + pl_line) > 0
            puck_line_correct = home_covers if pl_pick == 'home' else not home_covers
            update_data['puck_line_correct'] = puck_line_correct
            updated_grades += 1

        # --- Grade O/U ---
        ou_pick_val = update_data.get('ou_pick', pred.get('ou_pick'))
        ou_line_val = update_data.get('ou_line', pred.get('ou_line'))

        if ou_pick_val and ou_line_val is not None and pred.get('ou_correct') is None:
            total = home_final + away_final
            if total != ou_line_val:
                ou_correct = (total > ou_line_val) if ou_pick_val == 'over' else (total < ou_line_val)
                update_data['ou_correct'] = ou_correct
                updated_grades += 1

        # --- Update if anything changed ---
        if update_data:
            try:
                supabase.table("predictions").update(update_data).eq("game_id", game_id).execute()
            except Exception as e:
                errors.append(f"{game_id}: {str(e)}")

    return {
        "message": f"Backfill complete: {updated_picks} picks derived, {updated_grades} grades calculated",
        "updated_picks": updated_picks,
        "updated_grades": updated_grades,
        "total_reviewed": len(all_preds),
        "errors": errors[:10] if errors else [],
    }
