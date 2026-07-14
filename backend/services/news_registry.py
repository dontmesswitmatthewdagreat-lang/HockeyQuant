"""
The news source registry — News 2.0's ingestion framework.

Every source is one config entry; a generic runner fetches them all in
parallel (each failing independently) and upserts into the `news_items`
archive keyed on the normalized URL, so nothing is ever stored twice.
Ingestion is 100% AI-free: tags come from the registry default or a keyword
heuristic; Groq only upgrades tags when a digest features an item.

Adapters: rss (feedparser — also handles Atom/YouTube/podcast feeds),
gnews (Google News RSS search), reddit (public hot.json), bluesky (public
AppView API). All legal: headlines + snippets + links out, never full text.
"""

import re
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional

from services.news_sources import (
    _rss_items, _google_news, _reddit, _bluesky, _norm_url, _title_norm,
)

# item_kind: article (long-form, gets a thumbnail row) | blurb (tweet-like small card)
# scope: league | team (team entries carry "team": abbrev)
SOURCE_REGISTRY: List[Dict] = [
    # -- League outlets (the existing digest feeds, registered for the archive too)
    {"id": "espn", "adapter": "rss", "url": "https://www.espn.com/espn/rss/nhl/news",
     "source": "ESPN", "item_kind": "article", "scope": "league"},
    {"id": "cbs", "adapter": "rss", "url": "https://www.cbssports.com/rss/headlines/nhl/",
     "source": "CBS Sports", "item_kind": "article", "scope": "league"},
    {"id": "yahoo", "adapter": "rss", "url": "https://sports.yahoo.com/nhl/rss/",
     "source": "Yahoo Sports", "item_kind": "article", "scope": "league"},
    {"id": "sportsnet", "adapter": "rss", "url": "https://www.sportsnet.ca/hockey/nhl/feed/",
     "source": "Sportsnet", "item_kind": "article", "scope": "league"},
    {"id": "thn", "adapter": "rss", "url": "https://thehockeynews.com/.rss/full/",
     "source": "The Hockey News", "item_kind": "article", "scope": "league"},
    {"id": "nhl", "adapter": "rss", "url": "https://www.nhl.com/rss/news",
     "source": "NHL.com", "item_kind": "article", "scope": "league"},

    # -- In-depth / niche articles
    {"id": "phr", "adapter": "rss", "url": "https://www.prohockeyrumors.com/feed",
     "source": "Pro Hockey Rumors", "item_kind": "article", "scope": "league", "default_tag": "Rumor"},
    {"id": "dfo", "adapter": "rss", "url": "https://www.dailyfaceoff.com/feed",
     "source": "Daily Faceoff", "item_kind": "article", "scope": "league"},
    {"id": "spectors", "adapter": "rss", "url": "https://spectorshockey.net/feed",
     "source": "Spector's Hockey", "item_kind": "article", "scope": "league", "default_tag": "Rumor"},
    {"id": "athletic", "adapter": "rss", "url": "https://www.nytimes.com/athletic/rss/nhl/",
     "source": "The Athletic", "item_kind": "article", "scope": "league", "default_tag": "Analysis"},
    {"id": "hockey_tactics", "adapter": "rss", "url": "https://jhanhky.substack.com/feed",
     "source": "Hockey Tactics", "item_kind": "article", "scope": "league",
     "default_tag": "Analysis", "limit": 5},
    {"id": "tsn", "adapter": "gnews", "query": "site:tsn.ca NHL",
     "source": "TSN", "item_kind": "article", "scope": "league", "limit": 10},
    {"id": "thirtytwo_thoughts", "adapter": "rss", "url": "https://feeds.simplecast.com/fYqFr5h_",
     "source": "32 Thoughts", "item_kind": "article", "scope": "league",
     "default_tag": "Analysis", "limit": 3},

    # -- Insider blurbs (short-form; Bluesky public API, Reddit, YouTube)
    {"id": "bsky_puckpedia", "adapter": "bluesky", "actor": "puckpedia.com",
     "source": "PuckPedia", "item_kind": "blurb", "scope": "league", "default_tag": "Signing"},
    {"id": "bsky_dgb", "adapter": "bluesky", "actor": "downgoesbrown.bsky.social",
     "source": "Down Goes Brown", "item_kind": "blurb", "scope": "league", "default_tag": "Analysis"},
    {"id": "bsky_dom", "adapter": "bluesky", "actor": "domluszczyszyn.bsky.social",
     "source": "Dom Luszczyszyn", "item_kind": "blurb", "scope": "league", "default_tag": "Analysis"},
    {"id": "bsky_wysh", "adapter": "bluesky", "actor": "wyshynski.bsky.social",
     "source": "Greg Wyshynski", "item_kind": "blurb", "scope": "league"},
    {"id": "yt_nhl", "adapter": "rss",
     "url": "https://www.youtube.com/feeds/videos.xml?channel_id=UCqFMzb-4AUf6WAIbl132QKA",
     "source": "NHL on YouTube", "item_kind": "blurb", "scope": "league",
     "default_tag": "Game", "limit": 4},
    {"id": "r_hockey", "adapter": "reddit", "subreddit": "hockey",
     "source": "r/hockey", "item_kind": "blurb", "scope": "league", "limit": 6},

    # -- Team blogs (SB Nation `{domain}/feed` pattern; dead feeds fail silently,
    #    fill out the rest of the league one line at a time)
    {"id": "sbn_nyr", "adapter": "rss", "url": "https://www.blueshirtbanter.com/feed",
     "source": "Blueshirt Banter", "item_kind": "article", "scope": "team", "team": "NYR"},
    {"id": "sbn_bos", "adapter": "rss", "url": "https://www.stanleycupofchowder.com/feed",
     "source": "Stanley Cup of Chowder", "item_kind": "article", "scope": "team", "team": "BOS"},
    {"id": "sbn_det", "adapter": "rss", "url": "https://www.wingingitinmotown.com/feed",
     "source": "Winging It In Motown", "item_kind": "article", "scope": "team", "team": "DET"},
    {"id": "sbn_pit", "adapter": "rss", "url": "https://www.pensburgh.com/feed",
     "source": "Pensburgh", "item_kind": "article", "scope": "team", "team": "PIT"},
    {"id": "sbn_chi", "adapter": "rss", "url": "https://www.secondcityhockey.com/feed",
     "source": "Second City Hockey", "item_kind": "article", "scope": "team", "team": "CHI"},
    {"id": "sbn_phi", "adapter": "rss", "url": "https://www.broadstreethockey.com/feed",
     "source": "Broad Street Hockey", "item_kind": "article", "scope": "team", "team": "PHI"},
    {"id": "sbn_mtl", "adapter": "rss", "url": "https://www.habseyesontheprize.com/feed",
     "source": "Eyes On The Prize", "item_kind": "article", "scope": "team", "team": "MTL"},
    {"id": "sbn_tor", "adapter": "rss", "url": "https://www.pensionplanpuppets.com/feed",
     "source": "Pension Plan Puppets", "item_kind": "article", "scope": "team", "team": "TOR"},
    {"id": "rmnb_wsh", "adapter": "rss", "url": "https://www.russianmachineneverbreaks.com/feed/",
     "source": "RMNB", "item_kind": "article", "scope": "team", "team": "WSH"},
]

# Keyword → tag heuristic (only used when the registry has no default_tag).
_TAG_RULES = [
    (re.compile(r"\btrade[ds]?\b|\bacquire[sd]?\b", re.I), "Trade"),
    (re.compile(r"\bsign(s|ed|ing)?\b|\bcontract\b|\bextension\b|\bELC\b|\bAAV\b", re.I), "Signing"),
    (re.compile(r"\binjur|\bsurgery\b|\bweek-to-week\b|\bday-to-day\b|\bplaced on (IR|LTIR)\b", re.I), "Injury"),
    (re.compile(r"\brumor|\blinked to\b|\binterest(ed)? in\b", re.I), "Rumor"),
    (re.compile(r"\bdraft\b|\bprospect", re.I), "Prospect"),
    (re.compile(r"\bwaiv|\brecall(s|ed)?\b|\bscratch|\blineup\b|\bstarting goalie\b", re.I), "Lineup"),
    (re.compile(r"\brecap\b|\bfinal score\b|\bhighlights\b", re.I), "Recap"),
]


def _heuristic_tag(title: str, snippet: str) -> str:
    text = f"{title} {snippet}"
    for pattern, tag in _TAG_RULES:
        if pattern.search(text):
            return tag
    return "Other"


def _iso_published(raw) -> Optional[str]:
    """Best-effort ISO timestamp from the mixed published_at shapes the
    adapters produce (RFC822 strings, ISO strings, unix floats)."""
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        try:
            return datetime.fromtimestamp(raw, tz=timezone.utc).isoformat()
        except Exception:
            return None
    s = str(raw).strip()
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).isoformat()
    except Exception:
        pass
    try:
        from email.utils import parsedate_to_datetime
        return parsedate_to_datetime(s).isoformat()
    except Exception:
        return None


def normalize_item(raw: Dict, entry: Dict) -> Optional[Dict]:
    """One fetched item → a news_items row (or None if unusable)."""
    url, title = raw.get("url") or "", raw.get("title") or ""
    if not url.startswith("http") or not title:
        return None
    snippet = raw.get("snippet") or ""
    return {
        "url": url,
        "url_norm": _norm_url(url),
        "title": title,
        "title_norm": _title_norm(title),
        "snippet": snippet or None,
        "source": raw.get("source") or entry["source"],
        "source_id": entry["id"],
        "kind": entry.get("item_kind", "article"),
        "scope": entry.get("scope", "league"),
        "team": entry.get("team") or raw.get("team"),
        "tag": entry.get("default_tag") or _heuristic_tag(title, snippet),
        "image_url": raw.get("image"),
        "published_at": _iso_published(raw.get("published_at")),
    }


def _fetch_entry(entry: Dict) -> List[Dict]:
    limit = entry.get("limit", 12)
    adapter = entry["adapter"]
    if adapter == "rss":
        return _rss_items(entry["source"], entry["url"], team=entry.get("team"), limit=limit)
    if adapter == "gnews":
        return _google_news(entry["query"], entry["source"], entry.get("team"), limit=limit)
    if adapter == "reddit":
        return _reddit(entry["subreddit"], entry.get("team"), limit=limit)
    if adapter == "bluesky":
        return _bluesky(entry["actor"], entry["source"], team=entry.get("team"), limit=limit)
    return []


def archive_items(sb, rows: List[Dict]) -> int:
    """Upsert normalized rows into news_items, ignoring URLs already seen."""
    fresh, seen = [], set()
    for r in rows:
        if r and r["url_norm"] not in seen:
            seen.add(r["url_norm"])
            fresh.append(r)
    for i in range(0, len(fresh), 200):
        sb.table("news_items").upsert(
            fresh[i:i + 200], on_conflict="url_norm", ignore_duplicates=True).execute()
    return len(fresh)


def run_ingest(sb) -> Dict:
    """Fetch every registered source in parallel and archive the results.
    One dead source never breaks the run."""
    counts: Dict[str, int] = {}
    all_rows: List[Dict] = []

    def fetch(entry):
        try:
            return entry["id"], [normalize_item(r, entry) for r in _fetch_entry(entry)]
        except Exception:
            return entry["id"], []

    with ThreadPoolExecutor(max_workers=8) as pool:
        for source_id, rows in pool.map(fetch, SOURCE_REGISTRY):
            rows = [r for r in rows if r]
            counts[source_id] = len(rows)
            all_rows += rows

    inserted = archive_items(sb, all_rows)

    # Retention: the archive only promises ~4 months of scrollback.
    pruned = 0
    try:
        cutoff = (datetime.now(timezone.utc) - timedelta(days=120)).isoformat()
        res = sb.table("news_items").delete().lt("first_seen_at", cutoff).execute()
        pruned = len(res.data or [])
    except Exception:
        pass

    return {"fetched": counts, "archived": inserted, "pruned": pruned}
