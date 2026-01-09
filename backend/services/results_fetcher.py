"""
NHL Game Results Fetcher
Fetches final scores from NHL API
"""

import requests
from typing import Dict, List, Optional
from datetime import datetime


def fetch_game_results(date_str: str) -> List[Dict]:
    """
    Fetch game results from NHL API for a specific date.

    Args:
        date_str: Date in YYYY-MM-DD format

    Returns:
        List of game results with teams and final scores
    """
    url = f"https://api-web.nhle.com/v1/score/{date_str}"

    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        data = response.json()
    except Exception as e:
        print(f"Error fetching results for {date_str}: {e}")
        return []

    results = []
    games = data.get("games", [])

    for game in games:
        # Only include completed games
        game_state = game.get("gameState", "")
        if game_state not in ["FINAL", "OFF"]:
            continue

        away_team = game.get("awayTeam", {})
        home_team = game.get("homeTeam", {})

        away_abbrev = away_team.get("abbrev", "")
        home_abbrev = home_team.get("abbrev", "")
        away_score = away_team.get("score", 0)
        home_score = home_team.get("score", 0)

        # Determine winner
        if away_score > home_score:
            winner = away_abbrev
        elif home_score > away_score:
            winner = home_abbrev
        else:
            # Tie (shouldn't happen in NHL, but handle it)
            winner = None

        results.append({
            "game_id": str(game.get("id", "")),
            "away_team": away_abbrev,
            "home_team": home_abbrev,
            "away_final": away_score,
            "home_final": home_score,
            "actual_winner": winner,
        })

    return results


def get_first_game_time(date_str: str) -> Optional[datetime]:
    """
    Get the start time of the first game on a given date.

    Args:
        date_str: Date in YYYY-MM-DD format

    Returns:
        datetime of first game start, or None if no games
    """
    url = f"https://api-web.nhle.com/v1/schedule/{date_str}"

    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        data = response.json()
    except Exception as e:
        print(f"Error fetching schedule for {date_str}: {e}")
        return None

    game_week = data.get("gameWeek", [])

    for day in game_week:
        if day.get("date") == date_str:
            games = day.get("games", [])
            if games:
                # Games should be sorted by time, get first one
                first_game = games[0]
                start_time = first_game.get("startTimeUTC")
                if start_time:
                    return datetime.fromisoformat(start_time.replace("Z", "+00:00"))

    return None
