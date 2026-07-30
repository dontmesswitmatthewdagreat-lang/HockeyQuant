"""Durable trade ledger.

Spotrac's transactions feed is a rolling window — it paginates chronologically
and purges history at the league-year rollover — so the report card's view of
who traded what kept changing underneath it. This module makes Supabase the
system of record: `sync_trades` scrapes and upserts (never deletes), and
`get_trades` serves the union of what we've stored and what's live right now.

That union is the whole point. The stored side survives a scrape that breaks or
an upstream purge; the live side means a trade made ten minutes ago grades
immediately instead of waiting for the next sync. If Supabase is unreachable we
fall back to the raw scrape, so the report card never hard-fails on either leg.
"""

import datetime
import time
from typing import Optional

from services.player_market import fetch_trades
from services.offseason_data import _ABBREV_FIX
from services.supabase_client import get_supabase

_TTL = 6 * 3600
_cache: dict = {}


def _norm_team(abbrev: str) -> str:
    """Spotrac writes WAS/SJ/TB; the rest of the app uses WSH/SJS/TBL."""
    a = (abbrev or "").strip().upper()
    return _ABBREV_FIX.get(a, a)


def league_year(d: Optional[datetime.date] = None) -> int:
    """The NHL league year a date belongs to — the year free agency opened.

    June (draft) through the following May all roll up to the same offseason,
    which is the window the report card grades."""
    d = d or datetime.date.today()
    return d.year if d.month >= 6 else d.year - 1


def _as_date(value) -> Optional[datetime.date]:
    if not value:
        return None
    try:
        return datetime.date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def sync_trades() -> dict:
    """Scrape the live feed and merge it into the ledger. Additive only."""
    sb = get_supabase()
    if sb is None:
        return {"error": "supabase not configured"}

    scraped = fetch_trades()
    players, picks = scraped["players"], scraped["picks"]
    if not players and not picks:
        # A broken or rate-limited scrape must never be mistaken for "no trades
        # happened" — leave the ledger exactly as it is.
        return {"players": 0, "picks": 0, "skipped": "empty scrape"}

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    default_year = league_year()

    player_rows = []
    for p in players:
        on = _as_date(p.get("traded_on"))
        player_rows.append({
            "player_name": p["name"],
            "name_norm": p["name"].lower(),
            "from_team": _norm_team(p["from_team"]),
            "to_team": _norm_team(p["to_team"]),
            "traded_on": on.isoformat() if on else None,
            "league_year": league_year(on) if on else default_year,
            "last_seen_at": now,
        })

    pick_rows = []
    for k in picks:
        on = _as_date(k.get("traded_on"))
        pick_rows.append({
            "from_team": _norm_team(k["from"]),
            "to_team": _norm_team(k["to"]),
            "pick_year": int(k["year"]),
            "pick_round": int(k["round"]),
            "conditional": bool(k["conditional"]),
            "traded_on": on.isoformat() if on else None,
            "league_year": league_year(on) if on else default_year,
            "last_seen_at": now,
        })

    if player_rows:
        sb.table("trade_players").upsert(player_rows, on_conflict="name_norm,to_team,from_team")
    if pick_rows:
        sb.table("trade_picks").upsert(pick_rows, on_conflict="from_team,to_team,pick_year,pick_round")

    _cache.pop("trades", None)
    return {"players": len(player_rows), "picks": len(pick_rows), "league_year": default_year}


def load_trades(year: Optional[int] = None) -> dict:
    """Read the ledger back in `fetch_trades`'s shape."""
    sb = get_supabase()
    if sb is None:
        return {"players": [], "picks": []}
    year = year or league_year()

    pl = sb.table("trade_players").select(
        "player_name,from_team,to_team,traded_on").eq("league_year", year).limit(2000).execute().data
    pk = sb.table("trade_picks").select(
        "from_team,to_team,pick_year,pick_round,conditional,traded_on"
    ).eq("league_year", year).limit(2000).execute().data

    return {
        "players": [{"name": r["player_name"], "from_team": r["from_team"],
                     "to_team": r["to_team"], "traded_on": r.get("traded_on")} for r in pl],
        "picks": [{"from": r["from_team"], "to": r["to_team"], "year": r["pick_year"],
                   "round": r["pick_round"], "conditional": r["conditional"],
                   "traded_on": r.get("traded_on")} for r in pk],
    }


def get_trades() -> dict:
    """The report card's entry point: stored ledger ∪ live feed.

    Either leg may come back empty (scrape broken, DB down) without taking the
    other with it — which is exactly the failure the ledger exists to absorb."""
    entry = _cache.get("trades")
    if entry and time.time() - entry["ts"] < _TTL:
        return entry["data"]

    year = league_year()
    try:
        stored = load_trades(year)
    except Exception:
        stored = {"players": [], "picks": []}
    try:
        live = fetch_trades()
    except Exception:
        live = {"players": [], "picks": []}

    players, seen = [], set()
    for p in stored["players"] + live["players"]:
        frm, to = _norm_team(p["from_team"]), _norm_team(p["to_team"])
        key = (p["name"].lower(), to, frm)
        if key in seen:
            continue
        seen.add(key)
        players.append({"name": p["name"], "from_team": frm, "to_team": to,
                        "traded_on": p.get("traded_on")})

    picks, pseen = [], set()
    for k in stored["picks"] + live["picks"]:
        frm, to = _norm_team(k["from"]), _norm_team(k["to"])
        key = (frm, to, int(k["year"]), int(k["round"]))
        if key in pseen:
            continue
        pseen.add(key)
        picks.append({"from": frm, "to": to, "year": int(k["year"]),
                      "round": int(k["round"]), "conditional": bool(k["conditional"]),
                      "traded_on": k.get("traded_on")})

    data = {"players": players, "picks": picks}
    if players or picks:
        _cache["trades"] = {"ts": time.time(), "data": data}
    return data
