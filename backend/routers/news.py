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
from services.news_sources import fetch_league_items, fetch_team_items, _google_news
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


@router.post("/news/generate/{date_str}/{kind}")
def generate(date_str: str, kind: str):
    """Cron/admin: build + store digests for a date. Idempotent per (date, kind, scope)."""
    if kind not in ("morning", "evening", "pregame", "postgame"):
        raise HTTPException(status_code=400, detail="kind must be morning|evening|pregame|postgame")
    sb = _sb()

    if kind in ("morning", "evening"):
        if _exists(sb, date_str, kind, "league"):
            return {"skipped": "already generated"}
        if kind == "evening" and not _all_games_final(date_str):
            return {"skipped": "games still in progress"}
        digest = build_digest(fetch_league_items(), "league", kind, max_items=14)
        if not digest:
            raise HTTPException(status_code=502, detail="Could not build digest")
        _store(sb, date_str, kind, "league", digest)
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
        digest = build_digest(fetch_team_items(team), team, kind, max_items=8)
        if not digest:
            continue
        _store(sb, date_str, kind, team, digest)
        generated.append(team)
        followers = sb.table("profiles").select("id").eq("favorite_team", team).execute().data
        label = "Pre-Game" if kind == "pregame" else "Post-Game"
        push_users(sb, [u["id"] for u in followers],
                   f"{TEAM_FULL_NAMES.get(team, team)} — {label} digest",
                   (digest.get("intro") or "")[:140])
    return {"generated": generated}


@router.get("/news/latest")
def latest(team: Optional[str] = None):
    """App feed: the latest league digest edition (evening after games end, else
    morning) + the favorite team's recent digests."""
    sb = _sb()
    digests = sb.table("news_digests").select("*").eq("scope", "league") \
        .in_("kind", ["morning", "evening"]) \
        .order("created_at", desc=True).limit(1).execute().data
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

    terms = [t for t in re.split(r"\W+", q.lower()) if len(t) > 2]
    past, seen = [], set()
    if terms:
        rows = sb.table("news_digests").select("items").order("created_at", desc=True).limit(30).execute().data
        for r in rows:
            for it in (r.get("items") or []):
                text = f"{it.get('headline', '')} {it.get('blurb', '')}".lower()
                url = it.get("url")
                if url and url not in seen and any(t in text for t in terms):
                    seen.add(url)
                    past.append(it)
            if len(past) >= 8:
                break
    return {"answer": ans["answer"], "sources": ans["items"], "past_matches": past[:8]}


# MARK: - Article quick summary (long-press on a news card)

_summary_cache: dict = {}


class SummarizeRequest(BaseModel):
    url: str
    headline: str = ""
    blurb: str = ""


def _article_text(url: str) -> str:
    """Best-effort readable text from an article page (paragraph tags only)."""
    resp = requests.get(
        url,
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
            max_tokens=400, temperature=0.3,
        )
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Summary unavailable: {e}")

    # If the model ran out of tokens mid-thought, cut back to the last full sentence.
    if summary and summary[-1] not in ".!?\"" and "." in summary:
        summary = summary[: summary.rfind(".") + 1]

    if len(_summary_cache) > 500:
        _summary_cache.clear()
    _summary_cache[url] = summary
    return {"summary": summary, "cached": False}
