"""HockeyQuant Prospects Router — league-wide draft board + per-team pools."""

from typing import Optional
from fastapi import APIRouter, HTTPException

from services.supabase_client import get_supabase
from services.prospects import sync_all
from services.draft_simulator import build_mock_draft
from services.push import apns_send


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
            "projection": projection, "news": news}


@router.post("/prospects/mock-draft/generate")
def generate_mock_draft():
    """Cron/admin: build + store this week's first-round mock draft. Idempotent per ISO week."""
    sb = _sb()
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

    sb.table("mock_drafts").upsert([{
        "draft_year": mock["draft_year"],
        "edition": mock["edition"],
        "generated_at": mock["generated_at"],
        "order_basis": mock["order_basis"],
        "lottery_odds": mock.get("lottery_odds", []),
        "picks": mock["picks"],
    }], on_conflict="draft_year,edition").execute()

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
