"""
Raw NHL news gathering for the daily digest.

Pulls from free, legal sources — RSS feeds, Google News per-team queries, and
Reddit threads — and normalizes them into deduped NewsItems. We only keep
headlines + short snippets + the original link (never full article text).
Every source fails independently: one dead feed never breaks the digest.
"""

import re
import time
import urllib.parse
from typing import List, Dict, Optional

import requests

from services.constants import TEAM_FULL_NAMES

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36 HockeyQuant/1.0")
REDDIT_UA = "HockeyQuant/1.0 (news digest; contact: hockeyquant.app)"

# League-wide RSS feeds (dead ones are skipped silently).
LEAGUE_RSS = [
    ("ESPN", "https://www.espn.com/espn/rss/nhl/news"),
    ("CBS Sports", "https://www.cbssports.com/rss/headlines/nhl/"),
    ("Yahoo Sports", "https://sports.yahoo.com/nhl/rss/"),
    ("Sportsnet", "https://www.sportsnet.ca/hockey/nhl/feed/"),
    ("The Hockey News", "https://thehockeynews.com/.rss/full/"),
    ("NHL.com", "https://www.nhl.com/rss/news"),
]

# Team subreddits (best-effort; a wrong/empty one just yields nothing).
REDDIT_SUBS = {
    "ANA": "AnaheimDucks", "BOS": "BostonBruins", "BUF": "sabres", "CGY": "CalgaryFlames",
    "CAR": "canes", "CHI": "hawks", "COL": "ColoradoAvalanche", "CBJ": "BlueJackets",
    "DAL": "DallasStars", "DET": "DetroitRedWings", "EDM": "EdmontonOilers", "FLA": "FloridaPanthers",
    "LAK": "losangeleskings", "MIN": "wildhockey", "MTL": "Habs", "NSH": "Predators",
    "NJD": "devils", "NYI": "NewYorkIslanders", "NYR": "rangers", "OTT": "OttawaSenators",
    "PHI": "Flyers", "PIT": "penguins", "SJS": "SanJoseSharks", "SEA": "SeattleKraken",
    "STL": "stlouisblues", "TBL": "TampaBayLightning", "TOR": "leafs", "UTA": "utahhockey",
    "VAN": "canucks", "VGK": "goldenknights", "WSH": "caps", "WPG": "winnipegjets",
}

_HTML = re.compile(r"<[^>]+>")
_OG = re.compile(r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\'][^>]+content=["\']([^"\']+)["\']', re.I)
_OG2 = re.compile(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\']', re.I)


def _clean(text: Optional[str], limit: int = 280) -> str:
    if not text:
        return ""
    t = _HTML.sub("", text)
    t = re.sub(r"\s+", " ", t).strip()
    return t[:limit]


def _norm_url(url: str) -> str:
    if not url:
        return ""
    u = url.split("?")[0].rstrip("/")
    return u.lower()


def _entry_image(e) -> Optional[str]:
    """Best image directly available in an RSS entry, if any."""
    for key in ("media_thumbnail", "media_content"):
        for m in (e.get(key) or []):
            if m.get("url"):
                return m["url"]
    for l in (e.get("links") or []):
        if "image" in (l.get("type") or "") and l.get("href"):
            return l["href"]
    m = re.search(r'<img[^>]+src="([^"]+)"', e.get("summary", "") or "")
    return m.group(1) if m else None


def _rss_items(source: str, url: str, team: Optional[str] = None, limit: int = 15) -> List[Dict]:
    try:
        import feedparser
        # Fetch with our UA, then parse (feedparser's default UA is often blocked).
        resp = requests.get(url, headers={"User-Agent": UA}, timeout=12)
        if not resp.ok:
            return []
        feed = feedparser.parse(resp.content)
    except Exception:
        return []
    out = []
    for e in feed.entries[:limit]:
        link = getattr(e, "link", "")
        title = _clean(getattr(e, "title", ""), 200)
        if not link or not title:
            continue
        out.append({
            "source": source,
            "title": title,
            "snippet": _clean(getattr(e, "summary", "") or getattr(e, "description", "")),
            "url": link,
            "published_at": getattr(e, "published", None) or getattr(e, "updated", None),
            "team": team,
            "image": _entry_image(e),
        })
    return out


def _google_news(query: str, source_label: str, team: Optional[str], limit: int = 12) -> List[Dict]:
    q = urllib.parse.quote_plus(query)
    url = f"https://news.google.com/rss/search?q={q}&hl=en-US&gl=US&ceid=US:en"
    items = _rss_items(source_label, url, team=team, limit=limit)
    # Google News titles are "Headline - Publisher"; split the publisher into source.
    for it in items:
        if " - " in it["title"]:
            head, pub = it["title"].rsplit(" - ", 1)
            it["title"] = head.strip()
            it["source"] = pub.strip() or source_label
    return items


def _reddit(subreddit: str, team: Optional[str], limit: int = 12) -> List[Dict]:
    url = f"https://www.reddit.com/r/{subreddit}/hot.json?limit={limit}&raw_json=1"
    try:
        resp = requests.get(url, headers={"User-Agent": REDDIT_UA}, timeout=12)
        if not resp.ok:
            return []
        children = resp.json().get("data", {}).get("children", [])
    except Exception:
        return []
    out = []
    for c in children:
        d = c.get("data", {})
        if d.get("stickied") or d.get("over_18"):
            continue
        title = _clean(d.get("title", ""), 200)
        if not title:
            continue
        # Prefer the linked article; fall back to the reddit thread.
        ext = d.get("url_overridden_by_dest") or d.get("url", "")
        permalink = "https://www.reddit.com" + d.get("permalink", "")
        link = ext if (ext and not d.get("is_self")) else permalink
        pv = (((d.get("preview") or {}).get("images") or [{}])[0].get("source") or {}).get("url")
        th = d.get("thumbnail") or ""
        out.append({
            "source": f"r/{subreddit}",
            "title": title,
            "snippet": _clean(d.get("selftext", ""), 200),
            "url": link,
            "published_at": d.get("created_utc"),
            "team": team,
            "score": d.get("score", 0),
            "image": pv or (th if th.startswith("http") else None),
        })
    return out


def _og_image(url: str) -> Optional[str]:
    """Fetch a page and extract its og:image / twitter:image."""
    try:
        r = requests.get(url, headers={"User-Agent": UA}, timeout=8, allow_redirects=True)
        if not r.ok:
            return None
        html = r.text[:200_000]
        m = _OG.search(html) or _OG2.search(html)
        if m:
            img = m.group(1).replace("&amp;", "&")
            return img if img.startswith("http") else None
    except Exception:
        return None
    return None


def resolve_image(item: Dict) -> Optional[str]:
    """A header image for a news item: feed-provided, else the article's og:image."""
    if item.get("image"):
        return item["image"]
    if item.get("url"):
        return _og_image(item["url"])
    return None


def _is_yahoo(it: Dict) -> bool:
    return "yahoo" in (it.get("source", "") or "").lower() or "yimg" in (it.get("image", "") or "")


def _dedupe(items: List[Dict]) -> List[Dict]:
    seen_url, by_title, out = set(), {}, []
    for it in items:
        nu = _norm_url(it["url"])
        if nu in seen_url:
            continue
        nt = re.sub(r"[^a-z0-9 ]", "", it["title"].lower())[:80]
        if nt in by_title:
            # Same story already kept — prefer a non-Yahoo source (Yahoo's og:image
            # is sometimes a generic banner; CBS/ESPN/NHL give real article photos).
            i = by_title[nt]
            if _is_yahoo(out[i]) and not _is_yahoo(it):
                seen_url.discard(_norm_url(out[i]["url"]))
                seen_url.add(nu)
                out[i] = it
            continue
        seen_url.add(nu)
        by_title[nt] = len(out)
        out.append(it)
    return out


def fetch_league_items(limit: int = 80) -> List[Dict]:
    """League-wide news: RSS feeds + Google News (general + prospects/draft) + Reddit."""
    items: List[Dict] = []
    for source, url in LEAGUE_RSS:
        items += _rss_items(source, url)
    items += _google_news("NHL hockey", "Google News", None, limit=15)
    # Dedicated prospect / draft coverage — there's a lot of it (draft + development
    # camps) that the generic "NHL" query doesn't surface.
    items += _google_news("NHL prospects", "Google News", None, limit=14)
    items += _google_news("NHL draft", "Google News", None, limit=14)
    items += _reddit("hockey", None, limit=20)
    items += _reddit("nhl_draft", None, limit=12)
    return _dedupe(items)[:limit]


def fetch_team_items(abbrev: str, limit: int = 30) -> List[Dict]:
    """Team-specific news: Google News for the team + the team subreddit."""
    name = TEAM_FULL_NAMES.get(abbrev, abbrev)
    items: List[Dict] = []
    items += _google_news(f'"{name}" NHL', "Google News", abbrev, limit=15)
    sub = REDDIT_SUBS.get(abbrev)
    if sub:
        items += _reddit(sub, abbrev, limit=15)
    return _dedupe(items)[:limit]
