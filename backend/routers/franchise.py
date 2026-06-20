"""HockeyQuant — My Franchise (card-collection mode).

A personal, single-player card game: buy player CARDS from a daily-rotating shop with
Coins, build a dream-team lineup, and play a nightly challenge vs a real NHL team. One
franchise per account. Card rarity/value is derived from `fantasy_players.cost`.
"""

import random
from datetime import date, datetime, timezone, timedelta
from typing import Optional

import requests
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field

from services.supabase_client import get_supabase
from services.results_fetcher import fetch_game_results
from routers.fantasy import get_user_id_from_token, current_season_year, ROSTER_SLOTS

NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}

router = APIRouter()


def _sb():
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    return sb


def _today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _clear_card_from_lineup(sb, uid: str, card_id: str) -> None:
    sb.table("franchise_lineup").update({"card_id": None}).eq("user_id", uid).eq("card_id", card_id).execute()


def _usernames(sb, uids: list) -> dict:
    uids = [u for u in set(uids) if u]
    if not uids:
        return {}
    return {p["id"]: p.get("username") for p in sb.table("profiles").select("id,username").in_("id", uids).execute().data}


# --- Card rarity + economy -------------------------------------------------
# Rarity is derived from the player's cap value (production). McDavid ≈ Legend.
RARITY_ORDER = ["common", "uncommon", "rare", "epic", "legend"]
RARITY_PRICE = {"common": 200, "uncommon": 600, "rare": 1500, "epic": 4000, "legend": 12000}
STARTING_COINS = 5000
DAILY_REWARD = 500
CARD_BUY_XP = 10              # account XP per card collected
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


def _add_account_xp(sb, uid: str, amount: int) -> None:
    """Credit account-wide XP (user_stats.total_xp) — the GM-tier track, fed by the
    franchise. Update if the row exists, else best-effort insert."""
    if not amount:
        return
    rows = sb.table("user_stats").select("total_xp").eq("user_id", uid).execute().data
    if rows:
        sb.table("user_stats").update({"total_xp": (rows[0].get("total_xp") or 0) + amount}).eq("user_id", uid).execute()
    else:
        try:
            sb.table("user_stats").insert([{"user_id": uid, "total_xp": amount}]).execute()
        except Exception:
            pass


def _account_xp(sb, uid: str) -> int:
    rows = sb.table("user_stats").select("total_xp").eq("user_id", uid).execute().data
    return (rows[0].get("total_xp") if rows else 0) or 0


def _check_franchise_badges(sb, uid: str) -> None:
    """Award any newly-earned card-collection badges (idempotent)."""
    earned = {r["achievement_id"] for r in sb.table("user_achievements").select("achievement_id").eq("user_id", uid).execute().data}
    want = set()
    cards = sb.table("franchise_cards").select("rarity,acquired_via").eq("user_id", uid).execute().data
    if len(cards) >= 30:
        want.add("fr_collector")
    if any(c.get("rarity") == "legend" for c in cards):
        want.add("fr_legend")
    if any(c.get("acquired_via") == "rookie" for c in cards):
        want.add("fr_scout")
    lineup = sb.table("franchise_lineup").select("card_id").eq("user_id", uid).execute().data
    if sum(1 for s in lineup if s.get("card_id")) >= len(ROSTER_SLOTS):
        want.add("fr_dream_team")
    chs = sb.table("franchise_challenges").select("won").eq("user_id", uid).execute().data
    if chs:
        want.add("fr_challenger")
    if any(c.get("won") for c in chs):
        want.add("fr_upset")
    new = want - earned
    if new:
        try:
            sb.table("user_achievements").insert([{"user_id": uid, "achievement_id": b} for b in new]).execute()
        except Exception:
            pass


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
    _check_franchise_badges(sb, uid)

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
        "account_xp": _account_xp(sb, uid),
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
    _add_account_xp(sb, uid, CARD_BUY_XP)        # collecting cards builds your account
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


# --- Nightly challenge -----------------------------------------------------
# Pick a real NHL team playing that night; your dream-team skaters' real goals + a
# goalie boost settle against the opponent team's real goals. Win → Coins (+ XP).
GOALIE_BOOST = {"SO": 3, "W": 2, "T": 1, "L": 1}        # your starter goalie's result that night
CHALLENGE_WIN_COINS = 750
CHALLENGE_LOSS_COINS = 100
CHALLENGE_WIN_XP = 60
CHALLENGE_LOSS_XP = 15


def _score_games(game_date: str) -> list:
    """All games on a date (any state) from the NHL score endpoint."""
    try:
        data = requests.get(f"https://api-web.nhle.com/v1/score/{game_date}", headers=NHL_HEADERS, timeout=12).json()
    except Exception:
        return []
    out = []
    for g in data.get("games", []):
        a, h = g.get("awayTeam", {}), g.get("homeTeam", {})
        out.append({"game_id": str(g.get("id", "")), "state": g.get("gameState", ""),
                    "away_team": a.get("abbrev", ""), "home_team": h.get("abbrev", ""),
                    "away_final": a.get("score") or 0, "home_final": h.get("score") or 0})
    return out


def _lineup_snapshot(sb, uid: str) -> dict:
    """The current lineup as NHL ids: {skaters: [nhl_id], goalie: nhl_id|None}."""
    assigned = {r["slot"]: r["card_id"] for r in sb.table("franchise_lineup").select("slot,card_id").eq("user_id", uid).execute().data}
    card_ids = [c for c in assigned.values() if c]
    if not card_ids:
        return {"skaters": [], "goalie": None}
    cards = {c["id"]: c["player_id"] for c in sb.table("franchise_cards").select("id,player_id").eq("user_id", uid).in_("id", card_ids).execute().data}
    pmap = {p["id"]: p for p in sb.table("fantasy_players").select("id,nhl_id,is_goalie").in_("id", list(cards.values())).execute().data}
    skaters, goalie = [], None
    for slot, cid in assigned.items():
        if not cid:
            continue
        p = pmap.get(cards.get(cid))
        if not p:
            continue
        if slot == "G_START":
            goalie = p.get("nhl_id")
        elif not p.get("is_goalie"):
            skaters.append(p.get("nhl_id"))
    return {"skaters": [s for s in skaters if s], "goalie": goalie}


def _franchise_night_stats(game_date: str):
    """For a date, from the boxscores: {nhl_id: goals} skaters, {abbrev: goals} team finals,
    {nhl_id: result} for starting goalies (SO/W/L/T)."""
    goals_by_id: dict = {}
    team_goals: dict = {}
    goalie_result: dict = {}
    for g in fetch_game_results(game_date):       # FINAL/OFF games only
        team_goals[g["away_team"]] = g["away_final"]
        team_goals[g["home_team"]] = g["home_final"]
        try:
            box = requests.get(f"https://api-web.nhle.com/v1/gamecenter/{g['game_id']}/boxscore", headers=NHL_HEADERS, timeout=12).json()
        except Exception:
            continue
        pbs = box.get("playerByGameStats", {})
        for side, mine, theirs in (("awayTeam", g["away_final"], g["home_final"]),
                                   ("homeTeam", g["home_final"], g["away_final"])):
            stats = pbs.get(side, {})
            for grp in ("forwards", "defense"):
                for p in stats.get(grp, []):
                    pid = p.get("playerId")
                    if pid is not None:
                        goals_by_id[pid] = goals_by_id.get(pid, 0) + (p.get("goals") or 0)
            for gk in stats.get("goalies", []):
                pid = gk.get("playerId")
                if pid is None or not gk.get("starter"):
                    continue
                goalie_result[pid] = "SO" if theirs == 0 else ("W" if mine > theirs else ("L" if mine < theirs else "T"))
    return goals_by_id, team_goals, goalie_result


def _score_challenge_row(ch: dict, goals_by_id: dict, team_goals: dict, goalie_result: dict):
    lu = ch.get("lineup") or {}
    my = sum(goals_by_id.get(nid, 0) for nid in lu.get("skaters", []))
    gid = lu.get("goalie")
    if gid and gid in goalie_result:
        my += GOALIE_BOOST.get(goalie_result[gid], 0)
    opp = team_goals.get(ch["opponent_team"], 0)
    return my, opp, my > opp


def score_franchise_challenges(sb, game_date: str) -> dict:
    """Cron/admin: settle every ungraded challenge for `game_date` from real boxscores."""
    pending = sb.table("franchise_challenges").select("*").eq("game_date", game_date).eq("graded", "false").execute().data
    if not pending:
        return {"scored": 0, "date": game_date}
    goals_by_id, team_goals, goalie_result = _franchise_night_stats(game_date)
    if not team_goals:
        return {"scored": 0, "date": game_date, "reason": "no final games yet"}
    n = 0
    for ch in pending:
        my, opp, won = _score_challenge_row(ch, goals_by_id, team_goals, goalie_result)
        coins = CHALLENGE_WIN_COINS if won else CHALLENGE_LOSS_COINS
        xp = CHALLENGE_WIN_XP if won else CHALLENGE_LOSS_XP
        sb.table("franchise_challenges").update({
            "my_score": my, "opp_score": opp, "won": won,
            "coins_awarded": coins, "xp_awarded": xp, "graded": True,
        }).eq("id", ch["id"]).execute()
        fr = sb.table("franchises").select("coins").eq("user_id", ch["user_id"]).execute().data
        if fr:
            sb.table("franchises").update({"coins": (fr[0]["coins"] or 0) + coins}).eq("user_id", ch["user_id"]).execute()
        _add_account_xp(sb, ch["user_id"], xp)       # challenge XP feeds the account GM tier
        _check_franchise_badges(sb, ch["user_id"])   # may unlock Challenger / Upset Special
        n += 1
    return {"scored": n, "date": game_date}


@router.get("/franchise/challenge/options")
def challenge_options(date: Optional[str] = None, authorization: Optional[str] = Header(None)):
    """NHL teams playing on a date (default tonight) — pick one to challenge."""
    get_user_id_from_token(authorization)
    day = date or _today()
    games = _score_games(day)
    teams = sorted({t for g in games for t in (g["away_team"], g["home_team"]) if t})
    return {"date": day, "teams": teams, "games": games}


class ChallengeRequest(BaseModel):
    opponent_team: str
    game_date: Optional[str] = None


@router.post("/franchise/challenge")
def lock_challenge(req: ChallengeRequest, authorization: Optional[str] = Header(None)):
    """Lock tonight's challenge: snapshot your lineup vs a chosen NHL team."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    _ensure_franchise(sb, uid)
    day = req.game_date or _today()
    teams = {t for g in _score_games(day) for t in (g["away_team"], g["home_team"])}
    if req.opponent_team not in teams:
        raise HTTPException(status_code=400, detail="That team isn't playing that night")
    snap = _lineup_snapshot(sb, uid)
    if not snap["skaters"]:
        raise HTTPException(status_code=400, detail="Set your dream-team lineup first")
    sb.table("franchise_challenges").upsert([{
        "user_id": uid, "game_date": day, "opponent_team": req.opponent_team,
        "lineup": snap, "graded": False,
    }], on_conflict="user_id,game_date").execute()
    return {"locked": True, "opponent_team": req.opponent_team, "game_date": day}


@router.get("/franchise/challenge")
def get_challenge(authorization: Optional[str] = Header(None)):
    """This manager's most recent challenge (tonight's if locked, else the last result)."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    rows = sb.table("franchise_challenges").select("game_date,opponent_team,my_score,opp_score,won,coins_awarded,xp_awarded,graded") \
        .eq("user_id", uid).order("game_date", desc=True).limit(1).execute().data
    return {"challenge": rows[0] if rows else None, "today": _today()}


# --- Annual rookie-card draft ----------------------------------------------
# Each season you earn rookie picks (a base + a performance bonus from challenge wins —
# the "lottery"), then draft rookie cards from the real prospect class into your collection.
BASE_ROOKIE_PICKS = 3
ROOKIE_PICK_XP = 15


def _ensure_rookie_picks(sb, uid: str, season: int) -> None:
    """Allocate this season's rookie picks once: a base + a bonus for challenge wins."""
    if sb.table("rookie_picks").select("id").eq("user_id", uid).eq("season_year", season).limit(1).execute().data:
        return
    wins = len(sb.table("franchise_challenges").select("id").eq("user_id", uid).eq("won", "true").execute().data)
    total = BASE_ROOKIE_PICKS + min(3, wins // 2)
    sb.table("rookie_picks").insert([{"user_id": uid, "season_year": season, "round": i + 1} for i in range(total)]).execute()


@router.get("/franchise/rookie-draft")
def rookie_draft(authorization: Optional[str] = Header(None)):
    """Your remaining rookie picks + the available rookie board (best prospects first)."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    _ensure_franchise(sb, uid)
    season = current_season_year()
    _ensure_rookie_picks(sb, uid, season)
    picks = sb.table("rookie_picks").select("used").eq("user_id", uid).eq("season_year", season).execute().data
    remaining = len([p for p in picks if not p["used"]])
    drafted = {c["player_id"] for c in sb.table("franchise_cards").select("player_id").eq("user_id", uid).eq("acquired_via", "rookie").execute().data}
    pool = sb.table("fantasy_players").select(_card_player_fields() + ",prospect_ranking") \
        .eq("is_prospect", "true").order("prospect_ranking").limit(80).execute().data
    board = []
    for p in pool:
        if p["id"] in drafted:
            continue
        d = _player_card(p)
        d["prospect_ranking"] = p.get("prospect_ranking")
        board.append(d)
        if len(board) >= 40:
            break
    return {"picks_remaining": remaining, "picks_total": len(picks), "season_year": season, "board": board}


class RookiePickRequest(BaseModel):
    player_id: str


@router.post("/franchise/rookie-draft/pick")
def rookie_pick(req: RookiePickRequest, authorization: Optional[str] = Header(None)):
    """Spend a rookie pick to draft a rookie card into your collection."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    season = current_season_year()
    _ensure_rookie_picks(sb, uid, season)
    unused = sb.table("rookie_picks").select("id").eq("user_id", uid).eq("season_year", season).eq("used", "false").limit(1).execute().data
    if not unused:
        raise HTTPException(status_code=400, detail="No rookie picks left this season")
    prow = sb.table("fantasy_players").select("id,cost,is_prospect").eq("id", req.player_id).execute().data
    if not prow or not prow[0].get("is_prospect"):
        raise HTTPException(status_code=400, detail="That isn't a draftable rookie")
    if sb.table("franchise_cards").select("id").eq("user_id", uid).eq("player_id", req.player_id).eq("acquired_via", "rookie").execute().data:
        raise HTTPException(status_code=400, detail="You already drafted that rookie")
    sb.table("rookie_picks").update({"used": True}).eq("id", unused[0]["id"]).execute()
    sb.table("franchise_cards").insert([{
        "user_id": uid, "player_id": req.player_id, "rarity": _rarity(prow[0].get("cost")), "acquired_via": "rookie",
    }]).execute()
    _add_account_xp(sb, uid, ROOKIE_PICK_XP)
    remaining = len(sb.table("rookie_picks").select("id").eq("user_id", uid).eq("season_year", season).eq("used", "false").execute().data)
    return {"drafted": req.player_id, "picks_remaining": remaining}


# --- Card marketplace (list / browse / buy) --------------------------------

class ListRequest(BaseModel):
    card_id: str
    price: int = Field(..., ge=1)


@router.post("/franchise/market/list")
def market_list(req: ListRequest, authorization: Optional[str] = Header(None)):
    """List one of your cards on the marketplace for a Coin price."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    owned = sb.table("franchise_cards").select("id,player_id,rarity").eq("id", req.card_id).eq("user_id", uid).execute().data
    if not owned:
        raise HTTPException(status_code=400, detail="You don't own that card")
    if sb.table("card_listings").select("id").eq("card_id", req.card_id).eq("status", "open").limit(1).execute().data:
        raise HTTPException(status_code=400, detail="That card is already listed")
    c = owned[0]
    sb.table("card_listings").insert([{
        "seller_id": uid, "card_id": req.card_id, "player_id": c["player_id"],
        "rarity": c["rarity"], "price": req.price, "status": "open",
    }]).execute()
    return {"listed": req.card_id, "price": req.price}


def _listing_cards(sb, listings: list, seller_names: dict) -> list:
    pmap = {p["id"]: p for p in sb.table("fantasy_players").select(_card_player_fields())
            .in_("id", [l["player_id"] for l in listings]).execute().data} if listings else {}
    out = []
    for l in listings:
        p = pmap.get(l["player_id"])
        if not p:
            continue
        d = _player_card(p)
        d["rarity"], d["price"], d["card_id"] = l["rarity"], l["price"], l.get("card_id")
        d["listing_id"], d["seller"], d["status"] = l["id"], seller_names.get(l.get("seller_id")), l.get("status")
        out.append(d)
    return out


@router.get("/franchise/market")
def market_browse(authorization: Optional[str] = Header(None)):
    """Open listings from other managers (you can't buy your own) + your Coin balance."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    fr = _ensure_franchise(sb, uid)
    listings = sb.table("card_listings").select("id,seller_id,player_id,rarity,price,status,card_id") \
        .eq("status", "open").order("created_at", desc=True).limit(120).execute().data
    others = [l for l in listings if l["seller_id"] != uid]
    names = _usernames(sb, [l["seller_id"] for l in others])
    return {"listings": _listing_cards(sb, others, names), "coins": fr.get("coins") or 0}


@router.get("/franchise/market/mine")
def market_mine(authorization: Optional[str] = Header(None)):
    """Your own listings (open + recently resolved)."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    listings = sb.table("card_listings").select("id,seller_id,player_id,rarity,price,status,card_id") \
        .eq("seller_id", uid).order("created_at", desc=True).limit(50).execute().data
    return {"listings": _listing_cards(sb, listings, {})}


class ListingActionRequest(BaseModel):
    listing_id: str


@router.post("/franchise/market/buy")
def market_buy(req: ListingActionRequest, authorization: Optional[str] = Header(None)):
    """Buy a listed card with Coins (transfers the card + Coins, closes the listing)."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    rows = sb.table("card_listings").select("*").eq("id", req.listing_id).execute().data
    if not rows or rows[0]["status"] != "open":
        raise HTTPException(status_code=400, detail="That listing isn't available")
    L = rows[0]
    if L["seller_id"] == uid:
        raise HTTPException(status_code=400, detail="You can't buy your own listing")
    fr = _ensure_franchise(sb, uid)
    coins = fr.get("coins") or 0
    if coins < L["price"]:
        raise HTTPException(status_code=400, detail=f"Not enough Coins — that card costs {L['price']}, you have {coins}.")
    if not sb.table("franchise_cards").select("id").eq("id", L["card_id"]).eq("user_id", L["seller_id"]).execute().data:
        sb.table("card_listings").update({"status": "cancelled", "resolved_at": _now()}).eq("id", L["id"]).execute()
        raise HTTPException(status_code=400, detail="That card is no longer available")
    # Transfer the card + Coins, clear it from the seller's lineup, close the listing.
    sb.table("franchise_cards").update({"user_id": uid, "acquired_via": "trade"}).eq("id", L["card_id"]).execute()
    _clear_card_from_lineup(sb, L["seller_id"], L["card_id"])
    sb.table("franchises").update({"coins": coins - L["price"]}).eq("user_id", uid).execute()
    srows = sb.table("franchises").select("coins").eq("user_id", L["seller_id"]).execute().data
    if srows:
        sb.table("franchises").update({"coins": (srows[0]["coins"] or 0) + L["price"]}).eq("user_id", L["seller_id"]).execute()
    sb.table("card_listings").update({"status": "sold", "buyer_id": uid, "resolved_at": _now()}).eq("id", L["id"]).execute()
    return {"bought": L["card_id"], "coins": coins - L["price"]}


@router.post("/franchise/market/cancel")
def market_cancel(req: ListingActionRequest, authorization: Optional[str] = Header(None)):
    """Delist one of your open listings."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    rows = sb.table("card_listings").select("seller_id,status").eq("id", req.listing_id).execute().data
    if not rows or rows[0]["seller_id"] != uid:
        raise HTTPException(status_code=403, detail="That isn't your listing")
    if rows[0]["status"] != "open":
        raise HTTPException(status_code=400, detail="That listing is already resolved")
    sb.table("card_listings").update({"status": "cancelled", "resolved_at": _now()}).eq("id", req.listing_id).execute()
    return {"cancelled": req.listing_id}


# --- Direct card-for-card offers (propose / inbox / accept) ----------------

TRADE_XP = 5


def _cards_by_id(sb, card_ids: list) -> dict:
    """Map franchise_card id -> PlayerCard dict (with current rarity), for offer views."""
    ids = [c for c in card_ids if c]
    if not ids:
        return {}
    fc = sb.table("franchise_cards").select("id,player_id,rarity").in_("id", ids).execute().data
    pmap = {p["id"]: p for p in sb.table("fantasy_players").select(_card_player_fields())
            .in_("id", [c["player_id"] for c in fc]).execute().data} if fc else {}
    out = {}
    for c in fc:
        p = pmap.get(c["player_id"])
        if not p:
            continue
        d = _player_card(p)
        d["rarity"], d["card_id"] = c["rarity"], c["id"]
        out[c["id"]] = d
    return out


def _offer_views(sb, offers: list) -> list:
    """Serialize offers with both cards' details + usernames."""
    if not offers:
        return []
    cards = _cards_by_id(sb, [o["from_card_id"] for o in offers] + [o["to_card_id"] for o in offers])
    names = _usernames(sb, [o["from_user"] for o in offers] + [o["to_user"] for o in offers])
    out = []
    for o in offers:
        out.append({
            "offer_id": o["id"],
            "from_card": cards.get(o["from_card_id"]),
            "to_card": cards.get(o["to_card_id"]),
            "from_coins": o.get("from_coins") or 0,
            "to_coins": o.get("to_coins") or 0,
            "from_user": names.get(o["from_user"]),
            "to_user": names.get(o["to_user"]),
            "status": o.get("status"),
        })
    return out


def _void_card_trades(sb, card_ids: list, except_offer: Optional[str] = None) -> None:
    """After a card changes hands, void competing pending offers + cancel open listings on it."""
    ids = [c for c in card_ids if c]
    if not ids:
        return
    sb.table("card_listings").update({"status": "cancelled", "resolved_at": _now()}) \
        .in_("card_id", ids).eq("status", "open").execute()
    for field in ("from_card_id", "to_card_id"):
        rows = sb.table("card_offers").select("id").in_(field, ids).eq("status", "pending").execute().data
        for r in rows:
            if r["id"] != except_offer:
                sb.table("card_offers").update({"status": "void", "resolved_at": _now()}).eq("id", r["id"]).execute()


class OfferRequest(BaseModel):
    to_card_id: str                       # the card you want (someone else's)
    from_card_id: str                     # your card you're giving
    from_coins: int = Field(0, ge=0)      # Coins you add to sweeten the deal


@router.post("/franchise/offers")
def offer_propose(req: OfferRequest, authorization: Optional[str] = Header(None)):
    """Propose a card-for-card trade (optionally adding Coins) to the owner of a card."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    mine = sb.table("franchise_cards").select("id").eq("id", req.from_card_id).eq("user_id", uid).execute().data
    if not mine:
        raise HTTPException(status_code=400, detail="You don't own the card you're offering")
    theirs = sb.table("franchise_cards").select("user_id").eq("id", req.to_card_id).execute().data
    if not theirs:
        raise HTTPException(status_code=400, detail="That card no longer exists")
    to_user = theirs[0]["user_id"]
    if to_user == uid:
        raise HTTPException(status_code=400, detail="That's already your card")
    fr = _ensure_franchise(sb, uid)
    if (fr.get("coins") or 0) < req.from_coins:
        raise HTTPException(status_code=400, detail="You don't have that many Coins to offer")
    sb.table("card_offers").insert([{
        "from_user": uid, "to_user": to_user, "from_card_id": req.from_card_id,
        "to_card_id": req.to_card_id, "from_coins": req.from_coins, "to_coins": 0, "status": "pending",
    }]).execute()
    return {"proposed": req.to_card_id}


@router.get("/franchise/offers")
def offers_list(authorization: Optional[str] = Header(None)):
    """Your pending offers — incoming (decide) and outgoing (waiting) — plus your Coin balance."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    fr = _ensure_franchise(sb, uid)
    incoming = sb.table("card_offers").select("*").eq("to_user", uid).eq("status", "pending") \
        .order("created_at", desc=True).limit(50).execute().data
    outgoing = sb.table("card_offers").select("*").eq("from_user", uid).eq("status", "pending") \
        .order("created_at", desc=True).limit(50).execute().data
    return {"incoming": _offer_views(sb, incoming), "outgoing": _offer_views(sb, outgoing), "coins": fr.get("coins") or 0}


class OfferActionRequest(BaseModel):
    offer_id: str


@router.post("/franchise/offers/accept")
def offer_accept(req: OfferActionRequest, authorization: Optional[str] = Header(None)):
    """Accept an incoming offer: swap the two cards (+ any Coins) and void competing trades."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    rows = sb.table("card_offers").select("*").eq("id", req.offer_id).execute().data
    if not rows or rows[0]["status"] != "pending":
        raise HTTPException(status_code=400, detail="That offer isn't available")
    o = rows[0]
    if o["to_user"] != uid:
        raise HTTPException(status_code=403, detail="That offer isn't addressed to you")
    # Both cards must still be owned by the right people.
    if not sb.table("franchise_cards").select("id").eq("id", o["from_card_id"]).eq("user_id", o["from_user"]).execute().data \
       or not sb.table("franchise_cards").select("id").eq("id", o["to_card_id"]).eq("user_id", uid).execute().data:
        sb.table("card_offers").update({"status": "void", "resolved_at": _now()}).eq("id", o["id"]).execute()
        raise HTTPException(status_code=400, detail="One of the cards is no longer available")
    from_coins = o.get("from_coins") or 0
    fr_from = sb.table("franchises").select("coins").eq("user_id", o["from_user"]).execute().data
    if from_coins and (not fr_from or (fr_from[0]["coins"] or 0) < from_coins):
        raise HTTPException(status_code=400, detail="The other manager can no longer cover the Coins offered")
    # Swap cards, clear them from both lineups.
    sb.table("franchise_cards").update({"user_id": o["to_user"], "acquired_via": "trade"}).eq("id", o["from_card_id"]).execute()
    sb.table("franchise_cards").update({"user_id": o["from_user"], "acquired_via": "trade"}).eq("id", o["to_card_id"]).execute()
    _clear_card_from_lineup(sb, o["from_user"], o["from_card_id"])
    _clear_card_from_lineup(sb, uid, o["to_card_id"])
    # Move Coins (proposer pays the sweetener to the recipient).
    if from_coins:
        sb.table("franchises").update({"coins": (fr_from[0]["coins"] or 0) - from_coins}).eq("user_id", o["from_user"]).execute()
        fr_to = sb.table("franchises").select("coins").eq("user_id", uid).execute().data
        sb.table("franchises").update({"coins": (fr_to[0]["coins"] or 0) + from_coins}).eq("user_id", uid).execute()
    sb.table("card_offers").update({"status": "accepted", "resolved_at": _now()}).eq("id", o["id"]).execute()
    _void_card_trades(sb, [o["from_card_id"], o["to_card_id"]], except_offer=o["id"])
    _add_account_xp(sb, uid, TRADE_XP)
    _add_account_xp(sb, o["from_user"], TRADE_XP)
    return {"accepted": o["id"]}


@router.post("/franchise/offers/decline")
def offer_decline(req: OfferActionRequest, authorization: Optional[str] = Header(None)):
    """Decline an incoming offer (recipient) or cancel an outgoing one (proposer)."""
    uid = get_user_id_from_token(authorization)
    sb = _sb()
    rows = sb.table("card_offers").select("from_user,to_user,status").eq("id", req.offer_id).execute().data
    if not rows or uid not in (rows[0]["from_user"], rows[0]["to_user"]):
        raise HTTPException(status_code=403, detail="That isn't your offer")
    if rows[0]["status"] != "pending":
        raise HTTPException(status_code=400, detail="That offer is already resolved")
    new_status = "cancelled" if rows[0]["from_user"] == uid else "declined"
    sb.table("card_offers").update({"status": new_status, "resolved_at": _now()}).eq("id", req.offer_id).execute()
    return {new_status: req.offer_id}


@router.post("/franchise/challenge/score")
def challenge_score(date: Optional[str] = None):
    """Cron/admin: settle franchise challenges. With no date, settles yesterday + today
    (NHL game nights span UTC midnight). Idempotent — graded challenges are skipped."""
    sb = _sb()
    if date:
        return score_franchise_challenges(sb, date)
    today = _today()
    yest = (datetime.now(timezone.utc).date() - timedelta(days=1)).isoformat()
    return {"yesterday": score_franchise_challenges(sb, yest), "today": score_franchise_challenges(sb, today)}
