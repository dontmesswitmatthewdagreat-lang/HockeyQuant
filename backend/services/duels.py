"""Global League weekly duels: matchmaking, snake draft, scoring, ranking.

The ranked mode. Each week you're paired with another player, you alternate
picks from randomly offered pools, and whoever's roster scores more that week
takes the rating. Private leagues are untouched by any of this — they stay
season-long with friends.

Two ideas carry the design:

*Depth slots are league-wide tiers.* Rank every player at a position by value
and cut every 32, so "2C" means roughly the second-line centre of an average
team and means the same thing to both drafters.

*Scarcity buys away agency.* A better slot offers fewer choices — a 1C hands
you a star but almost no decision, while a 4C is where reading the matchups
actually wins you the week.
"""

import datetime
import random
from typing import Optional

from services.supabase_client import get_supabase

# Roster each player drafts. Even total (12 picks) so the snake is symmetric —
# an odd count would hand one player an extra turn.
ROSTER = ["C", "LW", "RW", "D", "D", "G"]

# Choices offered per depth tier. Elite slots are scarce by design.
TIER_OPTIONS = {1: 2, 2: 3, 3: 4, 4: 5}

# Tiers a slot can roll. Goalies only go two deep — a league has ~64 of them.
SKATER_TIERS = [1, 2, 3, 4]
GOALIE_TIERS = [1, 2]

TEAMS_IN_LEAGUE = 32

# Rating band for matchmaking, widened if nobody suitable is waiting.
BASE_BAND = 150
MAX_BAND = 10_000


def week_bounds(today: Optional[datetime.date] = None) -> tuple:
    """Monday→Sunday scoring week containing `today`."""
    today = today or datetime.date.today()
    start = today - datetime.timedelta(days=today.weekday())
    return start, start + datetime.timedelta(days=6)


def next_week_bounds(today: Optional[datetime.date] = None) -> tuple:
    start, _ = week_bounds(today)
    nxt = start + datetime.timedelta(days=7)
    return nxt, nxt + datetime.timedelta(days=6)


# ----------------------------------------------------------------- depth tiers

def _pool_by_slot(sb) -> dict:
    """Group active players into {(position, tier): [player, ...]}.

    Tier is a league-wide cut every 32 by cost, so tier 1 at a position is
    about one starter per team.
    """
    rows = (sb.table("fantasy_players")
            .select("nhl_id,full_name,team,position,roster_pos,cost,is_goalie,headshot")
            .eq("active", "true").limit(2000).execute().data)

    buckets: dict = {}
    for row in rows:
        if row.get("is_prospect"):
            continue
        slot = "G" if row.get("is_goalie") else _skater_slot(row.get("roster_pos"))
        if slot:
            buckets.setdefault(slot, []).append(row)

    pools: dict = {}
    for slot, players in buckets.items():
        players.sort(key=lambda p: -(p.get("cost") or 0))
        tiers = GOALIE_TIERS if slot == "G" else SKATER_TIERS
        for tier in tiers:
            lo = (tier - 1) * TEAMS_IN_LEAGUE
            hi = tier * TEAMS_IN_LEAGUE
            chunk = players[lo:hi]
            # Past the last full tier, sweep the remainder into the deepest one
            # rather than offering an empty board.
            if tier == tiers[-1]:
                chunk = players[lo:]
            if chunk:
                pools[(slot, tier)] = chunk
    return pools


def _skater_slot(roster_pos: Optional[str]) -> Optional[str]:
    if not roster_pos:
        return None
    if roster_pos in ("LHD", "RHD", "D"):
        return "D"
    if roster_pos in ("C", "LW", "RW"):
        return roster_pos
    return None


# ------------------------------------------------------------------ draft flow

def _snake_order(n_picks: int, first: str, second: str) -> list:
    """A→B→B→A→A→B… so neither player gets a run of premium rolls."""
    order, flip = [], False
    for i in range(0, n_picks, 2):
        order += [second, first] if flip else [first, second]
        flip = not flip
    return order[:n_picks]


def _slot_schedule() -> list:
    """The (slot, tier) each pick will be for, shuffled per duel."""
    schedule = []
    for slot in ROSTER:
        tiers = GOALIE_TIERS if slot == "G" else SKATER_TIERS
        schedule.append((slot, random.choice(tiers)))
    random.shuffle(schedule)
    return schedule


def create_duel(sb, week_start, week_end, user_a: str, user_b: str) -> dict:
    """Pair two users and lay out the full pick order for the week."""
    first, second = (user_a, user_b) if random.random() < 0.5 else (user_b, user_a)
    duel = sb.table("duels").insert([{
        "week_start": str(week_start), "week_end": str(week_end),
        "user_a": user_a, "user_b": user_b,
        "state": "drafting", "turn_user": first, "pick_no": 0,
    }]).data[0]

    # Each player drafts the same roster shape; tiers are rolled per player so
    # one drafter's 1C roll doesn't dictate the other's.
    order = _snake_order(len(ROSTER) * 2, first, second)
    schedules = {first: _slot_schedule(), second: _slot_schedule()}
    taken = {first: 0, second: 0}

    rows = []
    for pick_no, who in enumerate(order):
        slot, tier = schedules[who][taken[who]]
        taken[who] += 1
        rows.append({"duel_id": duel["id"], "pick_no": pick_no, "user_id": who,
                     "slot": f"{tier}{slot}" if slot != "G" else f"G{tier}",
                     "offered": []})
    sb.table("duel_picks").insert(rows)
    return duel


def offer_pool(sb, duel_id: int) -> dict:
    """The board for the pick on the clock: refresh it and hand it back.

    The pool is drawn now rather than at duel creation so it can exclude
    everyone already taken in this duel — a player can never appear on two
    boards in the same matchup.
    """
    duel = sb.table("duels").select("*").eq("id", duel_id).execute().data
    if not duel:
        raise ValueError("no such duel")
    duel = duel[0]
    if duel["state"] != "drafting":
        return {"duel": duel, "pick": None, "offered": []}

    picks = (sb.table("duel_picks").select("*")
             .eq("duel_id", duel_id).order("pick_no").limit(64).execute().data)
    current = next((p for p in picks if p["chosen_nhl_id"] is None), None)
    if current is None:
        return {"duel": duel, "pick": None, "offered": []}

    if current["offered"]:                      # already drawn; don't reroll
        return {"duel": duel, "pick": current, "offered": current["offered"]}

    slot_label = current["slot"]
    tier = int(slot_label[0]) if slot_label[0].isdigit() else int(slot_label[-1])
    slot = slot_label[1:] if slot_label[0].isdigit() else "G"

    pools = _pool_by_slot(sb)
    candidates = list(pools.get((slot, tier), []))
    already = {p["chosen_nhl_id"] for p in picks if p["chosen_nhl_id"]}
    candidates = [c for c in candidates if c["nhl_id"] not in already]
    if not candidates:
        raise ValueError(f"no players left for {slot_label}")

    n = TIER_OPTIONS.get(tier, 3)
    offered = random.sample(candidates, min(n, len(candidates)))
    payload = [{"nhl_id": c["nhl_id"], "name": c["full_name"], "team": c["team"],
                "pos": c["position"], "headshot": c.get("headshot"),
                "cost": c.get("cost")} for c in offered]

    sb.table("duel_picks").update({"offered": payload}).eq("id", current["id"]).execute()
    current["offered"] = payload
    return {"duel": duel, "pick": current, "offered": payload}


def make_pick(sb, duel_id: int, user_id: str, nhl_id: int, auto: bool = False) -> dict:
    """Record a pick. Rejects anything that isn't this user's turn or wasn't offered."""
    state = offer_pool(sb, duel_id)
    duel, pick = state["duel"], state["pick"]
    if pick is None:
        raise ValueError("draft already complete")
    if pick["user_id"] != user_id:
        raise ValueError("not your pick")
    if nhl_id not in {o["nhl_id"] for o in state["offered"]}:
        raise ValueError("player was not on your board")

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    sb.table("duel_picks").update({
        "chosen_nhl_id": nhl_id, "auto_picked": auto, "picked_at": now,
    }).eq("id", pick["id"]).execute()

    remaining = (sb.table("duel_picks").select("pick_no,user_id")
                 .eq("duel_id", duel_id).is_("chosen_nhl_id", "null")
                 .order("pick_no").limit(64).execute().data)
    nxt = next((r for r in remaining if r["pick_no"] != pick["pick_no"]), None)

    sb.table("duels").update({
        "pick_no": pick["pick_no"] + 1,
        "turn_user": nxt["user_id"] if nxt else None,
        "state": "drafting" if nxt else "live",
    }).eq("id", duel_id).execute()

    return {"picked": nhl_id, "next_user": nxt["user_id"] if nxt else None,
            "complete": nxt is None}


def autopick(sb, duel_id: int) -> dict:
    """Take the best remaining option for whoever is on the clock.

    A stalled draft would otherwise strand the opponent for the whole week, so
    the clock picks rather than forfeits.
    """
    state = offer_pool(sb, duel_id)
    if state["pick"] is None:
        return {"skipped": "draft complete"}
    best = max(state["offered"], key=lambda o: o.get("cost") or 0)
    return make_pick(sb, duel_id, state["pick"]["user_id"], best["nhl_id"], auto=True)


# ---------------------------------------------------------------- matchmaking

def match_queue(sb, week_start=None) -> dict:
    """Pair everyone waiting for a week, closest rating first.

    Sorting by rating and walking in pairs keeps matchups tight without needing
    a real bracket; the band only matters for the odd one left over.
    """
    week_start = week_start or next_week_bounds()[0]
    week_end = week_start + datetime.timedelta(days=6)
    waiting = (sb.table("duel_queue").select("*")
               .eq("week_start", str(week_start)).order("rating", desc=True)
               .limit(1000).execute().data)
    if len(waiting) < 2:
        return {"matched": 0, "waiting": len(waiting)}

    created, leftover = [], None
    if len(waiting) % 2:
        leftover = waiting.pop()          # lowest-rated waits for next run

    for i in range(0, len(waiting), 2):
        a, b = waiting[i], waiting[i + 1]
        duel = create_duel(sb, week_start, week_end, a["user_id"], b["user_id"])
        created.append(duel["id"])
        for u in (a, b):
            sb.table("duel_queue").delete().eq("user_id", u["user_id"]).execute()

    return {"matched": len(created), "duels": created,
            "waiting": 1 if leftover else 0}


def join_queue(sb, user_id: str, week_start=None) -> dict:
    week_start = week_start or next_week_bounds()[0]
    rank = (sb.table("duel_rankings").select("rating")
            .eq("user_id", user_id).execute().data)
    rating = rank[0]["rating"] if rank else 1000
    sb.table("duel_queue").upsert([{
        "user_id": user_id, "week_start": str(week_start), "rating": rating,
    }], on_conflict="user_id")
    return {"queued": True, "week_start": str(week_start), "rating": rating}


# -------------------------------------------------------------------- scoring

def _elo(rating_a: int, rating_b: int, score_a: float, k: int = 32) -> tuple:
    """Standard Elo. Beating a stronger opponent has to move you more than
    farming a weaker one, which is the whole point of ranking consistency."""
    expected_a = 1 / (1 + 10 ** ((rating_b - rating_a) / 400))
    delta = round(k * (score_a - expected_a))
    return rating_a + delta, rating_b - delta


def apply_result(sb, duel_id: int, score_a: float, score_b: float,
                 bonus_a: float = 0.0, bonus_b: float = 0.0) -> dict:
    """Grade a finished duel and move both ratings."""
    duel = sb.table("duels").select("*").eq("id", duel_id).execute().data[0]
    if duel["state"] == "final":
        return {"skipped": "already graded"}

    total_a, total_b = score_a + bonus_a, score_b + bonus_b
    outcome = 0.5 if total_a == total_b else (1.0 if total_a > total_b else 0.0)
    winner = None if outcome == 0.5 else (duel["user_a"] if outcome else duel["user_b"])

    ranks = {}
    for uid in (duel["user_a"], duel["user_b"]):
        row = sb.table("duel_rankings").select("*").eq("user_id", uid).execute().data
        ranks[uid] = row[0] if row else {
            "user_id": uid, "rating": 1000, "wins": 0, "losses": 0, "ties": 0,
            "streak": 0, "best_rating": 1000, "duels_played": 0,
        }

    a, b = ranks[duel["user_a"]], ranks[duel["user_b"]]
    new_a, new_b = _elo(a["rating"], b["rating"], outcome)

    for row, rating, won in ((a, new_a, outcome), (b, new_b, 1 - outcome)):
        row["rating"] = rating
        row["best_rating"] = max(row["best_rating"], rating)
        row["duels_played"] += 1
        if won == 0.5:
            row["ties"] += 1
            row["streak"] = 0
        elif won == 1.0:
            row["wins"] += 1
            row["streak"] = row["streak"] + 1 if row["streak"] > 0 else 1
        else:
            row["losses"] += 1
            row["streak"] = row["streak"] - 1 if row["streak"] < 0 else -1
        row["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()

    sb.table("duel_rankings").upsert([a, b], on_conflict="user_id")
    sb.table("duels").update({
        "state": "final", "score_a": score_a, "score_b": score_b,
        "bonus_a": bonus_a, "bonus_b": bonus_b, "winner": winner,
        "graded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }).eq("id", duel_id).execute()

    return {"winner": winner, "rating_a": new_a, "rating_b": new_b,
            "total_a": total_a, "total_b": total_b}
