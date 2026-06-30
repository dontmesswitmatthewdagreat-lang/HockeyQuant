"""
AI news digester. Takes raw fetched items + a scope/kind and asks Groq to curate
+ write a digest. The model references items by index only; we reconstruct the
real url/source/published_at from the originals so links can't be hallucinated.
"""

import json
from typing import List, Dict, Optional

from services.llm import groq_chat
from services.news_sources import resolve_image
from services.constants import TEAM_FULL_NAMES

MODEL = "llama-3.3-70b-versatile"
TAGS = ["Trade", "Injury", "Signing", "Rumor", "Recap", "Analysis", "Prospect", "Lineup", "Game", "Other"]

SYSTEM = (
    "You are an NHL news editor compiling a concise daily digest. You are given a "
    "numbered list of news items (headline, source, snippet). Curate the most notable, "
    "on-topic items and write a tight digest.\n"
    "Rules:\n"
    "- Only use items from the provided list; reference each by its number (idx).\n"
    "- Do NOT invent facts. Base each blurb ONLY on that item's headline/snippet.\n"
    "- blurb: 1-2 factual sentences, no hype or buzzwords.\n"
    f"- tag: exactly one of {', '.join(TAGS)}.\n"
    "- Skip duplicates, non-NHL noise, and pure opinion/clickbait.\n"
    "- Order items by importance.\n"
    "- key_points: 3-5 short, punchy one-line takeaways of what matters most today.\n"
    'Return ONLY JSON: {"intro": "<1-2 sentence overview>", '
    '"key_points": ["<takeaway>", ...], '
    '"items": [{"idx": <int>, "headline": "<short headline>", "blurb": "<1-2 sentences>", "tag": "<tag>"}]}'
)


def _kind_instruction(scope: str, kind: str) -> str:
    if scope == "league":
        if kind == "evening":
            return ("Compile a nightcap roundup now that tonight's NHL games have wrapped: "
                    "tonight's results and standout performances first, then any breaking "
                    "trades, signings, injuries, prospect/draft developments, or storylines from today.")
        return ("Compile a morning roundup of the most notable news from around the NHL "
                "over the last day — trades, signings, injuries, rumors, storylines, and "
                "prospect/draft news (the draft, picks, development camps, top prospects). "
                "Give prospect and draft stories real coverage when they're in the items.")
    name = TEAM_FULL_NAMES.get(scope, scope)
    if kind == "pregame":
        return (f"Compile a pre-game digest for the {name}: the storylines, injuries, lineup "
                f"notes, and matchup angles heading into their next game.")
    if kind == "postgame":
        return (f"Compile a post-game digest for the {name}: recap, key takeaways, and analysis "
                f"from their most recent game.")
    return f"Compile the most notable recent news for the {name}."


def _title(scope: str, kind: str) -> str:
    if scope == "league":
        return "Around the League"
    name = TEAM_FULL_NAMES.get(scope, scope)
    return f"{name} — " + {"pregame": "Pre-Game", "postgame": "Post-Game"}.get(kind, "Latest")


def build_digest(items: List[Dict], scope: str, kind: str, max_items: int = 8) -> Optional[Dict]:
    """Returns {title, intro, items:[{headline,blurb,tag,source,url,published_at}]} or None."""
    if not items:
        return None

    numbered = "\n".join(
        f"[{i}] {it['title']} (source: {it.get('source', '?')})"
        f"{' — ' + it['snippet'] if it.get('snippet') else ''}"
        for i, it in enumerate(items)
    )
    user = (
        f"{_kind_instruction(scope, kind)}\n\n"
        f"Select up to {max_items} items.\n\nItems:\n{numbered}"
    )

    try:
        raw = groq_chat(
            [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}],
            model=MODEL, max_tokens=2400, temperature=0.4, response_json=True,
        )
        data = json.loads(raw)
    except Exception:
        return None

    out_items = []
    for entry in data.get("items", [])[:max_items]:
        try:
            idx = int(entry.get("idx"))
        except (TypeError, ValueError):
            continue
        if idx < 0 or idx >= len(items):
            continue
        src = items[idx]  # real source-of-truth for the link
        tag = entry.get("tag") if entry.get("tag") in TAGS else "Other"
        out_items.append({
            "headline": (entry.get("headline") or src["title"])[:200],
            "blurb": (entry.get("blurb") or "")[:400],
            "tag": tag,
            "source": src.get("source", "?"),
            "url": src["url"],
            "published_at": str(src["published_at"]) if src.get("published_at") is not None else None,
            "image_url": resolve_image(src),
        })

    if not out_items:
        return None
    # The lead (hero) card is big — make sure it has a photo when any top item does.
    if not out_items[0].get("image_url"):
        for i in range(1, min(len(out_items), 4)):
            if out_items[i].get("image_url"):
                out_items.insert(0, out_items.pop(i))
                break
    key_points = [str(k)[:160] for k in (data.get("key_points") or []) if k][:5]
    return {
        "title": _title(scope, kind),
        "intro": (data.get("intro") or "")[:500],
        "key_points": key_points,
        "items": out_items,
    }


def answer_query(query: str, items: List[Dict], max_sources: int = 6) -> Dict:
    """AI answer to a user question from live news items. Cites items by index;
    links are reconstructed from the real items (no hallucination)."""
    if not items:
        return {"answer": "I couldn't find recent news on that.", "items": []}
    numbered = "\n".join(
        f"[{i}] {it['title']} (source: {it.get('source', '?')})"
        f"{' — ' + it['snippet'] if it.get('snippet') else ''}"
        for i, it in enumerate(items)
    )
    system = (
        "You are an NHL news assistant. Answer the user's question using ONLY the provided "
        "news items. Be direct and factual; if the items don't answer it, say so plainly. "
        "Cite the supporting items by their index.\n"
        'Return ONLY JSON: {"answer": "<2-4 sentences>", "sources": [<idx>, ...]}'
    )
    try:
        raw = groq_chat(
            [{"role": "system", "content": system}, {"role": "user", "content": f"Question: {query}\n\nItems:\n{numbered}"}],
            model=MODEL, max_tokens=600, temperature=0.3, response_json=True,
        )
        data = json.loads(raw)
    except Exception:
        return {"answer": "", "items": []}
    src = []
    for idx in (data.get("sources") or [])[:max_sources]:
        try:
            i = int(idx)
        except (TypeError, ValueError):
            continue
        if 0 <= i < len(items):
            it = items[i]
            src.append({
                "headline": it["title"][:200], "blurb": "", "tag": "News",
                "source": it.get("source", "?"), "url": it["url"],
                "published_at": str(it["published_at"]) if it.get("published_at") is not None else None,
                "image_url": it.get("image"),
            })
    return {"answer": (data.get("answer") or "")[:800], "items": src}
