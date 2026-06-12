"""
HockeyQuant User Models Router
Endpoints for creating and managing custom prediction models
"""

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field
from typing import List, Optional, Dict
from datetime import datetime, timedelta, timezone
import json

from services import NHLAnalyzer, get_data_loader
from services.supabase_client import get_supabase

router = APIRouter()


# Pydantic models for API
class ModelWeights(BaseModel):
    """Weight distribution for prediction model (must sum to 100)"""
    offense: float = Field(40, ge=0, le=100, description="Offensive quality weight")
    defense: float = Field(15, ge=0, le=100, description="Defensive quality weight")
    goaltending: float = Field(30, ge=0, le=100, description="Goaltending weight")
    points_pct: float = Field(10, ge=0, le=100, description="Points percentage weight")
    win_rate: float = Field(5, ge=0, le=100, description="Win rate weight")


class ModelMultipliers(BaseModel):
    """Per-factor emphasis for a model. 1.0 = official, 0 = ignore, 2.0 = double."""
    fatigue: float = Field(1.0, ge=0, le=3)
    streak: float = Field(1.0, ge=0, le=3)
    special_teams: float = Field(1.0, ge=0, le=3)
    injuries: float = Field(1.0, ge=0, le=3)
    h2h: float = Field(1.0, ge=0, le=3)


class CreateModelRequest(BaseModel):
    """Request to create a new model"""
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None
    weights: ModelWeights
    multipliers: Optional[ModelMultipliers] = None


class UpdateModelRequest(BaseModel):
    """Request to update an existing model"""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None
    weights: Optional[ModelWeights] = None
    multipliers: Optional[ModelMultipliers] = None


class ModelAccuracyStats(BaseModel):
    """Accuracy statistics for a model"""
    total_predictions: int = 0
    correct_predictions: int = 0
    accuracy_pct: float = 0.0
    strong_total: int = 0
    strong_correct: int = 0
    moderate_total: int = 0
    moderate_correct: int = 0
    close_total: int = 0
    close_correct: int = 0


class UserModel(BaseModel):
    """A user's custom prediction model"""
    id: str
    user_id: str
    name: str
    description: Optional[str] = None
    weights: ModelWeights
    multipliers: ModelMultipliers = ModelMultipliers()
    is_active: bool = True
    created_at: str
    updated_at: str
    accuracy: Optional[ModelAccuracyStats] = None


class ModelsListResponse(BaseModel):
    """Response for listing models"""
    models: List[UserModel]
    total: int


# Helper to extract user_id from Authorization header
def get_user_id_from_token(authorization: str) -> str:
    """
    Extract user_id from Supabase JWT token.
    In production, this should properly verify the JWT.
    For now, we decode the payload to get the sub (user_id).
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")

    token = authorization.replace("Bearer ", "")

    try:
        # Decode JWT payload (base64 middle section)
        import base64
        parts = token.split(".")
        if len(parts) != 3:
            raise HTTPException(status_code=401, detail="Invalid token format")

        # Add padding if needed
        payload = parts[1]
        padding = 4 - len(payload) % 4
        if padding != 4:
            payload += "=" * padding

        decoded = base64.urlsafe_b64decode(payload)
        payload_data = json.loads(decoded)

        user_id = payload_data.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token: no user_id")

        return user_id
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Token decode error: {str(e)}")


def validate_weights(weights: ModelWeights) -> None:
    """Ensure weights sum to 100"""
    total = weights.offense + weights.defense + weights.goaltending + weights.points_pct + weights.win_rate
    if abs(total - 100) > 0.01:
        raise HTTPException(
            status_code=400,
            detail=f"Weights must sum to 100. Current sum: {total}"
        )


def _row_to_weights(row: dict) -> ModelWeights:
    """Build ModelWeights from the individual weight columns stored in the DB."""
    return ModelWeights(
        offense=float(row.get("weight_offensive", 40)),
        defense=float(row.get("weight_defensive", 15)),
        goaltending=float(row.get("weight_goaltending", 30)),
        points_pct=float(row.get("weight_points_pct", 10)),
        win_rate=float(row.get("weight_win_rate", 5)),
    )


def _weights_to_columns(weights: ModelWeights) -> dict:
    """Convert ModelWeights to the individual column names used in the DB."""
    return {
        "weight_offensive": weights.offense,
        "weight_defensive": weights.defense,
        "weight_goaltending": weights.goaltending,
        "weight_points_pct": weights.points_pct,
        "weight_win_rate": weights.win_rate,
    }


def _row_to_multipliers(row: dict) -> ModelMultipliers:
    """Build ModelMultipliers from DB columns (default 1.0 = official)."""
    return ModelMultipliers(
        fatigue=float(row.get("mult_fatigue", 1.0) or 1.0),
        streak=float(row.get("mult_streak", 1.0) or 1.0),
        special_teams=float(row.get("mult_special_teams", 1.0) or 1.0),
        injuries=float(row.get("mult_injuries", 1.0) or 1.0),
        h2h=float(row.get("mult_h2h", 1.0) or 1.0),
    )


def _multipliers_to_columns(m: ModelMultipliers) -> dict:
    """Convert ModelMultipliers to DB column names."""
    return {
        "mult_fatigue": m.fatigue,
        "mult_streak": m.streak,
        "mult_special_teams": m.special_teams,
        "mult_injuries": m.injuries,
        "mult_h2h": m.h2h,
    }


def calculate_model_accuracy(model_id: str, supabase) -> ModelAccuracyStats:
    """Calculate accuracy statistics for a model"""
    try:
        result = supabase.table("model_predictions").select("*").eq("model_id", model_id).not_is("correct", "null").execute()
        predictions = result.data

        if not predictions:
            return ModelAccuracyStats()

        total = len(predictions)
        correct = sum(1 for p in predictions if p.get("correct"))

        # By confidence level
        strong = [p for p in predictions if p.get("confidence") == "STRONG"]
        moderate = [p for p in predictions if p.get("confidence") == "MODERATE"]
        close = [p for p in predictions if p.get("confidence") == "CLOSE"]

        return ModelAccuracyStats(
            total_predictions=total,
            correct_predictions=correct,
            accuracy_pct=round((correct / total) * 100, 1) if total > 0 else 0.0,
            strong_total=len(strong),
            strong_correct=sum(1 for p in strong if p.get("correct")),
            moderate_total=len(moderate),
            moderate_correct=sum(1 for p in moderate if p.get("correct")),
            close_total=len(close),
            close_correct=sum(1 for p in close if p.get("correct")),
        )
    except Exception:
        return ModelAccuracyStats()


@router.get("/models", response_model=ModelsListResponse)
async def list_models(authorization: str = Header(None)):
    """
    List all models for the authenticated user.
    Requires Bearer token in Authorization header.
    """
    user_id = get_user_id_from_token(authorization)

    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        result = supabase.table("user_models").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()

        models = []
        for row in result.data:
            accuracy = calculate_model_accuracy(row["id"], supabase)

            models.append(UserModel(
                id=row["id"],
                user_id=row["user_id"],
                name=row["name"],
                description=row.get("description"),
                weights=_row_to_weights(row),
                multipliers=_row_to_multipliers(row),
                is_active=row.get("is_active", True),
                created_at=row["created_at"],
                updated_at=row["updated_at"],
                accuracy=accuracy,
            ))

        return ModelsListResponse(models=models, total=len(models))

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.post("/models", response_model=UserModel)
async def create_model(request: CreateModelRequest, authorization: str = Header(None)):
    """
    Create a new custom prediction model.
    Weights must sum to exactly 100.
    """
    user_id = get_user_id_from_token(authorization)
    validate_weights(request.weights)

    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        # Ensure a profile row exists (user_models.user_id FKs to profiles.id)
        try:
            supabase.table("profiles").upsert([{"id": user_id}])
        except Exception:
            pass  # Profile likely already exists; FK error on user_models insert will be clearer

        # Check if model name already exists for this user
        existing = supabase.table("user_models").select("id").eq("user_id", user_id).eq("name", request.name).execute()
        if existing.data:
            raise HTTPException(status_code=400, detail="A model with this name already exists")

        result = supabase.table("user_models").insert([{
            "user_id": user_id,
            "name": request.name,
            "description": request.description,
            "is_active": True,
            **_weights_to_columns(request.weights),
            **_multipliers_to_columns(request.multipliers or ModelMultipliers()),
        }]).execute()

        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to create model")

        row = result.data[0]

        return UserModel(
            id=row["id"],
            user_id=row["user_id"],
            name=row["name"],
            description=row.get("description"),
            weights=_row_to_weights(row),
            is_active=row.get("is_active", True),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.get("/models/leaderboard")
async def get_models_leaderboard():
    """
    Public leaderboard of all user models ranked by accuracy.
    No authentication required.
    """
    supabase = get_supabase()
    if not supabase:
        return []

    try:
        # 1. Fetch ALL models (no user_id filter)
        models_result = supabase.table("user_models").select("*").execute()
        models = models_result.data
        if not models:
            return []

        # 2. Batch-fetch usernames from profiles
        user_ids = list({m["user_id"] for m in models})
        profiles_result = supabase.table("profiles").select("id,username").in_("id", user_ids).execute()
        profiles_by_id = {p["id"]: p for p in profiles_result.data}

        # 3. Fetch all graded model predictions, paginated (PostgREST caps at 1000/req)
        preds_rows = []
        start = 0
        while True:
            chunk = supabase.table("model_predictions") \
                .select("model_id,confidence,correct") \
                .not_is("correct", "null") \
                .limit(1000).offset(start) \
                .execute().data
            preds_rows.extend(chunk)
            if len(chunk) < 1000:
                break
            start += 1000

        # 4. Aggregate accuracy per model in Python (avoids N+1 queries)
        from collections import defaultdict
        stats = defaultdict(lambda: {
            "total": 0, "correct": 0,
            "strong_total": 0, "strong_correct": 0,
            "moderate_total": 0, "moderate_correct": 0,
            "close_total": 0, "close_correct": 0,
        })
        for p in preds_rows:
            mid = p["model_id"]
            stats[mid]["total"] += 1
            if p.get("correct"):
                stats[mid]["correct"] += 1
            conf = (p.get("confidence") or "").lower()
            if conf in ("strong", "moderate", "close"):
                stats[mid][f"{conf}_total"] += 1
                if p.get("correct"):
                    stats[mid][f"{conf}_correct"] += 1

        # 5. Build entries
        def pct(c, t):
            return round(c / t * 100, 1) if t > 0 else None

        entries = []
        for m in models:
            mid = m["id"]
            s = stats[mid]
            total = s["total"]
            correct = s["correct"]
            profile = profiles_by_id.get(m["user_id"], {})
            entries.append({
                "model_id": mid,
                "model_name": m["name"],
                "username": profile.get("username"),
                "user_id": m["user_id"],
                "description": m.get("description"),
                "model_type": m.get("model_type", "weighted"),
                "ml_kind": (m.get("ml_meta") or {}).get("kind") if m.get("model_type") == "ml" else None,
                "weights": _row_to_weights(m).model_dump(),
                "created_at": m["created_at"],
                "total_predictions": total,
                "correct_predictions": correct,
                "accuracy_pct": pct(correct, total),
                "strong_total": s["strong_total"],
                "strong_correct": s["strong_correct"],
                "strong_pct": pct(s["strong_correct"], s["strong_total"]),
                "moderate_total": s["moderate_total"],
                "moderate_correct": s["moderate_correct"],
                "moderate_pct": pct(s["moderate_correct"], s["moderate_total"]),
                "close_total": s["close_total"],
                "close_correct": s["close_correct"],
                "close_pct": pct(s["close_correct"], s["close_total"]),
            })

        # 6. Sort: models with predictions first (by accuracy desc), then no-prediction models
        entries.sort(key=lambda x: (
            x["accuracy_pct"] is None,
            -(x["accuracy_pct"] or 0),
            -(x["total_predictions"]),
        ))
        return entries

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Leaderboard error: {str(e)}")


@router.get("/models/{model_id}", response_model=UserModel)
async def get_model(model_id: str, authorization: str = Header(None)):
    """
    Get a specific model by ID.
    User must own the model.
    """
    user_id = get_user_id_from_token(authorization)

    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        result = supabase.table("user_models").select("*").eq("id", model_id).eq("user_id", user_id).execute()

        if not result.data:
            raise HTTPException(status_code=404, detail="Model not found")

        row = result.data[0]
        accuracy = calculate_model_accuracy(model_id, supabase)

        return UserModel(
            id=row["id"],
            user_id=row["user_id"],
            name=row["name"],
            description=row.get("description"),
            weights=_row_to_weights(row),
            is_active=row.get("is_active", True),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            accuracy=accuracy,
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.put("/models/{model_id}", response_model=UserModel)
async def update_model(model_id: str, request: UpdateModelRequest, authorization: str = Header(None)):
    """
    Update an existing model.
    User must own the model.
    """
    user_id = get_user_id_from_token(authorization)

    if request.weights:
        validate_weights(request.weights)

    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        # Verify ownership
        existing = supabase.table("user_models").select("*").eq("id", model_id).eq("user_id", user_id).execute()
        if not existing.data:
            raise HTTPException(status_code=404, detail="Model not found")

        # Build update data
        update_data = {}
        if request.name is not None:
            update_data["name"] = request.name
        if request.description is not None:
            update_data["description"] = request.description
        if request.weights is not None:
            update_data.update(_weights_to_columns(request.weights))
        if request.multipliers is not None:
            update_data.update(_multipliers_to_columns(request.multipliers))

        result = supabase.table("user_models").update(update_data).eq("id", model_id).execute()

        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to update model")

        row = result.data[0]
        accuracy = calculate_model_accuracy(model_id, supabase)

        return UserModel(
            id=row["id"],
            user_id=row["user_id"],
            name=row["name"],
            description=row.get("description"),
            weights=_row_to_weights(row),
            is_active=row.get("is_active", True),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            accuracy=accuracy,
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.delete("/models/{model_id}")
async def delete_model(model_id: str, authorization: str = Header(None)):
    """
    Delete a model and all its predictions.
    User must own the model.
    """
    user_id = get_user_id_from_token(authorization)

    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        # Verify ownership
        existing = supabase.table("user_models").select("id").eq("id", model_id).eq("user_id", user_id).execute()
        if not existing.data:
            raise HTTPException(status_code=404, detail="Model not found")

        # Delete model (cascade will delete predictions)
        supabase.table("user_models").delete().eq("id", model_id).execute()

        return {"message": "Model deleted successfully"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


# Shared analyzer instance
_analyzer = None


def get_analyzer() -> NHLAnalyzer:
    """Get or create analyzer instance"""
    global _analyzer
    if _analyzer is None:
        data_loader = get_data_loader()
        data_loader.load_all_data()
        _analyzer = NHLAnalyzer(data_loader)
    return _analyzer


@router.get("/models/{model_id}/predictions/{date_str}")
async def get_model_predictions(model_id: str, date_str: str, authorization: str = Header(None)):
    """
    Get predictions for a date using a custom model's weights.
    User must own the model.
    """
    user_id = get_user_id_from_token(authorization)

    # Validate date format
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    # Get and verify model ownership
    try:
        result = supabase.table("user_models").select("*").eq("id", model_id).eq("user_id", user_id).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="Model not found")

        model = result.data[0]
        model_weights = _row_to_weights(model)
        weights_data = model_weights.model_dump()
        mult = _row_to_multipliers(model)
        multiplier_weights = {
            "fatigue": mult.fatigue,
            "streak": mult.streak,
            "special_teams": mult.special_teams,
            "injuries": mult.injuries,
            "h2h": mult.h2h,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

    # Get predictions with custom weights + factor emphasis
    try:
        analyzer = get_analyzer()
        results = analyzer.analyze_date(date_str, custom_weights=weights_data, multiplier_weights=multiplier_weights)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analyzer error: {str(e)}")

    if not results:
        return {
            "date": date_str,
            "model_id": model_id,
            "model_name": model["name"],
            "games_count": 0,
            "predictions": []
        }

    # Current time for determining official status
    now = datetime.now(timezone.utc)

    # Transform results
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

        predictions.append({
            "away": r['away'],
            "home": r['home'],
            "pick": r['pick'],
            "diff": round(r['diff'], 2),
            "confidence": confidence,
            "factors": r.get('factors', []),
            "game_time": game_time_str,
            "is_official": is_official,
            "official_at": official_at_str,
            "goalie_status_away": r.get('goalie_status_away', 'expected'),
            "goalie_status_home": r.get('goalie_status_home', 'expected'),
        })

    # Auto-store official predictions to model_predictions (idempotent, fire-and-forget)
    if supabase and predictions:
        try:
            existing_mp = supabase.table("model_predictions") \
                .select("game_id") \
                .eq("model_id", model_id) \
                .eq("game_date", date_str) \
                .execute()
            existing_mp_ids = {r["game_id"] for r in (existing_mp.data or [])}

            to_insert = []
            for pred in predictions:
                game_id = f"{date_str}_{pred['away']['team']}_{pred['home']['team']}"
                if pred.get("is_official") and game_id not in existing_mp_ids:
                    to_insert.append({
                        "model_id": model_id,
                        "game_id": game_id,
                        "game_date": date_str,
                        "away_team": pred["away"]["team"],
                        "home_team": pred["home"]["team"],
                        "pick": pred["pick"],
                        "away_score": pred["away"]["final_score"],
                        "home_score": pred["home"]["final_score"],
                        "diff": round(pred["diff"], 2),
                        "confidence": pred["confidence"],
                    })
            if to_insert:
                supabase.table("model_predictions").insert(to_insert).execute()
        except Exception as store_err:
            print(f"Warning: Failed to auto-store model predictions: {store_err}")

    return {
        "date": date_str,
        "model_id": model_id,
        "model_name": model["name"],
        "weights": weights_data,
        "games_count": len(predictions),
        "predictions": predictions
    }
