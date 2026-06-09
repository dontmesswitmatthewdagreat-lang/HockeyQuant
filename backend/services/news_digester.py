"""
AI news digester. Takes raw fetched items + a scope/kind and asks Groq to curate
+ write a digest. The model references items by index only; we reconstruct the
real url/source/published_at from the originals so links can't be hallucinated.
"""

import json
from typing import List, Dict, Optional

from services.llm import groq_chat
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
    'Return ONLY JSON: {"intro": "<1-2 sentence overview>", "items": '
    '[{"idx": <int>, "headline": "<short headline>", "blurb": "<1-2 sentences>", "tag": "<tag>"}]}'
)


def _kind_instruction(scope: str, kind: str) -> str:
    if scope == "league":
        return ("Compile a morning roundup of the most notable news from around the NHL "
                "over the last day — trades, signings, injuries, rumors, and storylines.")
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
            model=MODEL, max_tokens=1400, temperature=0.4, response_json=True,
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
        })

    if not out_items:
        return None
    return {
        "title": _title(scope, kind),
        "intro": (data.get("intro") or "")[:500],
        "items": out_items,
    }
