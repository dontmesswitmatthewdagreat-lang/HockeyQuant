"""
Player market API: fair values, market heat, movers, graded signings, and
per-player detail (range, history, comparables, best fits).
"""

import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException

from services.supabase_client import get_supabase
from services.player_market import (
    build_market, comparables, resolve_action_photo, wikimedia_photo, _norm, _group,
)

router = APIRouter()


def _sb():
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    return sb


def _market():
    try:
        return build_market()
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Market model unavailable: {e}")


def _player_payload(p: dict) -> dict:
    payload = {
        "name": p["name"], "team": p.get("contract_team") or p.get("team"),
        "position": p["position"], "age": p["age"], "gp": p["gp"],
        "ppg": round(p["ppg"], 3), "aav": p.get("aav"),
        "modelValue": round(p["model_value"]),
        "marketValue": round(p["market_value"]),
        "valueLow": round(p["value_low"]), "valueHigh": round(p["value_high"]),
        "verdict": _verdict(p),
    }
    if p["position"] == "G":
        payload["gsax"] = round(p.get("gsax", 0), 1)
        payload["svPct"] = round(p.get("sv_pct", 0), 3)
    return payload


def _verdict(p: dict) -> Optional[str]:
    aav = p.get("aav")
    if not aav or aav < 1_000_000:
        return None
    prem = (aav - p["model_value"]) / p["model_value"]
    return "steal" if prem < -0.15 else ("overpay" if prem > 0.15 else "fair")


@router.get("/market/overview")
def overview():
    """Index series, heat by group, movers, and graded recent signings."""
    market = _market()
    sb = _sb()

    index, movers = [], []
    try:
        rows = sb.table("player_values").select("snap_date,market_value") \
            .order("snap_date", desc=True).limit(20000).execute().data
        by_date: dict = {}
        for r in rows:
            by_date.setdefault(r["snap_date"], []).append(float(r["market_value"]))
        index = [{"date": d, "value": sum(sorted(v, reverse=True)[:100]) / min(len(v), 100)}
                 for d, v in sorted(by_date.items())]

        dates = sorted(by_date)
        if len(dates) >= 2:
            latest, prev = dates[-1], dates[-2]
            cur = {r2["name"]: float(r2["market_value"]) for r2 in
                   sb.table("player_values").select("name,market_value").eq("snap_date", latest).execute().data}
            old = {r2["name"]: float(r2["market_value"]) for r2 in
                   sb.table("player_values").select("name,market_value").eq("snap_date", prev).execute().data}
            deltas = [{"name": n, "marketValue": v, "deltaPct": (v - old[n]) / old[n] * 100}
                      for n, v in cur.items() if n in old and old[n] > 0]
            deltas.sort(key=lambda d: -abs(d["deltaPct"]))
            movers = [d for d in deltas if abs(d["deltaPct"]) > 0.5][:10]
    except Exception:
        pass

    signings = sorted(
        [s for s in market["signings"] if s.get("fair_value")],
        key=lambda s: -s["aav"])[:20]
    return {
        "heat": {g: round(v * 100, 1) for g, v in market["heat"].items()},
        "trainedOn": market["trained_on"],
        "index": index,
        "movers": movers,
        "signings": [{
            "name": s["name"], "team": s["team"], "position": s["position"],
            "aav": s["aav"], "years": s.get("years"),
            "fairValue": round(s["fair_value"]), "verdict": s["verdict"],
        } for s in signings],
    }


@router.get("/market/players")
def players(q: Optional[str] = None, limit: int = 50):
    """Search, or the top of the market by value."""
    market = _market()
    pool = list(market["players"].values())
    if q and q.strip():
        needle = _norm(q)
        pool = [p for p in pool if needle in _norm(p["name"])]
    pool.sort(key=lambda p: -p["market_value"])
    return {"players": [_player_payload(p) for p in pool[:min(limit, 200)]]}


@router.get("/market/player/{name}")
def player_detail(name: str):
    market = _market()
    key = _norm(name)
    p = market["players"].get(key)
    if not p:
        raise HTTPException(status_code=404, detail="Player not valued (goalie, or too few games)")

    history = []
    try:
        history = _sb().table("player_values").select("snap_date,model_value,market_value") \
            .eq("name", p["name"]).order("snap_date").limit(120).execute().data
    except Exception:
        pass

    fits = []
    try:
        from services.draft_simulator import _fetch_standings, _team_needs
        from services.offseason_data import fetch_team_caps
        standings = _fetch_standings()
        needs = _team_needs({s["abbrev"]: s for s in standings})
        caps = {t["abbrev"]: t["cap_space"] for t in fetch_team_caps()}
        g = _group(p["position"])
        for ab, need in needs.items():
            space = caps.get(ab, 0)
            if space < p["market_value"]:
                continue
            match = 2 if need.get("primary") == g else (1 if need.get("secondary") == g else 0)
            fits.append({"team": ab, "needMatch": match, "capSpace": space})
        fits.sort(key=lambda f: (-f["needMatch"], -f["capSpace"]))
        fits = fits[:5]
    except Exception:
        fits = []

    payload = _player_payload(p)
    # Hero image, best first: a real NHL landscape action shot (full-bleed), else
    # a validated Wikipedia photo or the headshot as a portrait over the gradient.
    action = resolve_action_photo(p, market)
    if action:
        payload["actionPhoto"] = action
    else:
        payload["portrait"] = wikimedia_photo(p["name"]) or p.get("headshot")
    if p.get("headshot"):
        payload["headshot"] = p["headshot"]

    return {
        "player": payload,
        "heatPct": round(market["heat"][_group(p["position"])] * 100, 1),
        "history": [{"date": h["snap_date"], "modelValue": float(h["model_value"]),
                     "marketValue": float(h["market_value"])} for h in history],
        "comparables": [_player_payload(c) for c in comparables(key, market)],
        "fits": fits,
    }


@router.get("/market/report-card/{team}")
def report_card(team: str):
    """The team's real offseason, graded: signings vs model value, talent
    in/out, what rivals paid the departures, and the draft desk."""
    from services.player_market import offseason_report_card
    try:
        return offseason_report_card(team.upper())
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Report card unavailable: {e}")


@router.get("/pulse/league")
def pulse_league():
    """Dial-style league reads for the News tab's pulse deck: luck meter,
    race tightness, deadline pulse, playoff pulse (dormant off-window)."""
    from services.league_pulse import league_pulses
    return {"pulses": league_pulses()}


@router.post("/market/sync-trades")
def sync_trades_route():
    """Cron: merge the live transactions feed into the durable trade ledger.

    Spotrac's feed rolls over and drops history, so the report card reads the
    ledger — this is what keeps it filled. Additive: an empty scrape is a no-op,
    never a wipe."""
    from services.trade_store import sync_trades
    try:
        return sync_trades()
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Trade sync failed: {e}")


@router.get("/market/trades")
def trades_route(year: Optional[int] = None):
    """The stored trade ledger for a league year (defaults to the current one).

    Reports an empty ledger rather than failing when the tables aren't there
    yet — the report card runs off the live feed in that state, so this is a
    diagnostic, not an outage."""
    from services.trade_store import load_trades, league_year
    y = year or league_year()
    try:
        data = load_trades(y)
    except Exception as e:
        return {"league_year": y, "players": [], "picks": [],
                "counts": {"players": 0, "picks": 0}, "ledger_error": str(e)[:200]}
    return {"league_year": y, **data,
            "counts": {"players": len(data["players"]), "picks": len(data["picks"])}}


@router.post("/market/snapshot")
def snapshot():
    """Cron: store today's values so the index/sparklines accrue history."""
    market = _market()
    sb = _sb()
    today = datetime.date.today().isoformat()
    pool = sorted(market["players"].values(), key=lambda p: -p["market_value"])[:400]
    rows = [{
        "snap_date": today, "name": p["name"],
        "team": p.get("contract_team") or p.get("team"), "position": p["position"],
        "aav": p.get("aav"), "model_value": round(p["model_value"]),
        "market_value": round(p["market_value"]),
    } for p in pool]
    for i in range(0, len(rows), 300):
        sb.table("player_values").upsert(rows[i:i + 300], on_conflict="name,snap_date").execute()
    return {"stored": len(rows), "date": today}
