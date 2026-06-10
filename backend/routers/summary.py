"""
HockeyQuant Summary Router
AI-generated game prediction summaries using Groq (free tier)
"""

import os
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

router = APIRouter()

# In-memory cache: key = "{away}_{home}_{date}", value = summary string
_cache: dict = {}


class TeamSummaryData(BaseModel):
    team: str
    final_score: float
    goalie: str
    goalie_gsax: float
    goalie_sv_pct: float
    fatigue: str
    streak: str
    injuries: str
    h2h: str


class SummaryRequest(BaseModel):
    away: TeamSummaryData
    home: TeamSummaryData
    pick: str
    diff: float
    confidence: str
    factors: List[str]
    game_time: Optional[str] = None


@router.post("/summary")
async def generate_summary(req: SummaryRequest):
    """Generate an AI summary explaining why the model picked the favored team."""
    # Build cache key from teams + date
    date_str = req.game_time[:10] if req.game_time else "unknown"
    cache_key = f"{req.away.team}_{req.home.team}_{date_str}"

    if cache_key in _cache:
        return {"summary": _cache[cache_key]}

    api_key = os.getenv("GROQ_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="GROQ_API_KEY not configured")

    loser = req.home.team if req.pick == req.away.team else req.away.team
    factors_str = ", ".join(req.factors) if req.factors else "overall team strength"

    prompt = (
        f"You are a concise NHL analyst. In 2-3 sentences, explain why {req.pick} "
        f"is favored over {loser} tonight.\n\n"
        f"Projected scores: {req.away.team} {req.away.final_score:.1f} – "
        f"{req.home.team} {req.home.final_score:.1f} "
        f"({req.confidence}, {abs(req.diff):.1f} pt spread)\n"
        f"Key factors: {factors_str}\n"
        f"{req.away.team}: {req.away.streak} | fatigue: {req.away.fatigue} | "
        f"injuries: {req.away.injuries} | H2H: {req.away.h2h}\n"
        f"{req.home.team}: {req.home.streak} | fatigue: {req.home.fatigue} | "
        f"injuries: {req.home.injuries} | H2H: {req.home.h2h}\n"
        f"{req.away.team} starting goalie: {req.away.goalie} "
        f"(GSAX {req.away.goalie_gsax:+.2f}, SV% {req.away.goalie_sv_pct:.3f})\n"
        f"{req.home.team} starting goalie: {req.home.goalie} "
        f"(GSAX {req.home.goalie_gsax:+.2f}, SV% {req.home.goalie_sv_pct:.3f})\n\n"
        f"Attribute each goalie ONLY to the team it is listed under above — do not guess or swap them. "
        f"Be direct and data-focused. Write as a single paragraph. No buzzwords."
    )

    try:
        from groq import Groq
        client = Groq(api_key=api_key)
        response = client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=150,
            temperature=0.4,
        )
        summary = response.choices[0].message.content.strip()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate summary: {str(e)}")

    _cache[cache_key] = summary
    return {"summary": summary}
