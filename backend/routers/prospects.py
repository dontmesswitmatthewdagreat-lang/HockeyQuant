"""HockeyQuant Prospects Router — league-wide draft board + per-team pools."""

from typing import Optional
from fastapi import APIRouter, HTTPException

from services.supabase_client import get_supabase
from services.prospects import sync_all
from services.draft_simulator import build_mock_draft

router = APIRouter()


def _sb():
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    return sb


@router.post("/prospects/sync")
def sync():
    """Cron/admin: refresh the prospect dataset from the NHL API."""
    return {"synced": sync_all(_sb())}


@router.get("/prospects")
def list_prospects(team: Optional[str] = None, limit: int = 200):
    """Team pool (by abbrev) or the league-wide notable draft board (default)."""
    sb = _sb()
    q = sb.table("prospects").select("id,nhl_id,name,team,position,draft_year,draft_overall,league,ranking,notable,info")
    if team:
        rows = q.eq("team", team).order("name").limit(min(limit, 500)).execute().data
    else:
        # League board: group by Central Scouting category (NA skaters first, then
        # Intl skaters, NA goalies, Intl goalies), each ordered by rank.
        rows = q.eq("notable", "true").limit(min(limit, 500)).execute().data
        rows.sort(key=lambda r: ((r.get("info") or {}).get("category_id", 9), r.get("ranking") or 999))
    return {"prospects": rows}


@router.post("/prospects/mock-draft/generate")
def generate_mock_draft():
    """Cron/admin: build + store this week's first-round mock draft. Idempotent per ISO week."""
    sb = _sb()
    mock = build_mock_draft(sb)
    if not mock:
        raise HTTPException(status_code=502, detail="Could not build mock draft")
    sb.table("mock_drafts").upsert([{
        "draft_year": mock["draft_year"],
        "edition": mock["edition"],
        "generated_at": mock["generated_at"],
        "order_basis": mock["order_basis"],
        "picks": mock["picks"],
    }], on_conflict="draft_year,edition").execute()
    return {"edition": mock["edition"], "picks": len(mock["picks"])}


@router.get("/prospects/mock-draft")
def latest_mock_draft():
    """App: the most recent weekly mock draft edition."""
    sb = _sb()
    rows = sb.table("mock_drafts").select("*").order("generated_at", desc=True).limit(1).execute().data
    return {"mock_draft": rows[0] if rows else None}
