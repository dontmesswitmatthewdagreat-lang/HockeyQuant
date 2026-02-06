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


class CreateModelRequest(BaseModel):
    """Request to create a new model"""
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None
    weights: ModelWeights


class UpdateModelRequest(BaseModel):
    """Request to update an existing model"""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None
    weights: Optional[ModelWeights] = None


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
            weights_data = row.get("weights", {})
            if isinstance(weights_data, str):
                weights_data = json.loads(weights_data)

            accuracy = calculate_model_accuracy(row["id"], supabase)

            models.append(UserModel(
                id=row["id"],
                user_id=row["user_id"],
                name=row["name"],
                description=row.get("description"),
                weights=ModelWeights(**weights_data),
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
        # Check if model name already exists for this user
        existing = supabase.table("user_models").select("id").eq("user_id", user_id).eq("name", request.name).execute()
        if existing.data:
            raise HTTPException(status_code=400, detail="A model with this name already exists")

        now = datetime.utcnow().isoformat()

        result = supabase.table("user_models").insert([{
            "user_id": user_id,
            "name": request.name,
            "description": request.description,
            "weights": request.weights.model_dump(),
            "is_active": True,
            "created_at": now,
            "updated_at": now,
        }]).execute()

        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to create model")

        row = result.data[0]
        weights_data = row.get("weights", {})
        if isinstance(weights_data, str):
            weights_data = json.loads(weights_data)

        return UserModel(
            id=row["id"],
            user_id=row["user_id"],
            name=row["name"],
            description=row.get("description"),
            weights=ModelWeights(**weights_data),
            is_active=row.get("is_active", True),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


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
        weights_data = row.get("weights", {})
        if isinstance(weights_data, str):
            weights_data = json.loads(weights_data)

        accuracy = calculate_model_accuracy(model_id, supabase)

        return UserModel(
            id=row["id"],
            user_id=row["user_id"],
            name=row["name"],
            description=row.get("description"),
            weights=ModelWeights(**weights_data),
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
        update_data = {"updated_at": datetime.utcnow().isoformat()}
        if request.name is not None:
            update_data["name"] = request.name
        if request.description is not None:
            update_data["description"] = request.description
        if request.weights is not None:
            update_data["weights"] = request.weights.model_dump()

        result = supabase.table("user_models").update(update_data).eq("id", model_id).execute()

        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to update model")

        row = result.data[0]
        weights_data = row.get("weights", {})
        if isinstance(weights_data, str):
            weights_data = json.loads(weights_data)

        accuracy = calculate_model_accuracy(model_id, supabase)

        return UserModel(
            id=row["id"],
            user_id=row["user_id"],
            name=row["name"],
            description=row.get("description"),
            weights=ModelWeights(**weights_data),
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
        weights_data = model.get("weights", {})
        if isinstance(weights_data, str):
            weights_data = json.loads(weights_data)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

    # Get predictions with custom weights
    try:
        analyzer = get_analyzer()
        results = analyzer.analyze_date(date_str, custom_weights=weights_data)
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

    return {
        "date": date_str,
        "model_id": model_id,
        "model_name": model["name"],
        "weights": weights_data,
        "games_count": len(predictions),
        "predictions": predictions
    }
