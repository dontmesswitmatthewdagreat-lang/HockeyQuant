"""Global League weekly duels — ranked head-to-head with a random-pool draft."""

import datetime
from typing import Optional

from fastapi import APIRouter, Header, HTTPException

from routers.fantasy import get_user_id_from_token
from services.supabase_client import get_supabase
import services.duels as duels

router = APIRouter()


def _sb():
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    return sb


@router.post("/duels/queue")
def join_queue(authorization: Optional[str] = Header(None)):
    """Enter the pool for next week's matchmaking."""
    uid = get_user_id_from_token(authorization)
    return duels.join_queue(_sb(), uid)


@router.delete("/duels/queue")
def leave_queue(authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    _sb().table("duel_queue").delete().eq("user_id", uid).execute()
    return {"queued": False}


@router.get("/duels/current")
def current_duel(authorization: Optional[str] = Header(None)):
    """Your live duel for this week, with the board if you're on the clock."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    week_start, _ = duels.week_bounds()
    rows = (sb.table("duels").select("*")
            .or_(f"user_a.eq.{uid},user_b.eq.{uid}")
            .gte("week_start", str(week_start - datetime.timedelta(days=7)))
            .order("week_start", desc=True).limit(5).execute().data)
    active = next((d for d in rows if d["state"] in ("drafting", "live")), None)
    if not active:
        queued = sb.table("duel_queue").select("week_start").eq("user_id", uid).execute().data
        return {"duel": None, "queued": bool(queued),
                "queued_for": queued[0]["week_start"] if queued else None}

    picks = (sb.table("duel_picks").select("*")
             .eq("duel_id", active["id"]).order("pick_no").limit(64).execute().data)
    board = []
    if active["state"] == "drafting" and active["turn_user"] == uid:
        board = duels.offer_pool(sb, active["id"])["offered"]
    return {"duel": active, "picks": picks, "board": board,
            "on_the_clock": active["turn_user"] == uid}


@router.post("/duels/{duel_id}/pick")
def pick(duel_id: int, nhl_id: int, authorization: Optional[str] = Header(None)):
    """Take one of the players currently on your board."""
    uid = get_user_id_from_token(authorization)
    try:
        return duels.make_pick(_sb(), duel_id, uid, nhl_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/duels/rankings")
def rankings(limit: int = 50):
    """Global ranked leaderboard."""
    sb = _sb()
    rows = (sb.table("duel_rankings").select("*")
            .order("rating", desc=True).limit(min(limit, 200)).execute().data)
    from routers.franchise import _usernames
    names = _usernames(sb, [r["user_id"] for r in rows])
    for i, r in enumerate(rows):
        r["rank"] = i + 1
        r["username"] = names.get(r["user_id"], "GM")
    return {"rankings": rows}


@router.post("/duels/match")
def run_matchmaking():
    """Cron: pair everyone queued for next week."""
    return duels.match_queue(_sb())


@router.post("/duels/autopick")
def run_autopick(max_age_hours: int = 12):
    """Cron: move stalled drafts along rather than stranding the opponent.

    A draft that never finishes would cost the *other* player their week, so
    the clock picks the best remaining option instead of forfeiting.
    """
    sb = _sb()
    cutoff = (datetime.datetime.now(datetime.timezone.utc)
              - datetime.timedelta(hours=max_age_hours)).isoformat()
    stalled = (sb.table("duels").select("id,created_at")
               .eq("state", "drafting").lt("created_at", cutoff)
               .limit(200).execute().data)
    moved = 0
    for d in stalled:
        try:
            duels.autopick(sb, d["id"])
            moved += 1
        except Exception:
            continue
    return {"advanced": moved, "checked": len(stalled)}
