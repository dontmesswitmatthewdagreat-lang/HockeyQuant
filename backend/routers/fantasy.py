"""
HockeyQuant Fantasy League Router
Player pool sync + league management. All fantasy logic is server-side; the
backend uses the Supabase service key (bypasses RLS).
"""

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime, timezone, timedelta
import base64
import json
import os
import random
import secrets
import statistics
import time
from collections import defaultdict

import requests

from services.supabase_client import get_supabase
from services.constants import NHL_DIVISIONS

router = APIRouter()

NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}
ALL_TEAMS = sorted({t for teams in NHL_DIVISIONS.values() for t in teams})

# Positional roster: 2 LW, 2 RW, 2 C, 2 LHD, 2 RHD, 1 starting G, 1 backup G.
ROSTER_SLOTS = [
    ("LW1", "LW"), ("LW2", "LW"),
    ("RW1", "RW"), ("RW2", "RW"),
    ("C1", "C"), ("C2", "C"),
    ("LHD1", "LHD"), ("LHD2", "LHD"),
    ("RHD1", "RHD"), ("RHD2", "RHD"),
    ("G_START", "G"), ("G_BACKUP", "G"),
]
SLOTS_PER_TEAM = len(ROSTER_SLOTS)

# Off-season prospect farm: drafted prospects (dynasty assets) live here, separate from
# the 12 active NHL slots that score weekly Cup matchups. One draft round per farm slot.
FARM_SLOTS = [("PR1", "FARM"), ("PR2", "FARM"), ("PR3", "FARM"),
              ("PR4", "FARM"), ("PR5", "FARM"), ("PR6", "FARM")]
OFFSEASON_ROUNDS = len(FARM_SLOTS)

REG_SEASON_WEEKS = 24          # fantasy regular-season length
GOALIE_BONUS = 1.20            # better weekly GSAX
GOALIE_PENALTY = 0.80          # worse weekly GSAX
TRADE_DEADLINE_WEEK = 16       # private leagues: trades allowed through this week
PLAYOFF_SEEDS = 4              # top-N make the fantasy playoff bracket
# Draft pace → pick-clock seconds. Rapid = live (everyone online), Standard /
# Slow = asynchronous (server cron auto-picks on expiry).
PACE_SECONDS = {"rapid": 120, "standard": 3600, "slow": 21600}
DEFAULT_PICK_SECONDS = PACE_SECONDS["slow"]


def _clock_label(secs: int) -> str:
    if secs < 3600:
        return f"{secs // 60} minutes"
    h = secs // 3600
    return f"{h} hour" + ("s" if h != 1 else "")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def get_user_id_from_token(authorization: Optional[str]) -> str:
    """Extract the Supabase user_id (sub) from a bearer JWT."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")
    token = authorization.replace("Bearer ", "")
    try:
        parts = token.split(".")
        if len(parts) != 3:
            raise HTTPException(status_code=401, detail="Invalid token format")
        payload = parts[1]
        payload += "=" * ((4 - len(payload) % 4) % 4)
        data = json.loads(base64.urlsafe_b64decode(payload))
        uid = data.get("sub")
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


def current_season_year() -> int:
    """The NHL season year (start year). Offseason summer maps to the upcoming season."""
    now = datetime.now(timezone.utc)
    if now.month >= 9:
        return now.year
    if now.month <= 4:
        return now.year - 1
    return now.year  # May–Aug → upcoming season starts this fall


# ---------------------------------------------------------------------------
# Push notifications (APNs) — gated on config; no-ops cleanly until enrolled.
# ---------------------------------------------------------------------------

from services.push import apns_send as _apns_send, push_users as _push_users  # shared APNs helpers


def _notify_on_clock(sb, league: dict, member_id: Optional[str]) -> None:
    # Rapid (live) drafts are synchronous — no per-pick push needed.
    if not member_id or league.get("draft_pace") == "rapid":
        return
    secs = league.get("pick_clock_seconds") or DEFAULT_PICK_SECONDS
    m = sb.table("fantasy_members").select("user_id").eq("id", member_id).execute().data
    if m:
        _push_users(sb, [m[0]["user_id"]], "You're on the clock! ⏱",
                    f"It's your pick in {league['name']}. You have {_clock_label(secs)} before an auto-pick.")


def _roster_pos(position_code: str, shoots: Optional[str]) -> Optional[str]:
    """Map NHL positionCode (+ handedness for D) to a fantasy slot type."""
    if position_code == "L":
        return "LW"
    if position_code == "R":
        return "RW"
    if position_code == "C":
        return "C"
    if position_code == "D":
        return "LHD" if shoots == "L" else "RHD"
    if position_code == "G":
        return "G"
    return None


# ---------------------------------------------------------------------------
# Player pool sync (cron/admin)
# ---------------------------------------------------------------------------

# Player cost in real NHL cap dollars. League minimum / entry-level at the floor,
# ~$12-13M for elite scorers and starters (scoring drives a skater's price; wins —
# a quality + volume proxy — drive a goalie's). Stored in dollars; the app shows $M.
_NHL_MIN = 775_000   # league minimum / ELC

def _player_cost(prod) -> int:
    """prod = ("skater", goals) | ("goalie", wins) | None (didn't play / ELC → minimum)."""
    if not prod:
        return _NHL_MIN
    kind, val = prod
    return _NHL_MIN + val * (230_000 if kind == "goalie" else 235_000)


# Prospects are entry-level, but to make the cap bind we scale their (ELC-flavored)
# cap hit by consensus draft rank: the #1 prospect is a real cap commitment, decaying
# to the league minimum deep in the board.
_PROSPECT_TOP_COST = 8_000_000
_PROSPECT_COST_STEP = 115_000

def _prospect_roster_pos(position: Optional[str], shoots: Optional[str]) -> Optional[str]:
    """Map an NHL draft positionCode to a roster slot type (D split by handedness)."""
    p = (position or "").upper()
    if p == "C": return "C"
    if p in ("L", "LW"): return "LW"
    if p in ("R", "RW"): return "RW"
    if p == "G": return "G"
    if p == "LD": return "LHD"
    if p == "RD": return "RHD"
    if p == "D": return "RHD" if (shoots or "L").upper() == "R" else "LHD"
    if p == "F": return "C"          # generic forward → center
    return None


def _prospect_cost(rank: int) -> int:
    cost = max(_NHL_MIN, _PROSPECT_TOP_COST - (rank - 1) * _PROSPECT_COST_STEP)
    return int(round(cost / 100_000) * 100_000)


def sync_prospects_to_players(sb) -> int:
    """Mirror the current draft class (consensus board) into fantasy_players as
    draftable, cap-priced prospects. Idempotent (upsert on nhl_id)."""
    from services.draft_simulator import _consensus_pool
    pool = _consensus_pool(sb)
    rows = []
    for i, p in enumerate(pool):
        info = p.get("info") or {}
        rpos = _prospect_roster_pos(p.get("position"), info.get("shoots"))
        if not rpos or not p.get("nhl_id"):
            continue
        rank = i + 1
        rows.append({
            "nhl_id": p["nhl_id"],
            "full_name": p.get("name") or "Prospect",
            "team": (info.get("club") or p.get("league") or "DRAFT")[:24],
            "position": ((p.get("position") or "")[:3]) or "F",
            "shoots": info.get("shoots"),
            "roster_pos": rpos,
            "is_goalie": rpos == "G",
            "headshot": info.get("headshot"),
            "active": False,
            "is_prospect": True,
            "prospect_ranking": rank,
            "draft_class": p.get("draft_year") or current_season_year(),
            "cost": _prospect_cost(rank),
            "updated_at": _now(),
        })
    for i in range(0, len(rows), 200):
        sb.table("fantasy_players").upsert(rows[i:i + 200], on_conflict="nhl_id").execute()
    return len(rows)


def _user_cap_space(sb, uid: str) -> int:
    rows = sb.table("user_stats").select("cap_space").eq("user_id", uid).execute().data
    return (rows[0].get("cap_space") if rows else 0) or 0


def _user_cups(sb, uid: str) -> int:
    rows = sb.table("user_stats").select("stanley_cups").eq("user_id", uid).execute().data
    return (rows[0].get("stanley_cups") if rows else 0) or 0


# The maximum Cap Space = the real NHL salary-cap upper limit for the season, which
# rises each year (NHL/NHLPA announced schedule). Mirrors the season_caps table the
# grading function clamps against (migration 017).
NHL_SALARY_CAP = {2021: 81_500_000, 2022: 82_500_000, 2023: 83_500_000,
                  2024: 88_000_000, 2025: 95_500_000, 2026: 104_000_000, 2027: 113_500_000}

def season_cap_max(season: int) -> int:
    if season in NHL_SALARY_CAP:
        return NHL_SALARY_CAP[season]
    yrs = sorted(NHL_SALARY_CAP)
    if season <= yrs[0]:
        return NHL_SALARY_CAP[yrs[0]]
    cap = NHL_SALARY_CAP[yrs[-1]]                       # estimate beyond the announced years (~8%/yr)
    for _ in range(season - yrs[-1]):
        cap = int(round(cap * 1.08 / 500_000) * 500_000)
    return cap


@router.post("/fantasy/sync-players")
def sync_players():
    """Fetch all 32 NHL team rosters + season production and upsert the player pool with costs."""
    sb = _sb()
    now_iso = datetime.now(timezone.utc).isoformat()
    rows: List[dict] = []
    failed: List[str] = []

    for team in ALL_TEAMS:
        try:
            resp = requests.get(
                f"https://api-web.nhle.com/v1/roster/{team}/current",
                headers=NHL_HEADERS, timeout=15,
            )
            if not resp.ok:
                failed.append(team)
                continue
            data = resp.json()
        except Exception:
            failed.append(team)
            continue

        # Season production by nhl_id, for player cost: goals (skaters) / wins (goalies).
        prod: dict = {}
        try:
            cs = requests.get(f"https://api-web.nhle.com/v1/club-stats/{team}/now",
                              headers=NHL_HEADERS, timeout=15).json()
            for s in cs.get("skaters", []):
                prod[s.get("playerId")] = ("skater", int(s.get("goals") or 0))
            for g in cs.get("goalies", []):
                prod[g.get("playerId")] = ("goalie", int(g.get("wins") or 0))
        except Exception:
            pass

        for group_key in ("forwards", "defensemen", "goalies"):
            for p in data.get(group_key, []):
                pos = p.get("positionCode")
                shoots = p.get("shootsCatches")
                rpos = _roster_pos(pos, shoots)
                if not rpos:
                    continue
                first = (p.get("firstName") or {}).get("default", "")
                last = (p.get("lastName") or {}).get("default", "")
                rows.append({
                    "nhl_id": p.get("id"),
                    "full_name": f"{first} {last}".strip(),
                    "team": team,
                    "position": pos,
                    "shoots": shoots,
                    "roster_pos": rpos,
                    "is_goalie": pos == "G",
                    "sweater": p.get("sweaterNumber"),
                    "headshot": p.get("headshot"),
                    "cost": _player_cost(prod.get(p.get("id"))),
                    "active": True,
                    "updated_at": now_iso,
                })

    if rows:
        # Upsert in batches to keep payloads reasonable.
        for i in range(0, len(rows), 300):
            sb.table("fantasy_players").upsert(rows[i:i + 300], on_conflict="nhl_id").execute()

    return {"synced": len(rows), "teams_ok": len(ALL_TEAMS) - len(failed), "failed": failed}


@router.post("/fantasy/sync-prospects")
def sync_prospects():
    """Cron/admin: mirror the current prospect draft class into fantasy_players,
    cap-priced by consensus rank, so they can be drafted in off-season leagues."""
    return {"synced": sync_prospects_to_players(_sb())}


# ---------------------------------------------------------------------------
# Player pool reads (draft board)
# ---------------------------------------------------------------------------

@router.get("/fantasy/players")
def list_players(slot_type: Optional[str] = None, q: Optional[str] = None, limit: int = 200):
    """List the player pool, optionally filtered by slot type (LW/RW/C/LHD/RHD/G) and name search."""
    sb = _sb()
    query = sb.table("fantasy_players").select(
        "id,nhl_id,full_name,team,position,shoots,roster_pos,is_goalie,sweater,headshot,cost"
    ).eq("active", "true")
    if slot_type:
        query = query.eq("roster_pos", slot_type)
    if q:
        query = query.ilike("full_name", f"*{q}*")
    # Priciest (best) players first — the market reads as a value board.
    rows = query.order("cost", desc=True).limit(min(limit, 1000)).execute().data
    return {"players": rows, "count": len(rows)}


# ---------------------------------------------------------------------------
# Leagues
# ---------------------------------------------------------------------------

class CreateLeagueRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=60)
    team_name: str = Field(..., min_length=1, max_length=40)
    league_type: str = Field("group", pattern="^(group|global)$")
    mode: str = Field("group", pattern="^(group|global|solo)$")
    cpu_count: int = Field(0, ge=0, le=11)        # CPU GMs to seed (solo mode)
    max_members: int = Field(8, ge=2, le=16)
    draft_pace: str = Field("standard", pattern="^(rapid|standard|slow)$")


# Fun CPU franchise names for solo leagues.
_CPU_TEAM_NAMES = [
    "Tundra Wolves", "Granite Grizzlies", "Aurora Borealis", "Steel City Stags",
    "Frostbite FC", "Glacier Kings", "Slapshot Syndicate", "Top Shelf Titans",
    "Blue Line Bandits", "Rink Rats", "Iron Moose",
]


class JoinLeagueRequest(BaseModel):
    invite_code: str = Field(..., min_length=4, max_length=12)
    team_name: str = Field(..., min_length=1, max_length=40)


def _league_summary(sb, league: dict, uid: str) -> dict:
    members = sb.table("fantasy_members").select("id,user_id,team_name,draft_order,cap_space").eq("league_id", league["id"]).execute().data
    mine = next((m for m in members if m["user_id"] == uid), None)
    return {
        "id": league["id"],
        "name": league["name"],
        "league_type": league["league_type"],
        "status": league["status"],
        "season_phase": league.get("season_phase", "regular"),
        "mode": league.get("mode", "group"),
        "max_members": league["max_members"],
        "unique_players": league["unique_players"],
        "invite_code": league["invite_code"],
        "season_year": league["season_year"],
        "draft_pace": league.get("draft_pace", "slow"),
        "pick_clock_seconds": league.get("pick_clock_seconds", DEFAULT_PICK_SECONDS),
        "is_commissioner": league["commissioner_id"] == uid,
        "member_count": len(members),
        "my_team_name": mine["team_name"] if mine else None,
        "my_cap_space": (mine.get("cap_space") if mine else 0) or 0,
    }


@router.post("/fantasy/leagues")
def create_league(req: CreateLeagueRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    invite = secrets.token_hex(3).upper()  # 6 hex chars
    season = current_season_year()
    league = sb.table("fantasy_leagues").insert([{
        "name": req.name,
        "commissioner_id": uid,
        "league_type": req.league_type,
        "mode": req.mode,
        "status": "open",
        "max_members": req.max_members,
        "unique_players": req.league_type == "group",
        "trade_deadline_enabled": req.league_type == "group",
        "invite_code": invite,
        "season_year": season,
        "draft_pace": req.draft_pace,
        "pick_clock_seconds": PACE_SECONDS[req.draft_pace],
    }]).data[0]

    # Group/solo leagues are franchises: each manager gets a Cap Space bank (the full
    # NHL cap to start; it carries over season-to-season). The global league uses the
    # per-user Cap Space earned from picks instead.
    start_cap = 0 if req.league_type == "global" else season_cap_max(season)
    sb.table("fantasy_members").insert([{
        "league_id": league["id"],
        "user_id": uid,
        "team_name": req.team_name,
        "cap_space": start_cap,
    }]).execute()

    # Solo mode: seed CPU-managed franchises so the lottery, draft, and trades have rivals.
    if req.mode == "solo" and req.cpu_count > 0:
        names = random.sample(_CPU_TEAM_NAMES, min(req.cpu_count, len(_CPU_TEAM_NAMES)))
        sb.table("fantasy_members").insert([{
            "league_id": league["id"], "team_name": nm, "is_cpu": True, "cap_space": start_cap,
        } for nm in names]).execute()

    sb.table("fantasy_draft_state").insert([{
        "league_id": league["id"],
        "status": "not_started",
    }]).execute()

    return _league_summary(sb, league, uid)


@router.post("/fantasy/leagues/join")
def join_league(req: JoinLeagueRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    found = sb.table("fantasy_leagues").select("*").eq("invite_code", req.invite_code.upper()).execute().data
    if not found:
        raise HTTPException(status_code=404, detail="No league with that invite code")
    league = found[0]
    if league["status"] != "open":
        raise HTTPException(status_code=400, detail="This league's draft has already started")

    members = sb.table("fantasy_members").select("id,user_id").eq("league_id", league["id"]).execute().data
    if any(m["user_id"] == uid for m in members):
        return _league_summary(sb, league, uid)  # already in
    if len(members) >= league["max_members"]:
        raise HTTPException(status_code=400, detail="This league is full")

    start_cap = 0 if league["league_type"] == "global" else season_cap_max(league["season_year"])
    sb.table("fantasy_members").insert([{
        "league_id": league["id"],
        "user_id": uid,
        "team_name": req.team_name,
        "cap_space": start_cap,
    }]).execute()
    return _league_summary(sb, league, uid)


@router.get("/fantasy/leagues")
def my_leagues(authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    mine = sb.table("fantasy_members").select("league_id").eq("user_id", uid).execute().data
    league_ids = [m["league_id"] for m in mine]
    if not league_ids:
        return {"leagues": []}
    leagues = sb.table("fantasy_leagues").select("*").in_("id", league_ids).execute().data
    return {"leagues": [_league_summary(sb, lg, uid) for lg in leagues]}


@router.get("/fantasy/leagues/{league_id}")
def league_detail(league_id: str, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    found = sb.table("fantasy_leagues").select("*").eq("id", league_id).execute().data
    if not found:
        raise HTTPException(status_code=404, detail="League not found")
    league = found[0]
    members = sb.table("fantasy_members").select("id,user_id,team_name,draft_order,is_cpu").eq("league_id", league_id).execute().data
    if not any(m["user_id"] == uid for m in members):
        raise HTTPException(status_code=403, detail="You are not a member of this league")
    draft = sb.table("fantasy_draft_state").select("*").eq("league_id", league_id).execute().data

    # Attach usernames for display (CPU members have no user_id).
    user_ids = [m["user_id"] for m in members if m["user_id"]]
    names = {}
    if user_ids:
        profs = sb.table("profiles").select("id,username").in_("id", user_ids).execute().data
        names = {p["id"]: p.get("username") for p in profs}

    return {
        "league": _league_summary(sb, league, uid),
        "members": [{
            "id": m["id"],
            "user_id": m["user_id"],
            "team_name": m["team_name"],
            "draft_order": m.get("draft_order"),
            "username": names.get(m["user_id"]),
            "is_cpu": bool(m.get("is_cpu")),
            "is_me": m["user_id"] == uid,
        } for m in members],
        "draft": draft[0] if draft else None,
        "lottery": league.get("lottery"),
    }


# ---------------------------------------------------------------------------
# Draft engine — lottery + positional-restriction wheel
# ---------------------------------------------------------------------------

def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _member_for_user(sb, league_id: str, uid: str) -> Optional[dict]:
    rows = sb.table("fantasy_members").select("id,user_id,team_name").eq("league_id", league_id).eq("user_id", uid).execute().data
    return rows[0] if rows else None


def _drafted_player_ids(sb, league_id: str) -> set:
    rows = sb.table("fantasy_draft_picks").select("player_id").eq("league_id", league_id).execute().data
    return {r["player_id"] for r in rows}


def _open_slots(sb, member_id: str) -> List[dict]:
    rows = sb.table("fantasy_roster_slots").select("slot,slot_type,player_id").eq("member_id", member_id).execute().data
    return [r for r in rows if r["player_id"] is None]


def _advance_draft(sb, league: dict) -> dict:
    """Lottery: pick a random member with open slots, then a random required slot
    type among the ones they still need. Marks the draft complete when all rosters
    are full. Returns the updated draft_state row."""
    league_id = league["id"]
    members = sb.table("fantasy_members").select("id").eq("league_id", league_id).execute().data
    eligible = [(m["id"], _open_slots(sb, m["id"])) for m in members]
    eligible = [(mid, opens) for mid, opens in eligible if opens]

    state = sb.table("fantasy_draft_state").select("*").eq("league_id", league_id).execute().data[0]

    if not eligible:
        sb.table("fantasy_draft_state").update({
            "status": "complete", "current_member_id": None,
            "required_slot_type": None, "pick_deadline": None, "updated_at": _now(),
        }).eq("league_id", league_id).execute()
        sb.table("fantasy_leagues").update({"status": "active"}).eq("id", league_id).execute()
        _generate_schedule(sb, league_id)
        return sb.table("fantasy_draft_state").select("*").eq("league_id", league_id).execute().data[0]

    picker_id, opens = random.choice(eligible)
    required = random.choice(sorted({s["slot_type"] for s in opens}))
    pick_number = state["current_pick_number"] + 1
    round_no = (pick_number - 1) // max(len(members), 1) + 1

    secs = league.get("pick_clock_seconds") or DEFAULT_PICK_SECONDS
    deadline = (datetime.now(timezone.utc) + timedelta(seconds=secs)).replace(microsecond=0).isoformat()
    sb.table("fantasy_draft_state").update({
        "status": "in_progress",
        "current_pick_number": pick_number,
        "current_member_id": picker_id,
        "required_slot_type": required,
        "round": round_no,
        "pick_deadline": deadline,
        "updated_at": _now(),
    }).eq("league_id", league_id).execute()
    _notify_on_clock(sb, league, picker_id)
    return sb.table("fantasy_draft_state").select("*").eq("league_id", league_id).execute().data[0]


def _assign_pick(sb, league: dict, member_id: str, player_id: str, required: str) -> None:
    """Place a player into the member's first open slot of the required type + log it."""
    slots = sb.table("fantasy_roster_slots").select("id,slot,slot_type,player_id") \
        .eq("member_id", member_id).eq("slot_type", required).execute().data
    target = next((s for s in slots if s["player_id"] is None), None)
    if not target:
        raise HTTPException(status_code=400, detail=f"No open {required} slot")
    state = sb.table("fantasy_draft_state").select("current_pick_number").eq("league_id", league["id"]).execute().data[0]
    sb.table("fantasy_roster_slots").update({"player_id": player_id}).eq("id", target["id"]).execute()
    sb.table("fantasy_draft_picks").insert([{
        "league_id": league["id"],
        "pick_number": state["current_pick_number"],
        "member_id": member_id,
        "player_id": player_id,
        "slot": target["slot"],
        "slot_type": required,
    }]).execute()


def _eligible_pool(sb, league: dict, required: str) -> List[dict]:
    rows = sb.table("fantasy_players").select(
        "id,full_name,team,roster_pos,is_goalie,sweater,headshot"
    ).eq("active", "true").eq("roster_pos", required).order("full_name").limit(1000).execute().data
    if league["unique_players"]:
        taken = _drafted_player_ids(sb, league["id"])
        rows = [r for r in rows if r["id"] not in taken]
    return rows


def _require_league(sb, league_id: str) -> dict:
    found = sb.table("fantasy_leagues").select("*").eq("id", league_id).execute().data
    if not found:
        raise HTTPException(status_code=404, detail="League not found")
    return found[0]


@router.post("/fantasy/leagues/{league_id}/start-draft")
def start_draft(league_id: str, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    if league["commissioner_id"] != uid:
        raise HTTPException(status_code=403, detail="Only the commissioner can start the draft")
    if league["status"] != "open":
        raise HTTPException(status_code=400, detail="Draft already started")
    members = sb.table("fantasy_members").select("id,user_id").eq("league_id", league_id).execute().data
    if len(members) < 2:
        raise HTTPException(status_code=400, detail="Need at least 2 managers to draft")

    order = list(range(1, len(members) + 1))
    random.shuffle(order)
    for m, o in zip(members, order):
        sb.table("fantasy_members").update({"draft_order": o}).eq("id", m["id"]).execute()
        sb.table("fantasy_roster_slots").insert([{
            "league_id": league_id, "member_id": m["id"], "slot": s, "slot_type": st,
        } for s, st in ROSTER_SLOTS]).execute()

    sb.table("fantasy_leagues").update({"status": "drafting", "draft_started_at": _now()}).eq("id", league_id).execute()
    sb.table("fantasy_draft_state").update({
        "total_picks": len(members) * SLOTS_PER_TEAM, "current_pick_number": 0,
    }).eq("league_id", league_id).execute()
    _advance_draft(sb, league)
    _push_users(sb, [m["user_id"] for m in members], "Draft started! 🏒",
                f"{league['name']} is drafting — watch for your turn to pick.")
    return get_draft(league_id, authorization)


class PickRequest(BaseModel):
    player_id: str


@router.post("/fantasy/leagues/{league_id}/draft/pick")
def make_pick(league_id: str, req: PickRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    state = sb.table("fantasy_draft_state").select("*").eq("league_id", league_id).execute().data[0]
    if state["status"] != "in_progress":
        raise HTTPException(status_code=400, detail="Draft is not in progress")
    me = _member_for_user(sb, league_id, uid)
    if not me:
        raise HTTPException(status_code=403, detail="You are not in this league")
    if state["current_member_id"] != me["id"]:
        raise HTTPException(status_code=403, detail="It's not your pick")

    # Off-season prospect draft: cap-enforced pick of a prospect into an open farm slot.
    if league.get("season_phase") == "offseason_draft":
        prow = sb.table("fantasy_players").select("id,is_prospect,cost").eq("id", req.player_id).execute().data
        if not prow or not prow[0].get("is_prospect"):
            raise HTTPException(status_code=400, detail="Pick a prospect")
        if req.player_id in _drafted_player_ids(sb, league_id):
            raise HTTPException(status_code=400, detail="That prospect is already drafted")
        cost = prow[0].get("cost") or 0
        if cost > _member_cap(sb, me["id"]):
            raise HTTPException(status_code=400, detail="Over the cap for that prospect — trade or pick a cheaper one")
        slot = _first_open_farm(sb, me["id"])
        if not slot:
            raise HTTPException(status_code=400, detail="Your prospect slots are full")
        _assign_prospect(sb, league, me["id"], req.player_id, slot, state["current_pick_number"], cost)
        _offseason_advance(sb, league)
        return get_draft(league_id, authorization)

    required = state["required_slot_type"]
    player = sb.table("fantasy_players").select("id,roster_pos").eq("id", req.player_id).execute().data
    if not player or player[0]["roster_pos"] != required:
        raise HTTPException(status_code=400, detail=f"That player isn't an eligible {required}")
    if league["unique_players"] and req.player_id in _drafted_player_ids(sb, league_id):
        raise HTTPException(status_code=400, detail="That player is already drafted")

    _assign_pick(sb, league, me["id"], req.player_id, required)
    _advance_draft(sb, league)
    return get_draft(league_id, authorization)


@router.post("/fantasy/leagues/{league_id}/draft/autopick")
def autopick(league_id: str, expected_pick: Optional[int] = None, authorization: Optional[str] = Header(None)):
    """Auto-pick a random eligible player for whoever is on the clock. Callable by
    the commissioner, the current picker, or — once the pick clock has expired —
    any member (so live drafts advance on time). `expected_pick` guards against
    double-advancing when several clients fire at once."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    state = sb.table("fantasy_draft_state").select("*").eq("league_id", league_id).execute().data[0]
    if state["status"] != "in_progress":
        raise HTTPException(status_code=400, detail="Draft is not in progress")
    # Idempotency: if the pick already advanced, no-op (someone else acted first).
    if expected_pick is not None and state["current_pick_number"] != expected_pick:
        return get_draft(league_id, authorization)
    me = _member_for_user(sb, league_id, uid)
    expired = bool(state.get("pick_deadline")) and state["pick_deadline"] < datetime.now(timezone.utc).isoformat()
    if not me or not (league["commissioner_id"] == uid or state["current_member_id"] == me["id"] or expired):
        raise HTTPException(status_code=403, detail="Not allowed to autopick now")

    if league.get("season_phase") == "offseason_draft":
        _cpu_prospect_pick(sb, league, state["current_member_id"], state["current_pick_number"])
        _offseason_advance(sb, league)
        return get_draft(league_id, authorization)

    required = state["required_slot_type"]
    pool = _eligible_pool(sb, league, required)
    if not pool:
        raise HTTPException(status_code=400, detail=f"No available {required}")
    _assign_pick(sb, league, state["current_member_id"], random.choice(pool)["id"], required)
    _advance_draft(sb, league)
    return get_draft(league_id, authorization)


@router.get("/fantasy/leagues/{league_id}/draft")
def get_draft(league_id: str, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    me = _member_for_user(sb, league_id, uid)
    if not me:
        raise HTTPException(status_code=403, detail="You are not in this league")
    state = sb.table("fantasy_draft_state").select("*").eq("league_id", league_id).execute().data[0]
    members = sb.table("fantasy_members").select("id,user_id,team_name,draft_order,is_cpu").eq("league_id", league_id).execute().data
    offseason = league.get("season_phase") == "offseason_draft"

    # Usernames (CPU members have no user_id)
    user_ids = [m["user_id"] for m in members if m["user_id"]]
    names = {}
    if user_ids:
        profs = sb.table("profiles").select("id,username").in_("id", user_ids).execute().data
        names = {p["id"]: p.get("username") for p in profs}

    # Rosters (slots + drafted player info)
    slots = sb.table("fantasy_roster_slots").select("member_id,slot,slot_type,player_id").eq("league_id", league_id).execute().data
    pids = [s["player_id"] for s in slots if s["player_id"]]
    players_by_id = {}
    if pids:
        prows = sb.table("fantasy_players").select("id,full_name,team,roster_pos,sweater,cost,prospect_ranking,is_prospect").in_("id", list(set(pids))).execute().data
        players_by_id = {p["id"]: p for p in prows}

    rosters = {}
    for m in members:
        rosters[m["id"]] = []
    for s in slots:
        p = players_by_id.get(s["player_id"]) if s["player_id"] else None
        rosters.setdefault(s["member_id"], []).append({
            "slot": s["slot"], "slot_type": s["slot_type"],
            "player": p,
        })

    current_id = state.get("current_member_id")
    current_member = next((m for m in members if m["id"] == current_id), None)
    if state["status"] != "in_progress":
        available = []
    elif offseason:
        available = _offseason_eligible(sb, league)
    else:
        available = _eligible_pool(sb, league, state["required_slot_type"])

    slot_order = [s for s, _ in (ROSTER_SLOTS + FARM_SLOTS)]
    return {
        "league": _league_summary(sb, league, uid),
        "state": {
            "status": state["status"],
            "pick_number": state["current_pick_number"],
            "total_picks": state["total_picks"],
            "round": state["round"],
            "required_slot_type": state["required_slot_type"],
            "current_member_id": current_id,
            "current_team_name": current_member["team_name"] if current_member else None,
            "current_username": (names.get(current_member["user_id"]) if current_member and current_member.get("user_id") else ("CPU" if current_member else None)),
            "is_my_pick": current_id == me["id"],
            "pick_deadline": state.get("pick_deadline"),
            "is_offseason": offseason,
            "my_cap_space": _member_cap(sb, me["id"]),
        },
        "members": [{
            "id": m["id"], "team_name": m["team_name"], "draft_order": m.get("draft_order"),
            "username": names.get(m["user_id"]), "is_cpu": bool(m.get("is_cpu")), "is_me": m["user_id"] == uid,
            "roster": sorted(rosters.get(m["id"], []), key=lambda r: slot_order.index(r["slot"]) if r["slot"] in slot_order else 99),
        } for m in members],
        "available_players": available,
    }


# ---------------------------------------------------------------------------
# Off-season franchise cycle: reset → random roster → (lottery → draft → trades)
# ---------------------------------------------------------------------------

def _member_roster_cost(sb, member_id: str) -> int:
    slots = sb.table("fantasy_roster_slots").select("player_id").eq("member_id", member_id).execute().data
    pids = [s["player_id"] for s in slots if s["player_id"]]
    if not pids:
        return 0
    total = 0
    for p in sb.table("fantasy_players").select("cost").in_("id", list(set(pids))).execute().data:
        total += p.get("cost") or 0
    return total


def _random_starter_roster(sb, league: dict, member: dict) -> None:
    """Fill a member's 12 active NHL slots with random affordable players (one per
    position), deducting their cost from the franchise Cap Space bank. Always leaves
    enough room to fill the remaining slots at the league minimum (feasible)."""
    budget = (member.get("cap_space") or 0)
    slots = sb.table("fantasy_roster_slots").select("id,slot,slot_type,player_id") \
        .eq("member_id", member["id"]).execute().data
    active = [s for s in slots if s["slot_type"] != "FARM" and s["player_id"] is None]
    pool: dict = {}
    for st in {st for _, st in ROSTER_SLOTS}:
        pool[st] = sb.table("fantasy_players").select("id,cost") \
            .eq("active", "true").eq("is_prospect", "false").eq("roster_pos", st).limit(600).execute().data
    remaining = budget
    n = len(active)
    for i, slot in enumerate(active):
        slots_left_after = n - i - 1
        cap_here = remaining - _NHL_MIN * slots_left_after
        bucket = pool.get(slot["slot_type"], [])
        cands = [p for p in bucket if (p.get("cost") or _NHL_MIN) <= cap_here]
        if not cands:
            cands = [p for p in bucket if (p.get("cost") or _NHL_MIN) <= remaining] or bucket
        if not cands:
            continue
        pick = random.choice(cands)
        sb.table("fantasy_roster_slots").update({"player_id": pick["id"]}).eq("id", slot["id"]).execute()
        remaining -= (pick.get("cost") or _NHL_MIN)
    sb.table("fantasy_members").update({"cap_space": max(0, remaining)}).eq("id", member["id"]).execute()


def _archive_season(sb, league: dict, members: list) -> None:
    """Best-effort archive of the season being left behind (kept across the reset)."""
    season = league["season_year"]
    rows = []
    for m in members:
        rows.append({
            "league_id": league["id"], "season_year": season, "member_id": m["id"],
            "team_name": m.get("team_name"), "team_rating": _member_roster_cost(sb, m["id"]),
        })
    if rows:
        try:
            sb.table("fantasy_team_archive").upsert(rows, on_conflict="league_id,season_year,member_id").execute()
        except Exception:
            pass   # archive is best-effort; never block the reset


def _enter_offseason(sb, league: dict) -> None:
    """Reset a group/solo league into the off-season build phase: archive the prior
    season (if any), clear rosters/matchups, keep each manager's Cap Space, seed a
    random affordable NHL starter roster, recreate roster slots (12 active + farm), and
    mint this season's draft-pick assets. Leaves the league in `offseason_lottery`."""
    league_id = league["id"]
    season = league["season_year"]
    members = sb.table("fantasy_members").select("id,user_id,team_name,cap_space").eq("league_id", league_id).execute().data
    if not members:
        raise HTTPException(status_code=400, detail="League has no managers")

    if league.get("status") in ("active", "playoffs", "complete"):
        _archive_season(sb, league, members)

    # Clear rosters, picks, schedule (Cap Space on fantasy_members is preserved).
    for tbl in ("fantasy_weekly_results", "fantasy_matchups", "fantasy_draft_picks", "fantasy_roster_slots"):
        try:
            sb.table(tbl).delete().eq("league_id", league_id).execute()
        except Exception:
            pass

    # Recreate roster slots (12 active + farm) and seed a random starter roster.
    for m in members:
        sb.table("fantasy_roster_slots").insert([{
            "league_id": league_id, "member_id": m["id"], "slot": s, "slot_type": st,
        } for s, st in (ROSTER_SLOTS + FARM_SLOTS)]).execute()
        _random_starter_roster(sb, league, m)

    # Mint draft-pick assets: one per round per member (lottery sets the order next).
    sb.table("fantasy_draft_pick_assets").delete().eq("league_id", league_id).eq("season_year", season).execute()
    assets = []
    for rnd in range(1, OFFSEASON_ROUNDS + 1):
        for m in members:
            assets.append({"league_id": league_id, "season_year": season, "round": rnd,
                           "original_member_id": m["id"], "owner_member_id": m["id"]})
    if assets:
        sb.table("fantasy_draft_pick_assets").insert(assets).execute()

    sb.table("fantasy_leagues").update({"status": "open", "season_phase": "offseason_lottery"}).eq("id", league_id).execute()
    sb.table("fantasy_draft_state").update({
        "status": "not_started", "current_pick_number": 0, "current_member_id": None,
        "required_slot_type": None, "round": 0, "updated_at": _now(),
    }).eq("league_id", league_id).execute()


@router.post("/fantasy/leagues/{league_id}/start-offseason")
def start_offseason(league_id: str, authorization: Optional[str] = Header(None)):
    """Commissioner: drop the league into the off-season build phase (reset + random
    starter rosters + Cap Space carryover + draft-pick assets), ready for the lottery."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    if league["commissioner_id"] != uid:
        raise HTTPException(status_code=403, detail="Only the commissioner can start the off-season")
    if league.get("league_type") == "global":
        raise HTTPException(status_code=400, detail="The global league has no off-season draft")
    _enter_offseason(sb, league)
    return _league_summary(sb, _require_league(sb, league_id), uid)


def _run_lottery(sb, league: dict) -> dict:
    """Weighted draft lottery: a worse prior-season finish earns better odds (NHL-style);
    a fresh league draws with equal odds. Assigns each member's draft_order, stores the
    odds + a suspense reveal sequence on the league, and advances to offseason_draft."""
    league_id = league["id"]
    members = sb.table("fantasy_members").select("id,user_id,team_name").eq("league_id", league_id).execute().data
    if not members:
        raise HTTPException(status_code=400, detail="League has no managers")
    uids = [m["user_id"] for m in members if m["user_id"]]
    names = {p["id"]: p.get("username") for p in sb.table("profiles").select("id,username").in_("id", uids).execute().data} if uids else {}

    # Weight by the most recent archived final_rank (worst finish = most weight); new = equal.
    archive: dict = {}
    for a in sb.table("fantasy_team_archive").select("member_id,final_rank,season_year").eq("league_id", league_id).execute().data:
        cur = archive.get(a["member_id"])
        if not cur or (a.get("season_year") or 0) >= (cur.get("season_year") or 0):
            archive[a["member_id"]] = a
    weights = {m["id"]: ((archive.get(m["id"]) or {}).get("final_rank") or 1) for m in members}
    total0 = sum(weights.values()) or 1

    # Weighted draw without replacement → pick order (index 0 = 1st overall).
    pool, w, order = members[:], dict(weights), []
    while pool:
        tot = sum(w[m["id"]] for m in pool) or 1
        r = random.uniform(0, tot)
        acc = 0.0
        chosen = pool[-1]
        for m in pool:
            acc += w[m["id"]]
            if r <= acc:
                chosen = m
                break
        order.append(chosen)
        pool.remove(chosen)

    odds = {m["id"]: round(weights[m["id"]] / total0 * 100, 1) for m in members}
    rows = []
    for i, m in enumerate(order):
        pick = i + 1
        sb.table("fantasy_members").update({"draft_order": pick}).eq("id", m["id"]).execute()
        rows.append({"pick": pick, "member_id": m["id"], "team_name": m["team_name"],
                     "username": names.get(m["user_id"]), "odds": odds[m["id"]]})
    payload = {"order": rows, "reveal": list(reversed(rows)), "ran_at": _now()}   # reveal from last pick → #1
    sb.table("fantasy_leagues").update({"lottery": payload, "season_phase": "offseason_draft"}).eq("id", league_id).execute()
    league["season_phase"] = "offseason_draft"
    _start_prospect_draft(sb, league)   # put the snake draft on the clock (auto-runs leading CPU picks)
    return payload


@router.post("/fantasy/leagues/{league_id}/lottery/run")
def run_lottery(league_id: str, authorization: Optional[str] = Header(None)):
    """Commissioner: run the weighted draft lottery and return the reveal sequence."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    if league["commissioner_id"] != uid:
        raise HTTPException(status_code=403, detail="Only the commissioner can run the lottery")
    if league.get("season_phase") != "offseason_lottery":
        raise HTTPException(status_code=400, detail="The lottery isn't open right now")
    return _run_lottery(sb, league)


# --- Prospect draft (snake by lottery order, into the farm; cap-enforced) -----

def _snake_member(order_ids: list, n: int, pick_number: int) -> str:
    """Member on the clock for a 1-based snake pick (round 1 ascending, round 2 reversed…)."""
    rnd, pos = divmod(pick_number - 1, n)
    if rnd % 2 == 1:
        pos = n - 1 - pos
    return order_ids[pos]


def _offseason_eligible(sb, league: dict) -> List[dict]:
    """Undrafted prospects for this league, best consensus rank first."""
    taken = _drafted_player_ids(sb, league["id"])
    rows = sb.table("fantasy_players").select(
        "id,full_name,team,roster_pos,is_goalie,sweater,headshot,cost,prospect_ranking,is_prospect"
    ).eq("is_prospect", "true").order("prospect_ranking").limit(400).execute().data
    return [r for r in rows if r["id"] not in taken]


def _first_open_farm(sb, member_id: str) -> Optional[dict]:
    rows = sb.table("fantasy_roster_slots").select("id,slot,slot_type,player_id") \
        .eq("member_id", member_id).eq("slot_type", "FARM").execute().data
    return next((r for r in rows if r["player_id"] is None), None)


def _member_cap(sb, member_id: str) -> int:
    rows = sb.table("fantasy_members").select("cap_space").eq("id", member_id).execute().data
    return (rows[0].get("cap_space") if rows else 0) or 0


def _assign_prospect(sb, league: dict, member_id: str, player_id: str, slot_row: dict, pick_number: int, cost: int) -> None:
    sb.table("fantasy_roster_slots").update({"player_id": player_id}).eq("id", slot_row["id"]).execute()
    sb.table("fantasy_draft_picks").insert([{
        "league_id": league["id"], "pick_number": pick_number, "member_id": member_id,
        "player_id": player_id, "slot": slot_row["slot"], "slot_type": "FARM",
    }]).execute()
    sb.table("fantasy_members").update({"cap_space": max(0, _member_cap(sb, member_id) - (cost or 0))}).eq("id", member_id).execute()


def _cpu_prospect_pick(sb, league: dict, member_id: str, pick_number: int) -> bool:
    """A CPU (or auto-pick) takes the best-ranked prospect it can afford for an open farm slot."""
    slot = _first_open_farm(sb, member_id)
    if not slot:
        return False
    pool = _offseason_eligible(sb, league)
    if not pool:
        return False
    cap = _member_cap(sb, member_id)
    pick = next((p for p in pool if (p.get("cost") or 0) <= cap), None) or min(pool, key=lambda p: p.get("cost") or 0)
    _assign_prospect(sb, league, member_id, pick["id"], slot, pick_number, pick.get("cost") or 0)
    return True


def _offseason_advance(sb, league: dict) -> None:
    """Advance the snake prospect draft, auto-running CPU picks until a human is on the
    clock or the draft completes (→ offseason_open)."""
    league_id = league["id"]
    members = sb.table("fantasy_members").select("id,user_id,draft_order,is_cpu").eq("league_id", league_id).execute().data
    order_ids = [m["id"] for m in sorted(members, key=lambda m: (m.get("draft_order") or 999))]
    by_id = {m["id"]: m for m in members}
    n = len(order_ids)
    total = n * OFFSEASON_ROUNDS
    pick = sb.table("fantasy_draft_state").select("current_pick_number").eq("league_id", league_id).execute().data[0]["current_pick_number"]
    while True:
        pick += 1
        if pick > total:
            sb.table("fantasy_draft_state").update({
                "status": "complete", "current_pick_number": total, "current_member_id": None,
                "required_slot_type": None, "pick_deadline": None, "updated_at": _now(),
            }).eq("league_id", league_id).execute()
            sb.table("fantasy_leagues").update({"season_phase": "offseason_open"}).eq("id", league_id).execute()
            return
        picker_id = _snake_member(order_ids, n, pick)
        rnd = (pick - 1) // n + 1
        if by_id[picker_id].get("is_cpu"):
            _cpu_prospect_pick(sb, league, picker_id, pick)
            sb.table("fantasy_draft_state").update({"current_pick_number": pick, "round": rnd, "updated_at": _now()}).eq("league_id", league_id).execute()
            continue
        secs = league.get("pick_clock_seconds") or DEFAULT_PICK_SECONDS
        deadline = (datetime.now(timezone.utc) + timedelta(seconds=secs)).replace(microsecond=0).isoformat()
        sb.table("fantasy_draft_state").update({
            "status": "in_progress", "current_pick_number": pick, "current_member_id": picker_id,
            "required_slot_type": "FARM", "round": rnd, "pick_deadline": deadline, "updated_at": _now(),
        }).eq("league_id", league_id).execute()
        return


def _start_prospect_draft(sb, league: dict) -> None:
    league_id = league["id"]
    n = len(sb.table("fantasy_members").select("id").eq("league_id", league_id).execute().data)
    sb.table("fantasy_draft_state").update({
        "status": "in_progress", "current_pick_number": 0, "total_picks": n * OFFSEASON_ROUNDS,
        "round": 0, "current_member_id": None, "required_slot_type": "FARM", "updated_at": _now(),
    }).eq("league_id", league_id).execute()
    _offseason_advance(sb, league)


# ---------------------------------------------------------------------------
# In-season: schedule, scoring, standings
# ---------------------------------------------------------------------------

def _generate_schedule(sb, league_id: str) -> None:
    """Round-robin weekly H2H (circle method). Odd groups get a rotating bye
    (ghost = league median that week). Fills REG_SEASON_WEEKS."""
    members = sb.table("fantasy_members").select("id").eq("league_id", league_id).execute().data
    ids: list = [m["id"] for m in members]
    random.shuffle(ids)
    if len(ids) % 2 == 1:
        ids.append(None)  # bye marker
    n = len(ids)
    arr = ids[:]
    rounds: list = []
    for _ in range(max(n - 1, 1)):
        pairs = [(arr[i], arr[n - 1 - i]) for i in range(n // 2)]
        rounds.append(pairs)
        arr = [arr[0]] + [arr[-1]] + arr[1:-1]  # rotate, fix first

    rows = []
    for week in range(1, REG_SEASON_WEEKS + 1):
        for a, b in rounds[(week - 1) % len(rounds)]:
            if a is None and b is None:
                continue
            ghost = a is None or b is None
            member_a, member_b = (a, b) if a is not None else (b, None)
            rows.append({
                "league_id": league_id, "week": week,
                "member_a": member_a, "member_b": None if ghost else member_b,
                "is_ghost": ghost,
            })
    if rows:
        for i in range(0, len(rows), 200):
            sb.table("fantasy_matchups").insert(rows[i:i + 200]).execute()


def _score_week(sb, league: dict, week: int, surviving_only: bool = False) -> list:
    """Score every matchup in a week from the ingested weekly stats. When
    `surviving_only` (playoffs), players whose NHL team is eliminated score 0."""
    league_id = league["id"]
    season = league["season_year"]
    matchups = sb.table("fantasy_matchups").select("*").eq("league_id", league_id).eq("week", week).execute().data
    if not matchups:
        return []
    if any(m.get("is_playoff") for m in matchups):
        surviving_only = True

    slots = sb.table("fantasy_roster_slots").select("member_id,slot,slot_type,player_id").eq("league_id", league_id).execute().data
    skater_ids = list({s["player_id"] for s in slots if s["player_id"] and s["slot_type"] != "G"})
    goalie_ids = list({s["player_id"] for s in slots if s["player_id"] and s["slot_type"] == "G"})

    goals = {}
    if skater_ids:
        for r in sb.table("fantasy_weekly_player_goals").select("player_id,goals").eq("season_year", season).eq("week", week).in_("player_id", skater_ids).execute().data:
            goals[r["player_id"]] = r["goals"]
    gstats = {}
    if goalie_ids:
        for r in sb.table("fantasy_weekly_goalie_stats").select("player_id,gsax,games_played").eq("season_year", season).eq("week", week).in_("player_id", goalie_ids).execute().data:
            gstats[r["player_id"]] = (r["gsax"], r["games_played"])

    # Playoffs: zero out players on eliminated NHL teams.
    dead: set = set()
    if surviving_only:
        elim = {r["team"] for r in sb.table("fantasy_eliminated_teams").select("team").eq("season_year", season).execute().data}
        allpids = skater_ids + goalie_ids
        if elim and allpids:
            for p in sb.table("fantasy_players").select("id,team").in_("id", allpids).execute().data:
                if p["team"] in elim:
                    dead.add(p["id"])

    slots_by_member = defaultdict(list)
    for s in slots:
        slots_by_member[s["member_id"]].append(s)

    raw, gsax = {}, {}
    for mid, ms in slots_by_member.items():
        raw[mid] = sum(goals.get(s["player_id"], 0) for s in ms
                       if s["slot_type"] != "G" and s["player_id"] and s["player_id"] not in dead)
        starter = next((s["player_id"] for s in ms if s["slot"] == "G_START"), None)
        backup = next((s["player_id"] for s in ms if s["slot"] == "G_BACKUP"), None)
        if starter in dead: starter = None
        if backup in dead: backup = None
        sg = gstats.get(starter) if starter else None
        eff = sg[0] if sg and sg[1] > 0 else (gstats.get(backup, (0.0, 0))[0] if backup else 0.0)
        gsax[mid] = eff

    median_raw = statistics.median(list(raw.values())) if raw else 0.0

    out = []
    for m in matchups:
        a, b = m["member_a"], m["member_b"]
        raw_a = float(raw.get(a, 0))
        if m["is_ghost"] or not b:
            score_a, score_b, ba, bb = raw_a, float(median_raw), 1.0, 1.0
            winner = a if score_a > score_b else None
        else:
            raw_b = float(raw.get(b, 0))
            ga, gb = gsax.get(a, 0.0), gsax.get(b, 0.0)
            ba = GOALIE_BONUS if ga > gb else (GOALIE_PENALTY if ga < gb else 1.0)
            bb = GOALIE_BONUS if gb > ga else (GOALIE_PENALTY if gb < ga else 1.0)
            score_a, score_b = raw_a * ba, raw_b * bb
            winner = a if score_a > score_b else (b if score_b > score_a else None)
        out.append({
            "league_id": league_id, "week": week, "member_a": a, "member_b": b,
            "score_a": round(score_a, 2), "score_b": round(score_b, 2),
            "goalie_bonus_a": ba, "goalie_bonus_b": bb,
            "winner_member_id": winner, "graded": True, "updated_at": _now(),
        })
    if out:
        sb.table("fantasy_weekly_results").upsert(out, on_conflict="league_id,week,member_a").execute()
    return out


@router.post("/fantasy/leagues/{league_id}/score-week/{week}")
def score_week(league_id: str, week: int, authorization: Optional[str] = Header(None)):
    """Score a week from already-ingested stats (commissioner / cron)."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    if league["commissioner_id"] != uid:
        raise HTTPException(status_code=403, detail="Only the commissioner can score")
    results = _score_week(sb, league, week)
    return {"week": week, "results": len(results)}


@router.post("/fantasy/leagues/{league_id}/simulate-week/{week}")
def simulate_week(league_id: str, week: int, authorization: Optional[str] = Header(None)):
    """OFFSEASON TEST ONLY: generate plausible random weekly stats for every
    rostered player, then score the week. Lets us verify scoring + standings
    before real games exist."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    if league["commissioner_id"] != uid:
        raise HTTPException(status_code=403, detail="Only the commissioner can simulate")
    season = league["season_year"]

    slots = sb.table("fantasy_roster_slots").select("slot_type,player_id").eq("league_id", league_id).execute().data
    skaters = list({s["player_id"] for s in slots if s["player_id"] and s["slot_type"] != "G"})
    goalies = list({s["player_id"] for s in slots if s["player_id"] and s["slot_type"] == "G"})

    skater_rows = [{
        "player_id": pid, "season_year": season, "week": week,
        "goals": random.choices([0, 1, 2, 3, 4], weights=[40, 32, 18, 8, 2])[0],
        "games_played": random.randint(2, 4), "updated_at": _now(),
    } for pid in skaters]
    goalie_rows = [{
        "player_id": pid, "season_year": season, "week": week,
        "gsax": round(random.uniform(-3.0, 4.0), 2),
        "games_played": random.randint(0, 4), "updated_at": _now(),
    } for pid in goalies]

    if skater_rows:
        for i in range(0, len(skater_rows), 200):
            sb.table("fantasy_weekly_player_goals").upsert(skater_rows[i:i + 200], on_conflict="player_id,season_year,week").execute()
    if goalie_rows:
        sb.table("fantasy_weekly_goalie_stats").upsert(goalie_rows, on_conflict="player_id,season_year,week").execute()

    results = _score_week(sb, league, week)
    return {"week": week, "simulated_players": len(skaters) + len(goalies), "results": len(results)}


@router.get("/fantasy/leagues/{league_id}/season")
def season(league_id: str, authorization: Optional[str] = Header(None)):
    """Everything the in-season screen needs: standings, my roster, schedule."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    members = sb.table("fantasy_members").select("id,user_id,team_name").eq("league_id", league_id).execute().data
    me = next((m for m in members if m["user_id"] == uid), None)
    if not me:
        raise HTTPException(status_code=403, detail="You are not a member of this league")

    names = {}
    profs = sb.table("profiles").select("id,username").in_("id", [m["user_id"] for m in members]).execute().data
    names = {p["id"]: p.get("username") for p in profs}
    team_of = {m["id"]: m["team_name"] for m in members}

    results = sb.table("fantasy_weekly_results").select("*").eq("league_id", league_id).eq("graded", True).execute().data

    # Standings
    rec = {m["id"]: {"wins": 0, "losses": 0, "ties": 0, "pf": 0.0} for m in members}
    for r in results:
        a, b, w = r["member_a"], r["member_b"], r["winner_member_id"]
        rec[a]["pf"] += r["score_a"]
        if b and b in rec:
            rec[b]["pf"] += r["score_b"]
        if w is None:
            rec[a]["ties"] += 1
            if b and b in rec: rec[b]["ties"] += 1
        else:
            for mid in (a, b):
                if mid and mid in rec:
                    if mid == w: rec[mid]["wins"] += 1
                    else: rec[mid]["losses"] += 1
    standings = sorted([{
        "member_id": m["id"], "team_name": m["team_name"], "username": names.get(m["user_id"]),
        "is_me": m["id"] == me["id"], **rec[m["id"]], "pf": round(rec[m["id"]]["pf"], 1),
    } for m in members], key=lambda x: (-x["wins"], -x["pf"]))

    # My roster
    my_slots = sb.table("fantasy_roster_slots").select("slot,slot_type,player_id").eq("league_id", league_id).eq("member_id", me["id"]).execute().data
    pids = [s["player_id"] for s in my_slots if s["player_id"]]
    pmap = {}
    if pids:
        for p in sb.table("fantasy_players").select("id,full_name,team,roster_pos,sweater").in_("id", pids).execute().data:
            pmap[p["id"]] = p
    order = [s for s, _ in ROSTER_SLOTS]
    my_roster = sorted([{
        "slot": s["slot"], "slot_type": s["slot_type"], "player": pmap.get(s["player_id"]) if s["player_id"] else None,
    } for s in my_slots], key=lambda r: order.index(r["slot"]) if r["slot"] in order else 99)

    # Schedule (results overlaid)
    matchups = sb.table("fantasy_matchups").select("*").eq("league_id", league_id).order("week").execute().data
    res_by_key = {(r["week"], r["member_a"]): r for r in results}
    schedule = []
    for mch in matchups:
        r = res_by_key.get((mch["week"], mch["member_a"]))
        schedule.append({
            "week": mch["week"], "member_a": mch["member_a"], "member_b": mch["member_b"],
            "a_team": team_of.get(mch["member_a"]), "b_team": team_of.get(mch["member_b"]) if mch["member_b"] else "League median",
            "is_ghost": mch["is_ghost"],
            "score_a": r["score_a"] if r else None, "score_b": r["score_b"] if r else None,
            "winner_member_id": r["winner_member_id"] if r else None,
            "graded": bool(r),
            "involves_me": me["id"] in (mch["member_a"], mch["member_b"]),
        })
    graded_weeks = [s["week"] for s in schedule if s["graded"]]
    current_week = (max(graded_weeks) + 1) if graded_weeks else 1

    return {
        "league": _league_summary(sb, league, uid),
        "current_week": current_week,
        "my_member_id": me["id"],
        "standings": standings,
        "my_roster": my_roster,
        "schedule": schedule,
    }


# ---------------------------------------------------------------------------
# G5a: Trades (private leagues only)
# ---------------------------------------------------------------------------

def _current_week(sb, league_id: str) -> int:
    weeks = [r["week"] for r in sb.table("fantasy_weekly_results").select("week").eq("league_id", league_id).eq("graded", True).execute().data]
    return (max(weeks) + 1) if weeks else 1


class ProposeTradeRequest(BaseModel):
    to_member_id: str
    my_player_id: str
    their_player_id: str


@router.post("/fantasy/leagues/{league_id}/trades")
def propose_trade(league_id: str, req: ProposeTradeRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    if not (league["unique_players"] and league["trade_deadline_enabled"]):
        raise HTTPException(status_code=400, detail="Trades are only available in private leagues")
    if league["status"] != "active":
        raise HTTPException(status_code=400, detail="Trades open during the regular season")
    if _current_week(sb, league_id) > TRADE_DEADLINE_WEEK:
        raise HTTPException(status_code=400, detail=f"The trade deadline (week {TRADE_DEADLINE_WEEK}) has passed")
    me = _member_for_user(sb, league_id, uid)
    if not me:
        raise HTTPException(status_code=403, detail="You are not in this league")

    mine = sb.table("fantasy_roster_slots").select("slot_type,player_id").eq("member_id", me["id"]).eq("player_id", req.my_player_id).execute().data
    theirs = sb.table("fantasy_roster_slots").select("slot_type,player_id").eq("member_id", req.to_member_id).eq("player_id", req.their_player_id).execute().data
    if not mine or not theirs:
        raise HTTPException(status_code=400, detail="Both players must be on the respective rosters")
    if mine[0]["slot_type"] != theirs[0]["slot_type"]:
        raise HTTPException(status_code=400, detail="You can only trade players of the same position")

    trade = sb.table("fantasy_trades").insert([{
        "league_id": league_id, "proposer_member": me["id"], "receiver_member": req.to_member_id,
        "proposer_player_id": req.my_player_id, "receiver_player_id": req.their_player_id,
        "slot_type": mine[0]["slot_type"], "status": "pending",
    }]).data[0]
    return {"trade_id": trade["id"], "status": "pending"}


class RespondTradeRequest(BaseModel):
    accept: bool


@router.post("/fantasy/leagues/{league_id}/trades/{trade_id}/respond")
def respond_trade(league_id: str, trade_id: str, req: RespondTradeRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    rows = sb.table("fantasy_trades").select("*").eq("id", trade_id).eq("league_id", league_id).execute().data
    if not rows:
        raise HTTPException(status_code=404, detail="Trade not found")
    trade = rows[0]
    me = _member_for_user(sb, league_id, uid)
    if not me or trade["receiver_member"] != me["id"]:
        raise HTTPException(status_code=403, detail="Only the receiving manager can respond")
    if trade["status"] != "pending":
        raise HTTPException(status_code=400, detail="Trade already resolved")

    if req.accept:
        # Swap the two players within their (same-type) slots.
        my_slot = sb.table("fantasy_roster_slots").select("id").eq("member_id", trade["proposer_member"]).eq("player_id", trade["proposer_player_id"]).execute().data
        their_slot = sb.table("fantasy_roster_slots").select("id").eq("member_id", trade["receiver_member"]).eq("player_id", trade["receiver_player_id"]).execute().data
        if not my_slot or not their_slot:
            raise HTTPException(status_code=400, detail="Rosters changed; trade no longer valid")
        sb.table("fantasy_roster_slots").update({"player_id": trade["receiver_player_id"]}).eq("id", my_slot[0]["id"]).execute()
        sb.table("fantasy_roster_slots").update({"player_id": trade["proposer_player_id"]}).eq("id", their_slot[0]["id"]).execute()

    sb.table("fantasy_trades").update({
        "status": "accepted" if req.accept else "rejected", "resolved_at": _now(),
    }).eq("id", trade_id).execute()
    return {"status": "accepted" if req.accept else "rejected"}


@router.get("/fantasy/leagues/{league_id}/trades")
def list_trades(league_id: str, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    _require_league(sb, league_id)
    me = _member_for_user(sb, league_id, uid)
    if not me:
        raise HTTPException(status_code=403, detail="You are not in this league")
    trades = sb.table("fantasy_trades").select("*").eq("league_id", league_id).order("created_at", desc=True).execute().data
    trades = [t for t in trades if me["id"] in (t["proposer_member"], t["receiver_member"])]
    pids = list({t["proposer_player_id"] for t in trades} | {t["receiver_player_id"] for t in trades})
    pmap = {}
    if pids:
        for p in sb.table("fantasy_players").select("id,full_name,team").in_("id", pids).execute().data:
            pmap[p["id"]] = p
    mids = list({t["proposer_member"] for t in trades} | {t["receiver_member"] for t in trades})
    tmap = {}
    if mids:
        for m in sb.table("fantasy_members").select("id,team_name").in_("id", mids).execute().data:
            tmap[m["id"]] = m["team_name"]
    return {"trades": [{
        "id": t["id"], "status": t["status"], "slot_type": t["slot_type"],
        "incoming": t["receiver_member"] == me["id"] and t["status"] == "pending",
        "proposer_team": tmap.get(t["proposer_member"]), "receiver_team": tmap.get(t["receiver_member"]),
        "proposer_player": pmap.get(t["proposer_player_id"]), "receiver_player": pmap.get(t["receiver_player_id"]),
    } for t in trades]}


# ---------------------------------------------------------------------------
# G5b: Playoffs
# ---------------------------------------------------------------------------

def _standings_order(sb, league_id: str) -> list:
    members = sb.table("fantasy_members").select("id").eq("league_id", league_id).execute().data
    rec = {m["id"]: {"wins": 0, "pf": 0.0} for m in members}
    for r in sb.table("fantasy_weekly_results").select("*").eq("league_id", league_id).eq("graded", True).execute().data:
        a, b, w = r["member_a"], r["member_b"], r["winner_member_id"]
        if a in rec: rec[a]["pf"] += r["score_a"]
        if b and b in rec: rec[b]["pf"] += r["score_b"]
        if w and w in rec: rec[w]["wins"] += 1
    return [m["id"] for m in sorted(members, key=lambda m: (-rec[m["id"]]["wins"], -rec[m["id"]]["pf"]))]


@router.post("/fantasy/leagues/{league_id}/eliminate-team/{season}/{team}")
def eliminate_team(league_id: str, season: int, team: str, authorization: Optional[str] = Header(None)):
    """Mark an NHL team eliminated (drives surviving-players playoff scoring). Test/cron."""
    sb = _sb()
    sb.table("fantasy_eliminated_teams").upsert([{"season_year": season, "team": team.upper()}], on_conflict="season_year,team").execute()
    return {"eliminated": team.upper()}


@router.post("/fantasy/leagues/{league_id}/start-playoffs")
def start_playoffs(league_id: str, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    if league["commissioner_id"] != uid:
        raise HTTPException(status_code=403, detail="Only the commissioner can start playoffs")
    if league["status"] not in ("active", "playoffs"):
        raise HTTPException(status_code=400, detail="Finish the regular season first")

    order = _standings_order(sb, league_id)
    size = 4 if len(order) >= 4 else 2
    seeds = order[:size]
    pw = REG_SEASON_WEEKS + 1
    pairs = [(seeds[0], seeds[3]), (seeds[1], seeds[2])] if size == 4 else [(seeds[0], seeds[1])]
    rows = [{"league_id": league_id, "week": pw, "member_a": a, "member_b": b, "is_ghost": False, "is_playoff": True} for a, b in pairs]
    sb.table("fantasy_matchups").insert(rows).execute()
    sb.table("fantasy_leagues").update({"status": "playoffs"}).eq("id", league_id).execute()
    return {"status": "playoffs", "round_week": pw, "seeds": size}


@router.post("/fantasy/leagues/{league_id}/advance-playoffs")
def advance_playoffs(league_id: str, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _require_league(sb, league_id)
    if league["commissioner_id"] != uid:
        raise HTTPException(status_code=403, detail="Only the commissioner can advance playoffs")
    pmatches = sb.table("fantasy_matchups").select("*").eq("league_id", league_id).eq("is_playoff", True).order("week").execute().data
    if not pmatches:
        raise HTTPException(status_code=400, detail="Playoffs haven't started")
    last_week = max(m["week"] for m in pmatches)
    results = {(r["member_a"]): r for r in sb.table("fantasy_weekly_results").select("*").eq("league_id", league_id).eq("week", last_week).eq("graded", True).execute().data}
    round_matches = [m for m in pmatches if m["week"] == last_week]
    if any(m["member_a"] not in results for m in round_matches):
        raise HTTPException(status_code=400, detail="Score this playoff round first")

    winners = [results[m["member_a"]]["winner_member_id"] or m["member_a"] for m in round_matches]
    if len(winners) <= 1:
        sb.table("fantasy_leagues").update({"status": "complete"}).eq("id", league_id).execute()
        return {"status": "complete", "champion_member_id": winners[0] if winners else None}

    nw = last_week + 1
    pairs = [(winners[i], winners[i + 1]) for i in range(0, len(winners) - 1, 2)]
    rows = [{"league_id": league_id, "week": nw, "member_a": a, "member_b": b, "is_ghost": False, "is_playoff": True} for a, b in pairs]
    sb.table("fantasy_matchups").insert(rows).execute()
    return {"status": "playoffs", "round_week": nw, "matchups": len(rows)}


# ---------------------------------------------------------------------------
# G5c: Global league (open, duplicate players, cumulative leaderboard)
# ---------------------------------------------------------------------------

def _get_or_create_global(sb, season: int, creator_uid: str) -> dict:
    found = sb.table("fantasy_leagues").select("*").eq("league_type", "global").eq("season_year", season).execute().data
    if found:
        return found[0]
    return sb.table("fantasy_leagues").insert([{
        "name": "HockeyQuant Global", "commissioner_id": creator_uid, "league_type": "global",
        "status": "active", "max_members": 100000, "unique_players": False,
        "trade_deadline_enabled": False, "invite_code": f"GLOBAL{season}", "season_year": season,
    }]).data[0]


@router.get("/fantasy/global")
def global_league(authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    season = current_season_year()
    league = _get_or_create_global(sb, season, uid)
    me = _member_for_user(sb, league["id"], uid)
    roster = []
    roster_cost = 0
    if me:
        slots = sb.table("fantasy_roster_slots").select("slot,slot_type,player_id").eq("member_id", me["id"]).execute().data
        pids = [s["player_id"] for s in slots if s["player_id"]]
        pmap = {}
        if pids:
            for p in sb.table("fantasy_players").select("id,full_name,team,roster_pos,sweater,cost").in_("id", pids).execute().data:
                pmap[p["id"]] = p
        order = [s for s, _ in ROSTER_SLOTS]
        roster = sorted([{"slot": s["slot"], "slot_type": s["slot_type"], "player": pmap.get(s["player_id"]) if s["player_id"] else None} for s in slots],
                        key=lambda r: order.index(r["slot"]) if r["slot"] in order else 99)
        roster_cost = sum((pmap[s["player_id"]].get("cost") or 0) for s in slots if s["player_id"] and s["player_id"] in pmap)
    return {"league": _league_summary(sb, league, uid), "joined": me is not None, "my_roster": roster,
            "cap_space": _user_cap_space(sb, uid), "roster_cost": roster_cost,
            "cap_max": season_cap_max(season)}


@router.post("/fantasy/global/join")
def global_join(req: JoinLeagueRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _get_or_create_global(sb, current_season_year(), uid)
    if _member_for_user(sb, league["id"], uid):
        return _league_summary(sb, league, uid)
    member = sb.table("fantasy_members").insert([{"league_id": league["id"], "user_id": uid, "team_name": req.team_name}]).data[0]
    sb.table("fantasy_roster_slots").insert([{
        "league_id": league["id"], "member_id": member["id"], "slot": s, "slot_type": st,
    } for s, st in ROSTER_SLOTS]).execute()
    return _league_summary(sb, league, uid)


class SetSlotRequest(BaseModel):
    slot: str
    player_id: str


@router.post("/fantasy/global/roster")
def global_set_slot(req: SetSlotRequest, authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    league = _get_or_create_global(sb, current_season_year(), uid)
    me = _member_for_user(sb, league["id"], uid)
    if not me:
        raise HTTPException(status_code=403, detail="Join the global league first")
    slot_type = next((st for s, st in ROSTER_SLOTS if s == req.slot), None)
    if not slot_type:
        raise HTTPException(status_code=400, detail="Invalid slot")
    player = sb.table("fantasy_players").select("id,roster_pos,cost").eq("id", req.player_id).execute().data
    if not player or player[0]["roster_pos"] != slot_type:
        raise HTTPException(status_code=400, detail=f"That player isn't an eligible {slot_type}")

    # Salary cap: the roster total (with this player swapped into the slot) must fit your Cap Space.
    new_cost = player[0].get("cost") or 0
    slots = sb.table("fantasy_roster_slots").select("slot,player_id").eq("member_id", me["id"]).execute().data
    other_pids = [s["player_id"] for s in slots if s["player_id"] and s["slot"] != req.slot]
    other_total = 0
    if other_pids:
        for p in sb.table("fantasy_players").select("cost").in_("id", other_pids).execute().data:
            other_total += p.get("cost") or 0
    cap = _user_cap_space(sb, uid)
    new_total = other_total + new_cost
    if new_total > cap:
        raise HTTPException(status_code=400,
                            detail=f"Over the cap — that roster needs {new_total} Cap Space, you have {cap}. Win more picks to earn Cap Space.")

    sb.table("fantasy_roster_slots").update({"player_id": req.player_id}).eq("member_id", me["id"]).eq("slot", req.slot).execute()
    return {"slot": req.slot, "player_id": req.player_id, "roster_cost": new_total, "cap_space": cap}


@router.get("/fantasy/global/leaderboard")
def global_leaderboard(authorization: Optional[str] = Header(None)):
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    season = current_season_year()
    league = _get_or_create_global(sb, season, uid)
    members = sb.table("fantasy_members").select("id,user_id,team_name").eq("league_id", league["id"]).execute().data
    if not members:
        return {"leaderboard": []}
    names = {p["id"]: p.get("username") for p in sb.table("profiles").select("id,username").in_("id", [m["user_id"] for m in members]).execute().data}
    slots = sb.table("fantasy_roster_slots").select("member_id,slot,player_id").eq("league_id", league["id"]).execute().data

    skater_ids = list({s["player_id"] for s in slots if s["player_id"] and not s["slot"].startswith("G_")})
    starter_ids = list({s["player_id"] for s in slots if s["player_id"] and s["slot"] == "G_START"})
    goals_by_pid: dict = defaultdict(int)
    if skater_ids:
        for r in sb.table("fantasy_weekly_player_goals").select("player_id,goals").eq("season_year", season).in_("player_id", skater_ids).execute().data:
            goals_by_pid[r["player_id"]] += r["goals"]
    gsax_by_pid: dict = defaultdict(float)
    if starter_ids:
        for r in sb.table("fantasy_weekly_goalie_stats").select("player_id,gsax").eq("season_year", season).in_("player_id", starter_ids).execute().data:
            gsax_by_pid[r["player_id"]] += r["gsax"]

    by_member = defaultdict(list)
    for s in slots:
        by_member[s["member_id"]].append(s)
    board = []
    for m in members:
        ms = by_member.get(m["id"], [])
        goals = sum(goals_by_pid.get(s["player_id"], 0) for s in ms if s["player_id"] and not s["slot"].startswith("G_"))
        gsax = sum(gsax_by_pid.get(s["player_id"], 0.0) for s in ms if s["slot"] == "G_START" and s["player_id"])
        board.append({"member_id": m["id"], "team_name": m["team_name"], "username": names.get(m["user_id"]),
                      "is_me": m["user_id"] == uid, "goals": goals, "points": round(goals + gsax, 1)})
    board.sort(key=lambda x: -x["points"])
    return {"leaderboard": board}


# ---------------------------------------------------------------------------
# Stanley Cup ladder — weekly head-to-head in the global league (phase 1c)
# ---------------------------------------------------------------------------

_CUP_WIN = 25      # Cups for a weekly win
_CUP_LOSS = 15     # Cups lost on a weekly loss (floored at 0)
_CUP_TIE = 5       # Cups for a tie


def _global_week_scores(sb, league_id: str, season: int, week: int) -> dict:
    """Each member's score for `week`: rostered skater goals + starter GSAX."""
    slots = sb.table("fantasy_roster_slots").select("member_id,slot,player_id").eq("league_id", league_id).execute().data
    skater_ids = list({s["player_id"] for s in slots if s["player_id"] and not s["slot"].startswith("G_")})
    starter_ids = list({s["player_id"] for s in slots if s["player_id"] and s["slot"] == "G_START"})
    goals = defaultdict(int)
    if skater_ids:
        for r in sb.table("fantasy_weekly_player_goals").select("player_id,goals").eq("season_year", season).eq("week", week).in_("player_id", skater_ids).execute().data:
            goals[r["player_id"]] += r["goals"]
    gsax = defaultdict(float)
    if starter_ids:
        for r in sb.table("fantasy_weekly_goalie_stats").select("player_id,gsax").eq("season_year", season).eq("week", week).in_("player_id", starter_ids).execute().data:
            gsax[r["player_id"]] += r["gsax"]
    by_member = defaultdict(list)
    for s in slots:
        by_member[s["member_id"]].append(s)
    out = {}
    for mid, ms in by_member.items():
        g = sum(goals.get(s["player_id"], 0) for s in ms if s["player_id"] and not s["slot"].startswith("G_"))
        gx = sum(gsax.get(s["player_id"], 0.0) for s in ms if s["slot"] == "G_START" and s["player_id"])
        out[mid] = round(g + gx, 1)
    return out


def score_cup_week(sb, week: int, season: Optional[int] = None, simulate: bool = False) -> dict:
    """Matchmake global-league managers by Cup count, play a weekly head-to-head, and
    apply Cup deltas (win +25 / loss -15 floored at 0 / tie +5). Idempotent per week.
    `simulate` fabricates scores (offseason testing, when weekly stats are empty)."""
    season = season or current_season_year()
    league = _get_or_create_global(sb, season, None)
    members = sb.table("fantasy_members").select("id,user_id,team_name").eq("league_id", league["id"]).execute().data
    if not members:
        return {"matches": 0, "reason": "no members"}
    if sb.table("cup_matches").select("id").eq("season_year", season).eq("week", week).limit(1).execute().data:
        return {"matches": 0, "reason": "already scored"}

    cups = {}
    for r in sb.table("user_stats").select("user_id,stanley_cups").in_("user_id", [m["user_id"] for m in members]).execute().data:
        cups[r["user_id"]] = r.get("stanley_cups") or 0

    scores = _global_week_scores(sb, league["id"], season, week)
    if simulate:
        scores = {m["id"]: round(random.uniform(0, 12), 1) for m in members}

    # Matchmake: sort by Cup count, pair adjacent; odd one out plays the field average.
    ordered = sorted(members, key=lambda m: (-cups.get(m["user_id"], 0), m["team_name"] or ""))
    rows, deltas = [], defaultdict(int)   # deltas: user_id -> total Cup change this week
    i = 0
    while i < len(ordered):
        a = ordered[i]
        b = ordered[i + 1] if i + 1 < len(ordered) else None
        sa = scores.get(a["id"], 0.0)
        if b is None:
            ghost = round(sum(scores.values()) / max(1, len(scores)), 1)
            da = _CUP_WIN if sa >= ghost else -_CUP_LOSS
            rows.append({"season_year": season, "week": week, "member_a": a["id"], "member_b": None,
                         "score_a": sa, "score_b": ghost, "cups_a": da, "cups_b": 0,
                         "winner_member_id": a["id"] if sa >= ghost else None, "is_ghost": True, "graded": True})
            deltas[a["user_id"]] += da
            i += 1
        else:
            sbv = scores.get(b["id"], 0.0)
            if sa > sbv:   da, db, w = _CUP_WIN, -_CUP_LOSS, a["id"]
            elif sbv > sa: da, db, w = -_CUP_LOSS, _CUP_WIN, b["id"]
            else:          da, db, w = _CUP_TIE, _CUP_TIE, None
            rows.append({"season_year": season, "week": week, "member_a": a["id"], "member_b": b["id"],
                         "score_a": sa, "score_b": sbv, "cups_a": da, "cups_b": db,
                         "winner_member_id": w, "is_ghost": False, "graded": True})
            deltas[a["user_id"]] += da
            deltas[b["user_id"]] += db
            i += 2

    sb.table("cup_matches").upsert(rows, on_conflict="season_year,week,member_a").execute()
    for uid, d in deltas.items():
        sb.table("user_stats").upsert({"user_id": uid, "stanley_cups": max(0, cups.get(uid, 0) + d)},
                                      on_conflict="user_id").execute()
    return {"matches": len(rows), "members": len(members), "season": season, "week": week}


def _next_cup_week(sb, season: int) -> int:
    """The next un-scored Cup week for the season (1 if none scored yet)."""
    weeks = [r["week"] for r in sb.table("cup_matches").select("week").eq("season_year", season).execute().data]
    return (max(weeks) + 1) if weeks else 1


@router.post("/fantasy/cup/score-week")
def cup_score_week(week: Optional[int] = None, simulate: bool = False):
    """Cron/admin: run the weekly global-league Cup matches. With no `week`, scores the
    next un-scored week of the current season (the weekly cron's normal path), so each
    weekly run advances the ladder by exactly one matchup. Idempotent per week."""
    sb = _sb()
    season = current_season_year()
    wk = week if week is not None else _next_cup_week(sb, season)
    return score_cup_week(sb, wk, season=season, simulate=simulate)


@router.get("/fantasy/cup/my-matchup")
def cup_my_matchup(authorization: Optional[str] = Header(None)):
    """The signed-in manager's most recent weekly Cup head-to-head (for the matchup card):
    you vs your opponent, the week's scores, and the Cups won/lost. Returns the latest
    graded `cup_matches` row involving you, plus your current Cup total and Arena."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    season = current_season_year()
    league = _get_or_create_global(sb, season, uid)
    me = _member_for_user(sb, league["id"], uid)
    cups = _user_cups(sb, uid)
    if not me:
        return {"joined": False, "stanley_cups": cups, "match": None}

    rows = sb.table("cup_matches").select(
        "week,member_a,member_b,score_a,score_b,cups_a,cups_b,winner_member_id,is_ghost"
    ).eq("season_year", season).or_(
        f"member_a.eq.{me['id']},member_b.eq.{me['id']}"
    ).order("week", desc=True).limit(1).execute().data
    if not rows:
        return {"joined": True, "stanley_cups": cups, "match": None}

    m = rows[0]
    i_am_a = m["member_a"] == me["id"]
    opp_id = m["member_b"] if i_am_a else m["member_a"]
    my_score = m["score_a"] if i_am_a else m["score_b"]
    opp_score = m["score_b"] if i_am_a else m["score_a"]
    my_delta = m["cups_a"] if i_am_a else m["cups_b"]

    # Opponent name (a ghost match is played against the field average).
    member_ids = [x for x in (m["member_a"], m["member_b"]) if x]
    mmap = {x["id"]: x for x in sb.table("fantasy_members").select(
        "id,user_id,team_name").in_("id", member_ids).execute().data}
    names = {p["id"]: p.get("username") for p in sb.table("profiles").select(
        "id,username").in_("id", [x["user_id"] for x in mmap.values()]).execute().data} if mmap else {}
    my_team = mmap.get(me["id"], {}).get("team_name") or "Your Team"
    if m["is_ghost"] or not opp_id:
        opp_team, opp_user = "Field Average", None
    else:
        opp_team = mmap.get(opp_id, {}).get("team_name") or "Opponent"
        opp_user = names.get(mmap.get(opp_id, {}).get("user_id"))

    # Result derived from the week scores (matches the scoring engine exactly).
    if m["is_ghost"]:
        result = "win" if my_score >= opp_score else "loss"
    elif my_score > opp_score:
        result = "win"
    elif my_score < opp_score:
        result = "loss"
    else:
        result = "tie"

    return {
        "joined": True,
        "stanley_cups": cups,
        "match": {
            "week": m["week"],
            "my_team": my_team,
            "my_username": names.get(me["user_id"]),
            "opponent_team": opp_team,
            "opponent_username": opp_user,
            "my_score": my_score,
            "opponent_score": opp_score,
            "cup_delta": my_delta,
            "result": result,
            "is_ghost": m["is_ghost"],
        },
    }


@router.get("/fantasy/leagues/{league_id}/rosters")
def all_rosters(league_id: str, authorization: Optional[str] = Header(None)):
    """Every manager's roster (for the trade UI). Members only."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    _require_league(sb, league_id)
    members = sb.table("fantasy_members").select("id,user_id,team_name").eq("league_id", league_id).execute().data
    if not any(m["user_id"] == uid for m in members):
        raise HTTPException(status_code=403, detail="You are not in this league")
    names = {p["id"]: p.get("username") for p in sb.table("profiles").select("id,username").in_("id", [m["user_id"] for m in members]).execute().data}
    slots = sb.table("fantasy_roster_slots").select("member_id,slot,slot_type,player_id").eq("league_id", league_id).execute().data
    pids = [s["player_id"] for s in slots if s["player_id"]]
    pmap = {}
    if pids:
        for p in sb.table("fantasy_players").select("id,full_name,team,roster_pos,sweater").in_("id", list(set(pids))).execute().data:
            pmap[p["id"]] = p
    order = [s for s, _ in ROSTER_SLOTS]
    out = []
    for m in members:
        ms = [s for s in slots if s["member_id"] == m["id"]]
        roster = sorted([{"slot": s["slot"], "slot_type": s["slot_type"], "player": pmap.get(s["player_id"]) if s["player_id"] else None} for s in ms],
                        key=lambda r: order.index(r["slot"]) if r["slot"] in order else 99)
        out.append({"id": m["id"], "team_name": m["team_name"], "username": names.get(m["user_id"]),
                    "is_me": m["user_id"] == uid, "roster": roster})
    return {"rosters": out}


# ---------------------------------------------------------------------------
# Push device tokens + async-draft auto-pick tick
# ---------------------------------------------------------------------------

class DeviceTokenRequest(BaseModel):
    token: str
    platform: str = "ios"


@router.post("/me/device-token")
def register_device_token(req: DeviceTokenRequest, authorization: Optional[str] = Header(None)):
    """Register/refresh this device's APNs token for the signed-in user."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    sb.table("device_tokens").upsert(
        [{"user_id": uid, "token": req.token, "platform": req.platform, "updated_at": _now()}],
        on_conflict="token",
    ).execute()
    return {"ok": True}


@router.post("/fantasy/drafts/tick")
def drafts_tick():
    """Cron: auto-pick for any in-progress draft whose current pick clock expired,
    then advance (which notifies + re-arms the clock for the next manager)."""
    sb = _sb()
    now_iso = datetime.now(timezone.utc).isoformat()
    states = sb.table("fantasy_draft_state").select("league_id,status,current_member_id,required_slot_type,pick_deadline").eq("status", "in_progress").execute().data
    acted = 0
    for st in states:
        dl = st.get("pick_deadline")
        if not (dl and st.get("current_member_id") and dl < now_iso):
            continue
        league = _require_league(sb, st["league_id"])
        pool = _eligible_pool(sb, league, st["required_slot_type"])
        if pool:
            _assign_pick(sb, league, st["current_member_id"], random.choice(pool)["id"], st["required_slot_type"])
            _advance_draft(sb, league)
            acted += 1
    return {"auto_picked": acted}
