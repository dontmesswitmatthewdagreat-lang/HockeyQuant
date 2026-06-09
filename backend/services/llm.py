"""Shared Groq LLM helper (used by summaries + the news digester)."""

import os
from typing import List, Dict, Optional


def groq_chat(
    messages: List[Dict[str, str]],
    model: str = "llama-3.3-70b-versatile",
    max_tokens: int = 1200,
    temperature: float = 0.4,
    response_json: bool = False,
) -> str:
    """Call Groq chat completion and return the message content.

    Raises RuntimeError if GROQ_API_KEY is missing.
    """
    api_key = os.getenv("GROQ_API_KEY")
    if not api_key:
        raise RuntimeError("GROQ_API_KEY not configured")

    from groq import Groq
    client = Groq(api_key=api_key)
    kwargs = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    if response_json:
        kwargs["response_format"] = {"type": "json_object"}
    resp = client.chat.completions.create(**kwargs)
    return (resp.choices[0].message.content or "").strip()
