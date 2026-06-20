"""HockeyQuant — My Franchise (card-collection mode).

A personal, single-player card game: buy player CARDS from a daily-rotating shop with
Coins, build a dream-team lineup, and play a nightly challenge vs a real NHL team. One
franchise per account. Card rarity/value is derived from `fantasy_players.cost`.
"""

import random
from datetime import date, datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel

from services.supabase_client import get_supabase
from routers.fantasy import get_user_id_from_token, current_season_year, ROSTER_SLOTS

router = APIRouter()


def _sb():
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    return sb


def _today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


# --- Card rarity + economy -------------------------------------------------
# Rarity is derived from the player's cap value (production). McDavid ≈ Legend.
RARITY_ORDER = ["common", "uncommon", "rare", "epic", "legend"]
RARITY_PRICE = {"common": 200, "uncommon": 600, "rare": 1500, "epic": 4000, "legend": 12000}
STARTING_COINS = 5000
DAILY_REWARD = 500
CHALLENGE_WIN_COINS = 750


def _rarity(cost: Optional[int]) -> str:
    c = cost or 0
    if c >= 12_000_000: return "legend"
    if c >= 8_000_000:  return "epic"
    if c >= 4_000_000:  return "rare"
    if c >= 1_500_000:  return "uncommon"
    return "common"


def _card_player_fields() -> str:
    return "id,full_name,team,roster_pos,is_goalie,sweater,headshot,cost,is_prospect"


def _player_card(p: dict) -> dict:
    """Serialize a fantasy_players row as a card (with derived rarity + shop price)."""
    rarity = _rarity(p.get("cost"))
    return {
        "player_id": p["id"], "full_name": p.get("full_name"), "team": p.get("team"),
        "roster_pos": p.get("roster_pos"), "is_goalie": bool(p.get("is_goalie")),
        "sweater": p.get("sweater"), "headshot": p.get("headshot"), "cost": p.get("cost") or 0,
        "rarity": rarity, "price": RARITY_PRICE[rarity],
    }


# --- Franchise (wallet + collection) --------------------------------------

def _grant_starter_pack(sb, uid: str) -> None:
    """A balanced low-rarity starter squad so a new manager can field a lineup at once:
    two affordable players per skater position + two goalies."""
    rows = []
    for pos in ("LW", "RW", "C", "LHD", "RHD", "G"):
        pool = sb.table("fantasy_players").select("id,cost").eq("active", "true") \
            .eq("is_prospect", "false").eq("roster_pos", pos) \
            .gte("cost", 800_000).lte("cost", 3_000_000).limit(60).execute().data
        picks = random.sample(pool, min(2, len(pool))) if pool else []
        for p in picks:
            rows.append({"user_id": uid, "player_id": p["id"], "rarity": _rarity(p.get("cost")),
                         "acquired_via": "starter"})
    if rows:
        sb.table("franchise_cards").insert(rows).execute()


def _ensure_franchise(sb, uid: str) -> dict:
    """Get-or-create the user's franchise; grant the starter pack + a daily Coin reward."""
    rows = sb.table("franchises").select("*").eq("user_id", uid).execute().data
    if not rows:
        fr = sb.table("franchises").insert([{
            "user_id": uid, "coins": STARTING_COINS, "season_year": current_season_year(),
            "last_daily_reward": _today(),
        }]).data[0]
        _grant_starter_pack(sb, uid)
        return fr
    fr = rows[0]
    if (fr.get("last_daily_reward") or "") != _today():     # once-per-day login bonus
        fr = sb.table("franchises").update({"coins": (fr.get("coins") or 0) + DAILY_REWARD,
                                            "last_daily_reward": _today()}) \
            .eq("user_id", uid).execute().data[0]
    return fr


@router.get("/franchise")
def get_franchise(authorization: Optional[str] = Header(None)):
    """Wallet (Coins), collection summary, lineup, and today's challenge status."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    fr = _ensure_franchise(sb, uid)

    cards = sb.table("franchise_cards").select("rarity").eq("user_id", uid).execute().data
    by_rarity = {r: 0 for r in RARITY_ORDER}
    for c in cards:
        by_rarity[c.get("rarity", "common")] = by_rarity.get(c.get("rarity", "common"), 0) + 1

    lineup = sb.table("franchise_lineup").select("slot,card_id").eq("user_id", uid).execute().data
    lineup_filled = sum(1 for s in lineup if s.get("card_id"))

    today = sb.table("franchise_challenges").select("opponent_team,won,graded,my_score,opp_score") \
        .eq("user_id", uid).eq("game_date", _today()).execute().data

    return {
        "coins": fr.get("coins") or 0,
        "season_year": fr.get("season_year"),
        "collection_count": len(cards),
        "by_rarity": by_rarity,
        "lineup_filled": lineup_filled,
        "lineup_slots": len(ROSTER_SLOTS),
        "today_challenge": today[0] if today else None,
        "daily_reward": DAILY_REWARD,
    }


@router.get("/franchise/collection")
def get_collection(authorization: Optional[str] = Header(None)):
    """Every card the manager owns, with player info + rarity, best first."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    _ensure_franchise(sb, uid)
    cards = sb.table("franchise_cards").select("id,player_id,rarity,acquired_via") \
        .eq("user_id", uid).execute().data
    if not cards:
        return {"cards": []}
    pids = list({c["player_id"] for c in cards})
    pmap = {p["id"]: p for p in sb.table("fantasy_players").select(_card_player_fields())
            .in_("id", pids).execute().data}
    out = []
    for c in cards:
        p = pmap.get(c["player_id"])
        if not p:
            continue
        d = _player_card(p)
        d.update({"card_id": c["id"], "rarity": c["rarity"], "acquired_via": c["acquired_via"]})
        out.append(d)
    out.sort(key=lambda x: (-RARITY_ORDER.index(x["rarity"]), -(x["cost"] or 0)))
    return {"cards": out}


# --- Rotating shop ---------------------------------------------------------
# A daily-rotating set of featured cards (same for everyone, cached per date). The
# composition leans common but always features a high-rarity headliner or two.
SHOP_PLAN = ["legend", "epic", "rare", "uncommon", "common", "common"]


def _generate_shop(sb) -> list:
    players = sb.table("fantasy_players").select("id,cost").eq("active", "true").eq("is_prospect", "false").limit(2000).execute().data
    buckets: dict = {r: [] for r in RARITY_ORDER}
    for p in players:
        buckets[_rarity(p.get("cost"))].append(p["id"])
    items, used = [], set()
    for want in SHOP_PLAN:
        rarity, pool = want, [pid for pid in buckets.get(want, []) if pid not in used]
        if not pool:                                   # fall back to the next tier down with stock
            for alt in reversed(RARITY_ORDER):
                alt_pool = [pid for pid in buckets.get(alt, []) if pid not in used]
                if alt_pool:
                    rarity, pool = alt, alt_pool
                    break
        if not pool:
            continue
        pid = random.choice(pool); used.add(pid)
        items.append({"player_id": pid, "rarity": rarity, "price": RARITY_PRICE[rarity]})
    return items


def _ensure_shop(sb, day: str) -> list:
    rows = sb.table("shop_rotation").select("items").eq("rotation_date", day).execute().data
    if rows:
        return rows[0]["items"] or []
    items = _generate_shop(sb)
    sb.table("shop_rotation").upsert([{"rotation_date": day, "items": items}], on_conflict="rotation_date").execute()
    return items


@router.get("/franchise/shop")
def get_shop(authorization: Optional[str] = Header(None)):
    """Today's rotating featured cards + your Coin balance."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    fr = _ensure_franchise(sb, uid)
    items = _ensure_shop(sb, _today())
    pmap = {p["id"]: p for p in sb.table("fantasy_players").select(_card_player_fields())
            .in_("id", [it["player_id"] for it in items]).execute().data}
    cards = []
    for it in items:
        p = pmap.get(it["player_id"])
        if not p:
            continue
        d = _player_card(p)
        d["rarity"], d["price"] = it["rarity"], it["price"]
        cards.append(d)
    return {"cards": cards, "coins": fr.get("coins") or 0, "rotation_date": _today()}


class BuyRequest(BaseModel):
    player_id: str


@router.post("/franchise/shop/buy")
def buy_card(req: BuyRequest, authorization: Optional[str] = Header(None)):
    """Buy a card from today's shop with Coins (duplicates allowed)."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    items = _ensure_shop(sb, _today())
    it = next((x for x in items if x["player_id"] == req.player_id), None)
    if not it:
        raise HTTPException(status_code=400, detail="That card isn't in today's shop")
    fr = _ensure_franchise(sb, uid)
    coins, price = fr.get("coins") or 0, it["price"]
    if coins < price:
        raise HTTPException(status_code=400, detail=f"Not enough Coins — that card costs {price}, you have {coins}.")
    sb.table("franchises").update({"coins": coins - price}).eq("user_id", uid).execute()
    sb.table("franchise_cards").insert([{
        "user_id": uid, "player_id": req.player_id, "rarity": it["rarity"], "acquired_via": "shop",
    }]).execute()
    return {"coins": coins - price, "bought": req.player_id}


# --- Dream-team lineup -----------------------------------------------------

def _slot_type(slot: str) -> Optional[str]:
    return next((st for s, st in ROSTER_SLOTS if s == slot), None)


@router.get("/franchise/lineup")
def get_lineup(authorization: Optional[str] = Header(None)):
    """The 12-slot dream team (each slot's assigned card, or empty) + the team rating."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    _ensure_franchise(sb, uid)
    assigned = {r["slot"]: r["card_id"] for r in
                sb.table("franchise_lineup").select("slot,card_id").eq("user_id", uid).execute().data}
    card_ids = [c for c in assigned.values() if c]
    cardmap: dict = {}
    if card_ids:
        cards = sb.table("franchise_cards").select("id,player_id,rarity").eq("user_id", uid).in_("id", card_ids).execute().data
        pmap = {p["id"]: p for p in sb.table("fantasy_players").select(_card_player_fields())
                .in_("id", [c["player_id"] for c in cards]).execute().data}
        for c in cards:
            p = pmap.get(c["player_id"])
            if p:
                d = _player_card(p); d["card_id"], d["rarity"] = c["id"], c["rarity"]
                cardmap[c["id"]] = d
    lineup, rating = [], 0
    for slot, st in ROSTER_SLOTS:
        card = cardmap.get(assigned.get(slot)) if assigned.get(slot) else None
        if card:
            rating += card["cost"] or 0
        lineup.append({"slot": slot, "slot_type": st, "card": card})
    return {"lineup": lineup, "rating": rating}


class LineupRequest(BaseModel):
    slot: str
    card_id: Optional[str] = None        # null clears the slot


@router.post("/franchise/lineup")
def set_lineup(req: LineupRequest, authorization: Optional[str] = Header(None)):
    """Assign an owned card to a lineup slot (its position must match), or clear it."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    st = _slot_type(req.slot)
    if not st:
        raise HTTPException(status_code=400, detail="Invalid slot")
    if req.card_id:
        owned = sb.table("franchise_cards").select("id,player_id").eq("id", req.card_id).eq("user_id", uid).execute().data
        if not owned:
            raise HTTPException(status_code=400, detail="You don't own that card")
        pos = sb.table("fantasy_players").select("roster_pos").eq("id", owned[0]["player_id"]).execute().data
        if not pos or pos[0]["roster_pos"] != st:
            raise HTTPException(status_code=400, detail=f"That card isn't a {st}")
        # A card can only sit in one slot — pull it from any other slot first.
        sb.table("franchise_lineup").update({"card_id": None}).eq("user_id", uid).eq("card_id", req.card_id).execute()
    sb.table("franchise_lineup").upsert([{"user_id": uid, "slot": req.slot, "card_id": req.card_id}],
                                        on_conflict="user_id,slot").execute()
    return {"ok": True}
