"""
HockeyQuant Pick'em Leagues Router

Private friend leagues for the daily Pick'em game. The solo pick/XP/grading
engine already lives in Supabase (migration 001); this only adds invite-code
groups + season-scoped standings. Mirrors routers/fantasy.py (service key).
"""

import base64
import json
import secrets
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field

from services.supabase_client import get_supabase

router = APIRouter()

MAX_MEMBERS = 20


def get_user_id_from_token(authorization: Optional[str]) -> str:
    """Extract the Supabase user_id (sub) from a bearer JWT."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")
    token = authorization.replace("Bearer ", "")
    try:
        parts = token.split(".")
        if len(parts) != 3:
            raise HTTPException(status_code=401, detail="Invalid token format")
        payload = parts[1] + "=" * ((4 - len(parts[1]) % 4) % 4)
        uid = json.loads(base64.urlsafe_b64decode(payload)).get("sub")
        if not uid:
            raise HTTPException(status_code=401, detail="Invalid token: no user_id")
        return uid
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Token decode error: {e}")


def _sb():
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    return sb


def _season_window():
    """(season_year, start 'YYYY-10-01', end 'YYYY-06-30') — matches iOS SeasonModels."""
    now = datetime.now(timezone.utc)
    sy = now.year if now.month >= 10 else now.year - 1
    return sy, f"{sy}-10-01", f"{sy + 1}-06-30"


class CreateLeagueRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=60)


class JoinLeagueRequest(BaseModel):
    invite_code: str = Field(..., min_length=4, max_length=12)


def _summary(sb, league: dict, uid: str) -> dict:
    members = sb.table("pickem_members").select("user_id").eq("league_id", league["id"]).execute().data
    return {
        "id": league["id"],
        "name": league["name"],
        "invite_code": league["invite_code"],
        "season_year": league["season_year"],
        "max_members": league["max_members"],
        "member_count": len(members),
        "is_commissioner": league["commissioner_id"] == uid,
    }


def _standings(sb, league_id: str) -> List[dict]:
    members = sb.table("pickem_members").select("user_id").eq("league_id", league_id).execute().data
    uids = [m["user_id"] for m in members]
    if not uids:
        return []

    profiles = sb.table("profiles").select("id,username").in_("id", uids).execute().data
    uname = {p["id"]: p.get("username") for p in profiles}

    _, start, end = _season_window()
    picks = (sb.table("user_picks")
             .select("user_id,xp_awarded,correct")
             .in_("user_id", uids)
             .gte("game_date", start).lte("game_date", end)
             .not_is("correct", "null")
             .execute().data)

    agg = {u: {"season_xp": 0, "picks": 0, "correct": 0} for u in uids}
    for p in picks:
        a = agg.get(p["user_id"])
        if a is None:
            continue
        a["season_xp"] += int(p.get("xp_awarded") or 0)
        a["picks"] += 1
        if p.get("correct") is True:
            a["correct"] += 1

    rows = []
    for u in uids:
        a = agg[u]
        acc = round(a["correct"] / a["picks"] * 100, 1) if a["picks"] else 0.0
        rows.append({
            "user_id": u,
            "username": uname.get(u),
            "season_xp": a["season_xp"],
            "picks": a["picks"],
            "correct": a["correct"],
            "accuracy": acc,
        })
    rows.sort(key=lambda r: (-r["season_xp"], -r["correct"]))
    for i, r in enumerate(rows):
        r["rank"] = i + 1
    return rows


@router.post("/pickem/leagues")
def create_league(req: CreateLeagueRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    sy, _, _ = _season_window()
    invite = secrets.token_hex(3).upper()  # 6 hex chars
    league = sb.table("pickem_leagues").insert([{
        "name": req.name.strip(),
        "commissioner_id": uid,
        "invite_code": invite,
        "season_year": sy,
        "max_members": MAX_MEMBERS,
        "status": "active",
    }]).data[0]
    sb.table("pickem_members").insert([{"league_id": league["id"], "user_id": uid}]).execute()
    return _summary(sb, league, uid)


@router.post("/pickem/leagues/join")
def join_league(req: JoinLeagueRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    found = sb.table("pickem_leagues").select("*").eq("invite_code", req.invite_code.strip().upper()).execute().data
    if not found:
        raise HTTPException(status_code=404, detail="No league with that invite code")
    league = found[0]

    members = sb.table("pickem_members").select("user_id").eq("league_id", league["id"]).execute().data
    if any(m["user_id"] == uid for m in members):
        return _summary(sb, league, uid)  # idempotent
    if len(members) >= league["max_members"]:
        raise HTTPException(status_code=409, detail="League is full")

    sb.table("pickem_members").insert([{"league_id": league["id"], "user_id": uid}]).execute()
    return _summary(sb, league, uid)


@router.get("/pickem/leagues")
def my_leagues(authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    mine = sb.table("pickem_members").select("league_id").eq("user_id", uid).execute().data
    league_ids = [m["league_id"] for m in mine]
    if not league_ids:
        return {"leagues": []}
    leagues = sb.table("pickem_leagues").select("*").in_("id", league_ids).execute().data
    return {"leagues": [_summary(sb, lg, uid) for lg in leagues]}


@router.get("/pickem/leagues/{league_id}")
def league_detail(league_id: str, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    found = sb.table("pickem_leagues").select("*").eq("id", league_id).execute().data
    if not found:
        raise HTTPException(status_code=404, detail="League not found")
    league = found[0]
    members = sb.table("pickem_members").select("user_id").eq("league_id", league_id).execute().data
    if not any(m["user_id"] == uid for m in members):
        raise HTTPException(status_code=403, detail="Not a member of this league")
    return {"league": _summary(sb, league, uid), "standings": _standings(sb, league_id)}
