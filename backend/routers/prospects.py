"""HockeyQuant Prospects Router — league-wide draft board + per-team pools."""

from typing import Optional
from fastapi import APIRouter, HTTPException

from services.supabase_client import get_supabase
from services.prospects import sync_all
from services.draft_simulator import build_mock_draft
from services.draft_results import fetch_draft_picks, drafted_lookup, team_picks
from services.push import apns_send


def _notable_draft_year(sb) -> int:
    import datetime
    rows = sb.table("prospects").select("draft_year").eq("notable", "true").limit(1).execute().data
    return (rows[0].get("draft_year") if rows else None) or datetime.date.today().year


def _mock_target_year(sb) -> int:
    """Mocks always look forward: once a draft has actually happened, the
    next class is the story (insiders publish way-too-early mocks within
    days), even before Central Scouting ranks it."""
    year = _notable_draft_year(sb)
    return year + 1 if fetch_draft_picks(year) else year


def _rank_deltas(sb, nhl_ids):
    """nhl_id -> rank change vs the previous list snapshot (positive = riser).
    Best-effort: {} until the prospect_rankings table exists / has 2 dates."""
    try:
        dates = sb.table("prospect_rankings").select("list_date") \
            .order("list_date", desc=True).limit(1).execute().data
        if not dates:
            return {}
        latest = dates[0]["list_date"]
        prev_rows = sb.table("prospect_rankings").select("list_date") \
            .lt("list_date", latest).order("list_date", desc=True).limit(1).execute().data
        if not prev_rows:
            return {}
        prev = prev_rows[0]["list_date"]
        cur = sb.table("prospect_rankings").select("nhl_id,rank").eq("list_date", latest) \
            .in_("nhl_id", nhl_ids).execute().data
        old = sb.table("prospect_rankings").select("nhl_id,rank").eq("list_date", prev) \
            .in_("nhl_id", nhl_ids).execute().data
        old_map = {r["nhl_id"]: r["rank"] for r in old}
        return {r["nhl_id"]: old_map[r["nhl_id"]] - r["rank"]
                for r in cur if r["nhl_id"] in old_map}
    except Exception:
        return {}

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
    deltas = _rank_deltas(sb, [r["nhl_id"] for r in rows if r.get("nhl_id")])
    for r in rows:
        r["rank_delta"] = deltas.get(r.get("nhl_id"))
    return {"prospects": rows}


@router.get("/prospects/{nhl_id}/detail")
def prospect_detail(nhl_id: int):
    """Detail sheet payload: ranking history, latest news, and the current
    mock draft's projection for this prospect."""
    sb = _sb()
    rows = sb.table("prospects").select("*").eq("nhl_id", nhl_id).limit(1).execute().data
    if not rows:
        raise HTTPException(status_code=404, detail="Unknown prospect")
    prospect = rows[0]

    try:
        history = sb.table("prospect_rankings").select("list_date,rank") \
            .eq("nhl_id", nhl_id).order("list_date").limit(60).execute().data
    except Exception:
        history = []

    drafted = None
    if prospect.get("draft_year"):
        drafted = drafted_lookup(prospect["draft_year"]).get(prospect["name"].lower())

    projection = None
    try:
        mocks = sb.table("mock_drafts").select("edition,picks") \
            .order("generated_at", desc=True).limit(1).execute().data
        if mocks:
            for pick in mocks[0].get("picks") or []:
                if (pick.get("prospect") or {}).get("name") == prospect["name"]:
                    projection = {"overall": pick.get("overall"), "team": pick.get("team"),
                                  "reason": pick.get("reason"), "edition": mocks[0]["edition"]}
                    break
    except Exception:
        pass

    news = []
    try:
        from services.news_sources import _google_news
        items = _google_news(f'"{prospect["name"]}" hockey', "Google News", None, limit=6)
        news = [{"headline": i.get("title"), "source": i.get("source"),
                 "url": i.get("url"), "published_at": i.get("published_at"),
                 "blurb": i.get("snippet") or ""}
                for i in items if i.get("url") and i.get("title")]
    except Exception:
        pass

    return {"prospect": prospect, "rank_history": history,
            "projection": projection, "drafted": drafted, "news": news}


@router.get("/prospects/draft-results")
def draft_results(team: Optional[str] = None, year: Optional[int] = None):
    """Actual draft picks once the draft has happened (all, or one team's
    class). Team results carry ELC-signed status: a drafted player appearing
    on his team's real cap sheet has signed his entry-level deal."""
    sb = _sb()
    y = year or _notable_draft_year(sb)
    picks = team_picks(y, team) if team else fetch_draft_picks(y)
    if team and picks:
        try:
            from services.offseason_data import fetch_roster
            from services.player_market import _norm, _fuzzy_key
            roster = fetch_roster(team.upper())
            names = {_norm(p["name"]) for p in roster}
            fuzzy = {_fuzzy_key(p["name"]) for p in roster}
            picks = [{**p, "signed_elc": _norm(p["player"]) in names
                      or _fuzzy_key(p["player"]) in fuzzy} for p in picks]
        except Exception:
            pass
    return {"year": y, "picks": picks}


@router.get("/prospects/mock-drafts")
def list_mock_drafts():
    """The newest mock from every source (internal engine + insider outlets)."""
    sb = _sb()
    rows = sb.table("mock_drafts").select("*").order("generated_at", desc=True).limit(24).execute().data
    # Forward-looking only: once any source covers a newer draft class, stale
    # previous-class mocks drop out of the list.
    if rows:
        latest_year = max(r.get("draft_year") or 0 for r in rows)
        rows = [r for r in rows if (r.get("draft_year") or 0) == latest_year]
    seen, out = set(), []
    for r in rows:
        src = r.get("source") or "HockeyQuant"
        if src in seen:
            continue
        seen.add(src)
        r["source"] = src
        out.append(r)
    # Internal projection first, then outlets alphabetically.
    out.sort(key=lambda r: (r["source"] != "HockeyQuant", r["source"]))
    return {"mocks": out}


@router.get("/prospects/calder")
def calder():
    """Calder Watch: pool prospects producing in the NHL this season.
    Dormant (active=false) during the offseason; lights up in October."""
    from services.pipeline_stats import calder_watch
    return calder_watch(_sb())


@router.get("/prospects/pipeline-stats")
def pipeline_stats(team: str):
    """Live CHL season stats for a team's prospect pool (name-matched)."""
    sb = _sb()
    rows = sb.table("prospects").select("name").eq("team", team.upper()).limit(80).execute().data
    from services.pipeline_stats import stats_for_names
    matched = stats_for_names([r["name"] for r in rows])
    return {"stats": [{"name": k, **v} for k, v in matched.items()]}


@router.post("/prospects/mock-draft/import-insiders")
def import_insiders():
    """Cron/admin: pull + store the latest insider mock drafts (one per outlet)."""
    sb = _sb()
    from services.insider_mocks import import_insider_mocks
    imported = import_insider_mocks(sb, _mock_target_year(sb))
    return {"imported": imported}


@router.post("/prospects/mock-draft/generate")
def generate_mock_draft():
    """Cron/admin: build + store this week's first-round mock draft. Idempotent per ISO week."""
    sb = _sb()
    # Post-draft the internal pool is the class that was just picked — skip
    # until the next Central Scouting list lands (insider imports carry the
    # way-too-early 2027+ mocks in the meantime).
    if _mock_target_year(sb) != _notable_draft_year(sb):
        return {"skipped": "draft complete — internal mock resumes with the next class rankings"}

    mock = build_mock_draft(sb)
    if not mock:
        raise HTTPException(status_code=502, detail="Could not build mock draft")

    # Annotate movement vs the previous edition, and remember whether this
    # edition is genuinely new (for the push below).
    prev_rows = sb.table("mock_drafts").select("edition,picks") \
        .order("generated_at", desc=True).limit(1).execute().data
    is_new_edition = not prev_rows or prev_rows[0]["edition"] != mock["edition"]
    prev_overall = {}
    if prev_rows:
        for p in prev_rows[0].get("picks") or []:
            name = (p.get("prospect") or {}).get("name")
            if name:
                prev_overall[name] = p.get("overall")
    for p in mock["picks"]:
        name = (p.get("prospect") or {}).get("name")
        p["previous_overall"] = prev_overall.get(name)

    row = {
        "draft_year": mock["draft_year"],
        "edition": mock["edition"],
        "generated_at": mock["generated_at"],
        "order_basis": mock["order_basis"],
        "lottery_odds": mock.get("lottery_odds", []),
        "picks": mock["picks"],
    }
    try:
        sb.table("mock_drafts").upsert([{**row, "source": "HockeyQuant"}],
                                       on_conflict="draft_year,edition,source").execute()
    except Exception:
        # Pre-migration-023 fallback (no source column yet).
        sb.table("mock_drafts").upsert([row], on_conflict="draft_year,edition").execute()

    if is_new_edition and mock["picks"]:
        top = mock["picks"][0]
        try:
            tokens = [r["token"] for r in sb.table("device_tokens").select("token").execute().data]
            apns_send(tokens, "This week's mock draft is in",
                      f"{top['team']} take {top['prospect']['name']} at #1 — see the full first round.")
        except Exception as e:
            print(f"[prospects] mock push skipped: {e}")

    return {"edition": mock["edition"], "picks": len(mock["picks"]), "new": is_new_edition}


@router.get("/prospects/mock-draft")
def latest_mock_draft():
    """App: the most recent weekly mock draft edition."""
    sb = _sb()
    rows = sb.table("mock_drafts").select("*").order("generated_at", desc=True).limit(1).execute().data
    return {"mock_draft": rows[0] if rows else None}
