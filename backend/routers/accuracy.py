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
    # Multi-window stats for puck line
    pl_all_time: Optional[WindowStats] = None
    pl_current_season: Optional[WindowStats] = None
    pl_rolling_30: Optional[WindowStats] = None
    # Multi-window stats for O/U
    ou_all_time: Optional[WindowStats] = None
    ou_current_season: Optional[WindowStats] = None
    ou_rolling_30: Optional[WindowStats] = None


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

# Parlay optimizer parameters
_MAX_LEGS = 8


def calc_optimal_parlay(predictions: List[Dict], max_legs: int = _MAX_LEGS) -> Dict:
    """
    Greedy optimizer: for each game with betting_lines, picks the single
    highest-probability bet (ML/PL/OU). Sorts all games by that probability
    descending and returns up to max_legs legs. No probability threshold —
    always produces a parlay as long as games are scheduled.
    """
    candidates = []
    for pred in predictions:
        bl = pred.get("betting_lines") or {}
        if not bl:
            continue
        away = pred.get("away", {})
        home = pred.get("home", {})
        away_team = away.get("team", "") if isinstance(away, dict) else str(away)
        home_team = home.get("team", "") if isinstance(home, dict) else str(home)
        pl_line = bl.get("puck_line", -1.5)
        ou_line = bl.get("over_under")
        date_str = (pred.get("game_time") or "")[:10]

        away_pl = -pl_line  # from away perspective
        options = [
            {"type": "ML", "label": f"{home_team} ML",              "pick": home_team, "prob": bl.get("ml_home_prob", 0)},
            {"type": "ML", "label": f"{away_team} ML",              "pick": away_team, "prob": bl.get("ml_away_prob", 0)},
            {"type": "PL", "label": f"{home_team} {pl_line:+.1f}",  "pick": home_team, "prob": bl.get("puck_line_home_cover_prob", 0), "line": pl_line},
            {"type": "PL", "label": f"{away_team} {away_pl:+.1f}", "pick": away_team, "prob": bl.get("puck_line_away_cover_prob", 0), "line": away_pl},
        ]
        if ou_line:
            options += [
                {"type": "OU", "label": f"Over {ou_line}",  "pick": "OVER",  "prob": bl.get("over_prob", 0),  "line": ou_line},
                {"type": "OU", "label": f"Under {ou_line}", "pick": "UNDER", "prob": bl.get("under_prob", 0), "line": ou_line},
            ]

        # Always pick the best option per game, regardless of probability level
        valid = [o for o in options if o.get("prob", 0) > 0]
        if not valid:
            continue
        best = max(valid, key=lambda x: x["prob"])
        candidates.append({
            **best,
            "game_id":   f"{date_str}_{away_team}_{home_team}",
            "away_team": away_team,
            "home_team": home_team,
            "game_time": pred.get("game_time"),
            "correct":   None,
        })

    candidates.sort(key=lambda x: x["prob"], reverse=True)

    legs: List[Dict] = []
    combined = 1.0
    for c in candidates:
        legs.append(c)
        combined *= c["prob"] / 100
        if len(legs) >= max_legs:
            break

    return {
        "legs": legs,
        "num_legs": len(legs),
        "combined_prob": round(combined * 100, 1) if legs else 0.0,
    }


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

    # Step 3: Update model predictions
    model_updated = 0
    try:
        mp_pending = supabase.table("model_predictions").select("game_date").is_("correct", "null").execute()
        model_dates = list(set([p["game_date"] for p in mp_pending.data])) if mp_pending.data else []
        for date_str in model_dates:
            result = await update_model_results(date_str)
            model_updated += result.get("updated", 0)
    except Exception as e:
        print(f"Model results update error: {e}")

    # Step 4: Grade ungraded parlays
    parlays_graded = 0
    try:
        ungraded = supabase.table("daily_parlays").select("*").is_("correct", "null").execute()
        for parlay in ungraded.data or []:
            game_date = parlay["game_date"]
            results = fetch_game_results(game_date)
            results_by_id = {
                f"{game_date}_{r['away_team']}_{r['home_team']}": r
                for r in results
            }
            legs = parlay.get("legs", [])
            graded_legs = []
            all_correct = True
            legs_correct = 0
            can_grade = True
            for leg in legs:
                result = results_by_id.get(leg.get("game_id"))
                if not result:
                    can_grade = False
                    graded_legs.append(leg)
                    continue
                leg_type = leg.get("type")
                if leg_type == "ML":
                    leg_correct = leg["pick"] == result["actual_winner"]
                elif leg_type == "PL":
                    margin = result["home_final"] - result["away_final"]
                    line = leg.get("line", 0)
                    if leg["pick"] == leg["home_team"]:
                        leg_correct = (margin + line) > 0
                    else:
                        leg_correct = (margin + line) < 0
                else:  # OU
                    total = result["home_final"] + result["away_final"]
                    line = leg.get("line", 0)
                    leg_correct = (total > line) if leg["pick"] == "OVER" else (total < line)
                leg = {**leg, "correct": leg_correct}
                if leg_correct:
                    legs_correct += 1
                else:
                    all_correct = False
                graded_legs.append(leg)
            if can_grade and all(l.get("correct") is not None for l in graded_legs):
                try:
                    supabase.table("daily_parlays").update({
                        "legs": graded_legs,
                        "correct": all_correct,
                        "legs_correct": legs_correct,
                        "updated_at": datetime.now(timezone.utc).isoformat(),
                    }).eq("id", parlay["id"]).execute()
                    parlays_graded += 1
                except Exception as e:
                    print(f"Error grading parlay {parlay.get('id')}: {e}")
    except Exception as e:
        print(f"Parlay grading error: {e}")

    return {
        "message": f"Updated {total_updated} results across {len(dates)} dates. Backfill: {backfill_result.get('updated_picks', 0)} picks, {backfill_result.get('updated_grades', 0)} grades. Model predictions: {model_updated} updated. Parlays graded: {parlays_graded}.",
        "updated": total_updated,
        "backfill_picks": backfill_result.get("updated_picks", 0),
        "backfill_grades": backfill_result.get("updated_grades", 0),
        "model_predictions_updated": model_updated,
        "parlays_graded": parlays_graded,
    }


@router.post("/accuracy/update-model-results/{date_str}")
async def update_model_results(date_str: str):
    """
    Update model_predictions with actual game results for a specific date.
    Called by update-all-pending nightly cron.
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    supabase = get_supabase()
    if not supabase:
        return {"message": "Supabase not configured", "updated": 0}

    results = fetch_game_results(date_str)
    if not results:
        return {"message": f"No completed games for {date_str}", "updated": 0}

    results_by_id = {
        f"{date_str}_{r['away_team']}_{r['home_team']}": r
        for r in results
    }

    try:
        pending = (
            supabase.table("model_predictions")
            .select("id,game_id,pick")
            .eq("game_date", date_str)
            .is_("correct", "null")
            .execute()
        )
        records = pending.data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Query error: {str(e)}")

    if not records:
        return {"message": f"No pending model predictions for {date_str}", "updated": 0}

    updated = 0
    for record in records:
        game_id = record.get("game_id")
        result = results_by_id.get(game_id)
        if not result:
            continue
        try:
            supabase.table("model_predictions").update({
                "correct": record["pick"] == result["actual_winner"],
                "actual_winner": result["actual_winner"],
            }).eq("id", record["id"]).execute()
            updated += 1
        except Exception as e:
            print(f"Error updating model prediction {record.get('id')}: {e}")

    return {"message": f"Updated {updated} model predictions for {date_str}", "updated": updated}


@router.post("/accuracy/store-model-predictions/{date_str}")
async def store_model_predictions(date_str: str):
    """
    Store official predictions for all active user models for a given date.
    Called by the store-predictions cron so model accuracy is tracked even
    if the user doesn't open their model in the browser before game time.
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    supabase = get_supabase()
    if not supabase:
        return {"message": "Supabase not configured", "stored": 0}

    try:
        models_result = supabase.table("user_models").select("*").eq("is_active", True).execute()
        models = models_result.data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch models: {str(e)}")

    if not models:
        return {"message": "No active models", "stored": 0}

    now = datetime.now(timezone.utc)

    # Fetch already-stored (model_id, game_id) pairs to avoid duplicates
    try:
        existing = (
            supabase.table("model_predictions")
            .select("model_id,game_id")
            .eq("game_date", date_str)
            .execute()
        )
        existing_set = {(r["model_id"], r["game_id"]) for r in (existing.data or [])}
    except Exception:
        existing_set = set()

    try:
        analyzer = get_analyzer()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analyzer error: {str(e)}")

    total_stored = 0
    debug_info = []
    for model in models:
        model_id = model["id"]
        weights_data = {
            "offense": float(model.get("weight_offensive", 40)),
            "defense": float(model.get("weight_defensive", 15)),
            "goaltending": float(model.get("weight_goaltending", 30)),
            "points_pct": float(model.get("weight_points_pct", 10)),
            "win_rate": float(model.get("weight_win_rate", 5)),
        }
        model_debug = {"model_id": model_id, "weights": weights_data}
        try:
            results = analyzer.analyze_date(date_str, custom_weights=weights_data)
            model_debug["results_count"] = len(results) if results else 0
        except Exception as e:
            model_debug["analyzer_error"] = str(e)
            print(f"Analyzer error for model {model_id}: {e}")
            debug_info.append(model_debug)
            continue

        if not results:
            model_debug["skip_reason"] = "analyze_date returned empty"
            debug_info.append(model_debug)
            continue

        skipped_no_time = skipped_not_official = skipped_existing = 0
        to_insert = []
        for r in results:
            game_time_str = r.get("game_time")
            if not game_time_str:
                skipped_no_time += 1
                continue
            try:
                game_time = datetime.fromisoformat(game_time_str.replace("Z", "+00:00"))
                is_official = now >= (game_time - timedelta(minutes=15))
            except Exception:
                is_official = False

            if not is_official:
                skipped_not_official += 1
                continue

            game_id = f"{date_str}_{r['away']['team']}_{r['home']['team']}"
            if (model_id, game_id) in existing_set:
                skipped_existing += 1
                continue

            diff = r["diff"]
            if diff >= 10:
                confidence = "STRONG"
            elif diff >= 5:
                confidence = "MODERATE"
            else:
                confidence = "CLOSE"

            to_insert.append({
                "model_id": model_id,
                "game_id": game_id,
                "game_date": date_str,
                "away_team": r["away"]["team"],
                "home_team": r["home"]["team"],
                "pick": r["pick"],
                "away_score": r["away"]["final_score"],
                "home_score": r["home"]["final_score"],
                "confidence": confidence,
            })

        model_debug["skipped_no_time"] = skipped_no_time
        model_debug["skipped_not_official"] = skipped_not_official
        model_debug["skipped_existing"] = skipped_existing
        model_debug["to_insert_count"] = len(to_insert)

        if to_insert:
            try:
                supabase.table("model_predictions").insert(to_insert).execute()
                total_stored += len(to_insert)
                for item in to_insert:
                    existing_set.add((item["model_id"], item["game_id"]))
            except Exception as e:
                model_debug["insert_error"] = str(e)
                print(f"Insert error for model {model_id}: {e}")

        debug_info.append(model_debug)

    return {
        "message": f"Stored {total_stored} model predictions for {date_str} across {len(models)} models",
        "stored": total_stored,
        "models_processed": len(models),
        "debug": debug_info,
    }


@router.get("/accuracy/parlay/{date_str}")
async def get_daily_parlay(date_str: str):
    """
    Return the optimal parlay for a given date (on-the-fly, no DB write).
    Uses cached daily_predictions if available, else runs the analyzer.
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    predictions = []

    # Fast path: try daily_predictions cache first
    supabase = get_supabase()
    if supabase:
        try:
            result = supabase.table("daily_predictions").select("predictions").eq("game_date", date_str).execute()
            if result.data and result.data[0].get("predictions"):
                predictions = result.data[0]["predictions"]
        except Exception:
            pass

    # Fall back to analyzer
    if not predictions:
        try:
            analyzer = get_analyzer()
            raw = analyzer.analyze_date(date_str)
            for r in raw:
                predictions.append({
                    "away": r.get("away"),
                    "home": r.get("home"),
                    "game_time": r.get("game_time"),
                    "betting_lines": r.get("betting_lines"),
                })
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Analyzer error: {str(e)}")

    if not predictions:
        return {"date": date_str, "legs": [], "num_legs": 0, "combined_prob": 0.0}

    result = calc_optimal_parlay(predictions)
    return {"date": date_str, **result}


@router.post("/accuracy/store-parlay/{date_str}")
async def store_daily_parlay(date_str: str):
    """
    Compute and persist today's optimal parlay for accuracy tracking.
    Idempotent: skips if already stored for this date.
    Only uses is_official predictions.
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    supabase = get_supabase()
    if not supabase:
        return {"message": "Supabase not configured", "stored": False}

    # Idempotency check
    try:
        existing = supabase.table("daily_parlays").select("id").eq("game_date", date_str).execute()
        if existing.data and len(existing.data) > 0:
            return {"message": f"Parlay already stored for {date_str}", "already_stored": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase query error: {str(e)}")

    predictions = []

    # Try cache first (official predictions only)
    try:
        result = supabase.table("daily_predictions").select("predictions").eq("game_date", date_str).execute()
        if result.data and result.data[0].get("predictions"):
            all_preds = result.data[0]["predictions"]
            # Filter to official only
            now = datetime.now(timezone.utc)
            for p in all_preds:
                gt = p.get("game_time")
                if gt:
                    try:
                        game_time = datetime.fromisoformat(gt.replace("Z", "+00:00"))
                        if now >= (game_time - timedelta(minutes=15)):
                            predictions.append(p)
                    except Exception:
                        pass
    except Exception:
        pass

    # Fall back to analyzer
    if not predictions:
        try:
            analyzer = get_analyzer()
            raw = analyzer.analyze_date(date_str)
            now = datetime.now(timezone.utc)
            for r in raw:
                gt = r.get("game_time")
                if gt:
                    try:
                        game_time = datetime.fromisoformat(gt.replace("Z", "+00:00"))
                        if now >= (game_time - timedelta(minutes=15)):
                            predictions.append({
                                "away": r.get("away"),
                                "home": r.get("home"),
                                "game_time": gt,
                                "betting_lines": r.get("betting_lines"),
                            })
                    except Exception:
                        pass
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Analyzer error: {str(e)}")

    if not predictions:
        return {"message": f"No official predictions for {date_str}", "stored": False, "num_legs": 0}

    parlay = calc_optimal_parlay(predictions)

    if not parlay["legs"]:
        return {"message": f"No qualifying bets for {date_str}", "stored": False, "num_legs": 0, "legs": []}

    try:
        supabase.table("daily_parlays").insert([{
            "game_date": date_str,
            "legs": parlay["legs"],
            "num_legs": parlay["num_legs"],
            "combined_prob": parlay["combined_prob"],
            "predicted_at": datetime.now(timezone.utc).isoformat(),
        }]).execute()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Insert error: {str(e)}")

    return {
        "message": f"Stored parlay for {date_str}",
        "stored": True,
        "num_legs": parlay["num_legs"],
        "combined_prob": parlay["combined_prob"],
    }


@router.get("/accuracy/parlay-stats")
async def get_parlay_stats():
    """
    Historical parlay accuracy stats for the Accuracy page.
    Returns summary stats and the 10 most recent graded parlays.
    """
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase not configured")

    try:
        all_parlays = (
            supabase.table("daily_parlays")
            .select("*")
            .order("game_date", desc=True)
            .execute()
            .data or []
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase query error: {str(e)}")

    graded = [p for p in all_parlays if p.get("correct") is not None]

    hit_count = sum(1 for p in graded if p.get("correct"))
    hit_pct = round(hit_count / len(graded) * 100, 1) if graded else 0.0
    avg_legs = round(sum(p.get("num_legs", 0) for p in graded) / len(graded), 1) if graded else 0.0
    avg_combined_prob = round(sum(p.get("combined_prob", 0) for p in graded) / len(graded), 1) if graded else 0.0
    avg_legs_correct = round(sum(p.get("legs_correct", 0) for p in graded) / len(graded), 1) if graded else 0.0

    recent_10 = all_parlays[:10]

    return {
        "total_parlays": len(all_parlays),
        "graded_parlays": len(graded),
        "hit_count": hit_count,
        "hit_pct": hit_pct,
        "avg_legs": avg_legs,
        "avg_combined_prob": avg_combined_prob,
        "avg_legs_correct": avg_legs_correct,
        "recent": recent_10,
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

    # Puck line multi-window stats (using all_preds which ignores date/confidence filters)
    pl_all = [p for p in all_preds if p.get('puck_line_correct') is not None]
    pl_last_30 = pl_all[:30]
    pl_season = [p for p in pl_all if season_start.isoformat() <= p['game_date'] <= season_end.isoformat()]
    pl_all_time_stats = WindowStats(
        correct=sum(1 for p in pl_all if p.get('puck_line_correct')),
        total=len(pl_all),
        pct=_pct(sum(1 for p in pl_all if p.get('puck_line_correct')), len(pl_all))
    )
    pl_rolling_30_stats = WindowStats(
        correct=sum(1 for p in pl_last_30 if p.get('puck_line_correct')),
        total=len(pl_last_30),
        pct=_pct(sum(1 for p in pl_last_30 if p.get('puck_line_correct')), len(pl_last_30))
    )
    pl_current_season_stats = WindowStats(
        correct=sum(1 for p in pl_season if p.get('puck_line_correct')),
        total=len(pl_season),
        pct=_pct(sum(1 for p in pl_season if p.get('puck_line_correct')), len(pl_season))
    )

    # O/U multi-window stats (using all_preds which ignores date/confidence filters)
    ou_all = [p for p in all_preds if p.get('ou_correct') is not None]
    ou_last_30 = ou_all[:30]
    ou_season = [p for p in ou_all if season_start.isoformat() <= p['game_date'] <= season_end.isoformat()]
    ou_all_time_stats = WindowStats(
        correct=sum(1 for p in ou_all if p.get('ou_correct')),
        total=len(ou_all),
        pct=_pct(sum(1 for p in ou_all if p.get('ou_correct')), len(ou_all))
    )
    ou_rolling_30_stats = WindowStats(
        correct=sum(1 for p in ou_last_30 if p.get('ou_correct')),
        total=len(ou_last_30),
        pct=_pct(sum(1 for p in ou_last_30 if p.get('ou_correct')), len(ou_last_30))
    )
    ou_current_season_stats = WindowStats(
        correct=sum(1 for p in ou_season if p.get('ou_correct')),
        total=len(ou_season),
        pct=_pct(sum(1 for p in ou_season if p.get('ou_correct')), len(ou_season))
    )

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
        # Puck line multi-window
        pl_all_time=pl_all_time_stats,
        pl_current_season=pl_current_season_stats,
        pl_rolling_30=pl_rolling_30_stats,
        # O/U multi-window
        ou_all_time=ou_all_time_stats,
        ou_current_season=ou_current_season_stats,
        ou_rolling_30=ou_rolling_30_stats,
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
    Backfill puck line and O/U grades for existing predictions.

    Only grades predictions that already have picks stored (puck_line_pick/ou_pick).
    Predictions stored before betting_lines existed have NULL picks and cannot
    be meaningfully backfilled (stored scores are quality scores, not expected goals).

    Also resets any bogus backfill data where ou_line > 10 (indicates quality scores
    were mistakenly used as expected goals).
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

    updated_grades = 0
    reset_count = 0
    errors = []

    for pred in all_preds:
        game_id = pred['game_id']
        away_final = pred.get('away_final')
        home_final = pred.get('home_final')
        update_data = {}

        # Skip if no actual results to grade against
        if away_final is None or home_final is None:
            continue

        # --- Reset bogus backfill data ---
        # If ou_line > 10, it was derived from quality scores (30-70 range) not expected goals
        ou_line_val = pred.get('ou_line')
        if ou_line_val is not None and ou_line_val > 10:
            update_data['puck_line_pick'] = None
            update_data['puck_line_line'] = None
            update_data['puck_line_correct'] = None
            update_data['ou_pick'] = None
            update_data['ou_line'] = None
            update_data['ou_correct'] = None
            reset_count += 1
            try:
                supabase.table("predictions").update(update_data).eq("game_id", game_id).execute()
            except Exception as e:
                errors.append(f"Reset {game_id}: {str(e)}")
            continue

        # --- Grade puck line (only if pick exists but grade is missing) ---
        pl_pick = pred.get('puck_line_pick')
        pl_line = pred.get('puck_line_line')

        if pl_pick and pl_line is not None and pred.get('puck_line_correct') is None:
            margin = home_final - away_final
            home_covers = (margin + pl_line) > 0
            puck_line_correct = home_covers if pl_pick == 'home' else not home_covers
            update_data['puck_line_correct'] = puck_line_correct
            updated_grades += 1

        # --- Grade O/U (only if pick exists but grade is missing) ---
        ou_pick_val = pred.get('ou_pick')

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
        "message": f"Backfill complete: {reset_count} bogus records reset, {updated_grades} grades calculated",
        "reset_count": reset_count,
        "updated_grades": updated_grades,
        "total_reviewed": len(all_preds),
        "errors": errors[:10] if errors else [],
    }
