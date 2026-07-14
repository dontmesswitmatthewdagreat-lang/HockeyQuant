"""
HockeyQuant News Router — AI-compiled daily NHL news digest.

Generated 3x/day (cron): a morning league-wide digest, plus per-team pre-game
and post-game digests for teams playing that date (within their windows).
Stores AI summaries + source links only (no full article text).
"""

import re
from datetime import datetime, timezone, timedelta
from typing import Optional, List

import requests
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from services.supabase_client import get_supabase
from services.news_sources import (
    fetch_league_items, fetch_team_items, _google_news, _norm_url, _title_norm,
)
from services.news_digester import build_digest, answer_query, MODEL
from services.push import apns_send, push_users
from services.constants import TEAM_FULL_NAMES

router = APIRouter()
NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}


def _sb():
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    return sb


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _games_for_date(date_str: str) -> List[dict]:
    """Each team playing `date_str` with its game start (UTC)."""
    try:
        r = requests.get(f"https://api-web.nhle.com/v1/schedule/{date_str}", headers=NHL_HEADERS, timeout=15)
        data = r.json()
    except Exception:
        return []
    out = []
    for day in data.get("gameWeek", []):
        if day.get("date") != date_str:
            continue
        for g in day.get("games", []):
            st = g.get("startTimeUTC")
            if not st:
                continue
            gutc = datetime.fromisoformat(st.replace("Z", "+00:00"))
            a = (g.get("awayTeam") or {}).get("abbrev")
            h = (g.get("homeTeam") or {}).get("abbrev")
            for team in (a, h):
                if team:
                    out.append({"team": team, "game_utc": gutc})
    return out


def _exists(sb, date_str: str, kind: str, scope: str) -> bool:
    rows = sb.table("news_digests").select("id").eq("digest_date", date_str).eq("kind", kind).eq("scope", scope).execute().data
    return bool(rows)


def _store(sb, date_str: str, kind: str, scope: str, digest: dict) -> None:
    sb.table("news_digests").upsert([{
        "digest_date": date_str, "kind": kind, "scope": scope,
        "title": digest["title"], "intro": digest["intro"],
        "key_points": digest.get("key_points", []), "items": digest["items"],
        "model": MODEL, "created_at": _now(),
    }], on_conflict="digest_date,kind,scope").execute()


def _all_games_final(date_str: str) -> bool:
    """True when every game on `date_str` is final (or there are no games)."""
    try:
        r = requests.get(f"https://api-web.nhle.com/v1/score/{date_str}", headers=NHL_HEADERS, timeout=15)
        games = r.json().get("games", [])
    except Exception:
        return False
    return all(g.get("gameState") in ("OFF", "FINAL") for g in games)


# MARK: - Archive plumbing (news_items)
#
# Every fetched candidate is archived once (unique on normalized URL), digests
# only feature stories that haven't been in one for 72h (no day-to-day repeats),
# and featured items get marked back so the exclusion window rolls forward.
# All best-effort: digests keep working even before the table exists.

def _archive_candidates(sb, items: list, team: Optional[str]) -> None:
    try:
        from services.news_registry import normalize_item, archive_items
        entry = {"id": "digest", "source": "News", "item_kind": "article",
                 "scope": "team" if team else "league", "team": team}
        archive_items(sb, [normalize_item(r, entry) for r in items])
    except Exception:
        pass


def _drop_recently_featured(sb, items: list, hours: int = 72) -> list:
    """Remove candidates whose URL or title was featured in any digest within
    the window — the cross-run dedupe (also saves Groq tokens)."""
    try:
        cutoff = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
        # PostgREST in.(...) needs values quoted (URLs can carry commas/parens,
        # normalized titles carry spaces).
        def quoted(vals):
            return [f'"{v}"' for v in vals if v and '"' not in v]
        url_norms = quoted([_norm_url(it["url"]) for it in items])
        used_urls, used_titles = set(), set()
        for i in range(0, len(url_norms), 100):
            rows = sb.table("news_items").select("url_norm,title_norm") \
                .in_("url_norm", url_norms[i:i + 100]) \
                .gt("used_in_digest_at", cutoff).execute().data
            for r in rows:
                used_urls.add(r["url_norm"])
                used_titles.add(r["title_norm"])
        title_norms = quoted([_title_norm(it["title"]) for it in items])
        for i in range(0, len(title_norms), 100):
            rows = sb.table("news_items").select("title_norm") \
                .in_("title_norm", title_norms[i:i + 100]) \
                .gt("used_in_digest_at", cutoff).execute().data
            used_titles.update(r["title_norm"] for r in rows)
        return [it for it in items
                if _norm_url(it["url"]) not in used_urls
                and _title_norm(it["title"]) not in used_titles]
    except Exception:
        return items


def _mark_featured(sb, digest: dict) -> None:
    """Stamp featured items (and upgrade their tag/image with Groq's picks)."""
    now = _now()
    for it in digest.get("items", []):
        try:
            patch = {"used_in_digest_at": now}
            if it.get("tag"):
                patch["tag"] = it["tag"]
            if it.get("image_url"):
                patch["image_url"] = it["image_url"]
            sb.table("news_items").update(patch) \
                .eq("url_norm", _norm_url(it.get("url") or "")).execute()
        except Exception:
            continue


LEAGUE_KINDS = ("morning", "midday", "afternoon", "evening")


@router.post("/news/generate/{date_str}/{kind}")
def generate(date_str: str, kind: str):
    """Cron/admin: build + store digests for a date. Idempotent per (date, kind, scope)."""
    if kind not in LEAGUE_KINDS + ("pregame", "postgame"):
        raise HTTPException(status_code=400,
                            detail="kind must be morning|midday|afternoon|evening|pregame|postgame")
    sb = _sb()

    if kind in LEAGUE_KINDS:
        if _exists(sb, date_str, kind, "league"):
            return {"skipped": "already generated"}
        if kind == "evening" and not _all_games_final(date_str):
            return {"skipped": "games still in progress"}
        items = fetch_league_items()
        _archive_candidates(sb, items, None)
        fresh = _drop_recently_featured(sb, items)
        if len(fresh) < 5:
            return {"skipped": f"only {len(fresh)} fresh stories — nothing new to tell"}
        digest = build_digest(fresh, "league", kind, max_items=14)
        if not digest:
            raise HTTPException(status_code=502, detail="Could not build digest")
        _store(sb, date_str, kind, "league", digest)
        _mark_featured(sb, digest)
        # Push only the bookend editions — midday/afternoon refresh quietly.
        if kind in ("morning", "evening"):
            tokens = [t["token"] for t in sb.table("device_tokens").select("token").execute().data]
            if kind == "morning":
                apns_send(tokens, "Morning hockey digest 🏒",
                          (digest.get("intro") or "Today's NHL roundup is ready.")[:140])
            else:
                apns_send(tokens, "Tonight's NHL nightcap 🏒",
                          (digest.get("intro") or "Tonight's results roundup is ready.")[:140])
        return {"generated": ["league"], "kind": kind, "items": len(digest["items"])}

    now = datetime.now(timezone.utc)
    generated = []
    for g in _games_for_date(date_str):
        team, gutc = g["team"], g["game_utc"]
        if kind == "pregame":
            in_window = gutc - timedelta(hours=4) <= now <= gutc - timedelta(hours=1)
        else:  # postgame — a few hours after the (~3h) game ends
            in_window = now >= gutc + timedelta(hours=5)
        if not in_window or _exists(sb, date_str, kind, team):
            continue
        items = fetch_team_items(team)
        _archive_candidates(sb, items, team)
        fresh = _drop_recently_featured(sb, items)
        if len(fresh) < 4:
            continue
        digest = build_digest(fresh, team, kind, max_items=8)
        if not digest:
            continue
        _store(sb, date_str, kind, team, digest)
        _mark_featured(sb, digest)
        generated.append(team)
        followers = sb.table("profiles").select("id").eq("favorite_team", team).execute().data
        label = "Pre-Game" if kind == "pregame" else "Post-Game"
        push_users(sb, [u["id"] for u in followers],
                   f"{TEAM_FULL_NAMES.get(team, team)} — {label} digest",
                   (digest.get("intro") or "")[:140])
    return {"generated": generated}


@router.post("/news/ingest")
def ingest():
    """Cron: pull every registered source (RSS, Google News, Reddit, Bluesky)
    into the news_items archive. Cheap, AI-free, safe to run often."""
    from services.news_registry import run_ingest
    return run_ingest(_sb())


@router.get("/news/feed")
def feed(team: Optional[str] = None, kind: Optional[str] = None,
         cursor: Optional[str] = None, limit: int = 30):
    """The Wire: the flat chronological archive (articles + blurbs mixed),
    keyset-paginated by id. With `team`, league items plus that team's blogs;
    without, league scope only."""
    sb = _sb()
    limit = max(1, min(limit, 60))
    try:
        q = sb.table("news_items").select(
            "id,title,snippet,tag,source,url,published_at,image_url,kind,team,first_seen_at")
        if kind in ("article", "blurb"):
            q = q.eq("kind", kind)
        if team:
            q = q.or_(f"team.eq.{team.upper()},team.is.null")
        else:
            q = q.eq("scope", "league")
        if cursor:
            try:
                q = q.lt("id", int(cursor))
            except ValueError:
                pass
        rows = q.order("id", desc=True).limit(limit).execute().data
    except Exception:
        rows = []
    items = [{
        "id": r["id"], "headline": r["title"], "blurb": r.get("snippet") or "",
        "tag": r.get("tag") or "Other", "source": r["source"], "url": r["url"],
        "published_at": r.get("published_at"), "image_url": r.get("image_url"),
        "kind": r.get("kind") or "article", "team": r.get("team"),
        "first_seen_at": r.get("first_seen_at"),
    } for r in rows]
    next_cursor = str(rows[-1]["id"]) if len(rows) == limit else None
    return {"items": items, "next_cursor": next_cursor}


@router.get("/news/latest")
def latest(team: Optional[str] = None):
    """App feed: the latest league digest edition (evening after games end, else
    morning) + the favorite team's recent digests."""
    sb = _sb()
    digests = sb.table("news_digests").select("*").eq("scope", "league") \
        .in_("kind", list(LEAGUE_KINDS)) \
        .order("created_at", desc=True).limit(2).execute().data
    if team:
        digests += sb.table("news_digests").select("*").eq("scope", team) \
            .order("created_at", desc=True).limit(4).execute().data
    return {"digests": digests}


@router.get("/news/search")
def search(q: str):
    """AI answer from live news for `q` + matching items from past digests."""
    q = (q or "").strip()
    if len(q) < 2:
        raise HTTPException(status_code=400, detail="Query too short")
    sb = _sb()
    live = _google_news(q, "Google News", None, limit=15)
    ans = answer_query(q, live)

    # Archive matches: full-text search over every stored article/blurb,
    # with a title ilike fallback for short queries and team abbrevs.
    cols = "title,snippet,tag,source,url,published_at,image_url"
    rows = []
    try:
        # wfts = PostgREST's websearch_to_tsquery operator (works on every
        # supabase-py version, unlike the .text_search helper).
        rows = sb.table("news_items").select(cols) \
            .filter("fts", "wfts(english)", q) \
            .order("id", desc=True).limit(12).execute().data or []
    except Exception:
        rows = []
    if not rows:
        try:
            rows = sb.table("news_items").select(cols) \
                .ilike("title", f"%{q}%").order("id", desc=True).limit(12).execute().data or []
        except Exception:
            rows = []
    past = [{
        "headline": r["title"], "blurb": r.get("snippet") or "",
        "tag": r.get("tag") or "Other", "source": r["source"], "url": r["url"],
        "published_at": r.get("published_at"), "image_url": r.get("image_url"),
    } for r in rows]
    return {"answer": ans["answer"], "sources": ans["items"], "past_matches": past}


# MARK: - Article quick summary (long-press on a news card)

_summary_cache: dict = {}


class SummarizeRequest(BaseModel):
    url: str
    headline: str = ""
    blurb: str = ""


def _article_text(url: str) -> str:
    """Best-effort readable text from an article page (paragraph tags only)."""
    from services.news_sources import resolve_gnews_url
    resp = requests.get(
        resolve_gnews_url(url),
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"},
        timeout=12, allow_redirects=True,
    )
    resp.raise_for_status()
    html = resp.text
    html = re.sub(r"<(script|style|nav|header|footer|aside)[^>]*>.*?</\1>", " ", html, flags=re.S | re.I)
    paras = re.findall(r"<p[^>]*>(.*?)</p>", html, re.S | re.I)
    chunks = []
    for p in paras:
        txt = re.sub(r"<[^>]+>", " ", p)
        txt = re.sub(r"\s+", " ", txt).strip()
        if len(txt) > 60:  # skip nav crumbs / bylines
            chunks.append(txt)
    return " ".join(chunks)[:6000]


@router.post("/news/summarize")
def summarize(req: SummarizeRequest):
    """3–4 sentence AI summary of one article so users don't have to leave the
    app. Cached per URL; article text is fetched best-effort and we fall back
    to the digest headline/blurb when a site blocks us."""
    url = (req.url or "").strip()
    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid URL")
    if url in _summary_cache:
        return {"summary": _summary_cache[url], "cached": True}

    try:
        text = _article_text(url)
    except Exception:
        text = ""
    source = f"ARTICLE TEXT:\n{text}" if len(text) >= 400 else \
        f"Only the headline and blurb are available.\nHEADLINE: {req.headline}\nBLURB: {req.blurb}"
    if len(text) < 400 and not (req.headline or req.blurb):
        raise HTTPException(status_code=422, detail="Could not read this article")

    from services.llm import groq_chat
    try:
        summary = groq_chat(
            [
                {"role": "system", "content": (
                    "You summarize NHL news for a hockey app. Reply with a 3-4 sentence "
                    "plain-text summary of the article: what happened, who is involved, and "
                    "why it matters. No preamble, no markdown, no headline restatement.")},
                {"role": "user", "content": source},
            ],
            max_tokens=700, temperature=0.3,
        )
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Summary unavailable: {e}")

    # If the model ran out of tokens mid-thought, cut back to the last full sentence.
    if summary and summary[-1] not in ".!?\"" and "." in summary:
        summary = summary[: summary.rfind(".") + 1]

    # Never cache (or serve) an empty completion — the model occasionally spends
    # its whole budget reasoning; let the client retry instead.
    if not summary.strip():
        raise HTTPException(status_code=503, detail="Summary came back empty — try again")

    if len(_summary_cache) > 500:
        _summary_cache.clear()
    _summary_cache[url] = summary
    return {"summary": summary, "cached": False}
