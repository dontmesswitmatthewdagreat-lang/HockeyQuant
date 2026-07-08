"""
Insider mock drafts: find each outlet's latest NHL mock-draft article, extract
the ordered first-round picks with the LLM, and shape them like the internal
mock so the app renders them with the same board.
"""

import datetime
import json
import re
from typing import Dict, List, Optional

import requests

from services.news_sources import _google_news, resolve_gnews_url
from services.llm import groq_chat
from services.constants import TEAM_FULL_NAMES
from services.draft_simulator import _prospect_payload

OUTLETS = ["ESPN", "TSN", "Sportsnet", "The Athletic", "Daily Faceoff"]
_UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"}
_ALL_TEAMS = set(TEAM_FULL_NAMES.keys())


def _article_text(url: str) -> str:
    resp = requests.get(resolve_gnews_url(url), headers=_UA, timeout=15, allow_redirects=True)
    resp.raise_for_status()
    html = re.sub(r"<(script|style|nav|header|footer|aside)[^>]*>.*?</\1>", " ",
                  resp.text, flags=re.S | re.I)
    paras = re.findall(r"<(?:p|h2|h3|li)[^>]*>(.*?)</(?:p|h2|h3|li)>", html, re.S | re.I)
    chunks = []
    for p in paras:
        txt = re.sub(r"<[^>]+>", " ", p)
        txt = re.sub(r"\s+", " ", txt).strip()
        if len(txt) > 25:
            chunks.append(txt)
    return " ".join(chunks)[:14000]


def _extract_picks(outlet: str, text: str, draft_year: int) -> List[dict]:
    """LLM: pull the ordered (overall, team, player) triples out of an article."""
    system = (
        "You extract NHL mock-draft picks from an article. Return ONLY JSON: "
        '{"picks": [{"overall": <int>, "team": "<3-letter NHL abbrev>", "player": "<full name>"}]}. '
        "Rules: only include picks the article explicitly lists in its mock draft; keep the "
        "article's order; use standard NHL team abbreviations (TOR, SJS, TBL, LAK, NJD, MTL, "
        "VGK, WPG, WSH, UTA...); at most 32 picks; if the article is not actually a mock draft, "
        'return {"picks": []}.'
    )
    try:
        raw = groq_chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": f"{outlet} {draft_year} NHL mock draft article:\n{text}"}],
            max_tokens=2000, temperature=0.1, response_json=True)
        data = json.loads(raw)
    except Exception:
        return []
    out, seen_players, seen_slots = [], set(), set()
    for p in data.get("picks", []):
        try:
            overall = int(p.get("overall"))
        except (TypeError, ValueError):
            continue
        team = str(p.get("team") or "").upper().strip()
        player = str(p.get("player") or "").strip()
        if not player or team not in _ALL_TEAMS:
            continue
        if overall in seen_slots or player.lower() in seen_players or not (1 <= overall <= 32):
            continue
        seen_slots.add(overall)
        seen_players.add(player.lower())
        out.append({"overall": overall, "team": team, "player": player})
    out.sort(key=lambda p: p["overall"])
    return out


def _prospect_rows(sb) -> Dict[str, dict]:
    rows = sb.table("prospects").select(
        "nhl_id,name,position,league,ranking,info").eq("notable", "true").limit(400).execute().data
    return {r["name"].lower(): r for r in rows}


def import_insider_mocks(sb, draft_year: int) -> List[str]:
    """Fetch + extract one mock per outlet; store each as its own mock_drafts row.
    Returns the outlets that were imported."""
    pool = _prospect_rows(sb)
    now = datetime.datetime.now(datetime.timezone.utc)
    _, iso_week, _ = datetime.date.today().isocalendar()
    edition = f"{draft_year}-W{iso_week:02d}"
    imported = []

    for outlet in OUTLETS:
        items = _google_news(f"{outlet} NHL mock draft {draft_year} first round",
                             outlet, None, limit=5)
        # Prefer results actually from the outlet's own site/feed.
        items.sort(key=lambda i: 0 if outlet.lower().replace(" ", "") in
                   (i.get("url") or "").lower().replace(" ", "") else 1)
        picks_raw: List[dict] = []
        article_title = None
        for item in items[:3]:
            try:
                text = _article_text(item["url"])
            except Exception:
                continue
            picks_raw = _extract_picks(outlet, text, draft_year)
            if len(picks_raw) >= 10:
                article_title = item.get("title")
                break
            picks_raw = []
        if len(picks_raw) < 10:
            print(f"[insider-mocks] {outlet}: no usable mock found", flush=True)
            continue

        picks = []
        for p in picks_raw:
            row = pool.get(p["player"].lower())
            prospect = _prospect_payload(row, draft_year, p["overall"]) if row else {
                "id": p["player"], "nhl_id": None, "name": p["player"], "team": None,
                "position": None, "draft_year": draft_year, "league": None,
                "ranking": None, "notable": True, "info": {},
            }
            group = (row or {}).get("position") or "F"
            picks.append({
                "overall": p["overall"], "round": 1, "team": p["team"],
                "team_name": TEAM_FULL_NAMES.get(p["team"], p["team"]),
                "need": "G" if group == "G" else ("D" if group == "D" else "F"),
                "reason": f"Per {outlet}",
                "source": "insider",
                "prospect": prospect,
            })

        sb.table("mock_drafts").upsert([{
            "draft_year": draft_year,
            "edition": edition,
            "source": outlet,
            "generated_at": now.isoformat(),
            "order_basis": article_title or f"{outlet} mock draft",
            "lottery_odds": [],
            "picks": picks,
        }], on_conflict="draft_year,edition,source").execute()
        imported.append(outlet)
        print(f"[insider-mocks] {outlet}: stored {len(picks)} picks ({edition})", flush=True)

    return imported
