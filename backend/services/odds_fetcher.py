"""
HockeyQuant Odds Fetcher
Fetches spreads and totals from The Odds API (free tier).
Gracefully falls back if API key is not set.
"""

import os
import requests
from datetime import datetime, timedelta
from typing import Optional, Dict


# The Odds API team names -> HockeyQuant abbreviations
ODDS_API_TEAM_MAPPING = {
    "Anaheim Ducks": "ANA",
    "Boston Bruins": "BOS",
    "Buffalo Sabres": "BUF",
    "Calgary Flames": "CGY",
    "Carolina Hurricanes": "CAR",
    "Chicago Blackhawks": "CHI",
    "Colorado Avalanche": "COL",
    "Columbus Blue Jackets": "CBJ",
    "Dallas Stars": "DAL",
    "Detroit Red Wings": "DET",
    "Edmonton Oilers": "EDM",
    "Florida Panthers": "FLA",
    "Los Angeles Kings": "LAK",
    "Minnesota Wild": "MIN",
    "Montreal Canadiens": "MTL",
    "Montréal Canadiens": "MTL",
    "Nashville Predators": "NSH",
    "New Jersey Devils": "NJD",
    "New York Islanders": "NYI",
    "New York Rangers": "NYR",
    "Ottawa Senators": "OTT",
    "Philadelphia Flyers": "PHI",
    "Pittsburgh Penguins": "PIT",
    "San Jose Sharks": "SJS",
    "Seattle Kraken": "SEA",
    "St. Louis Blues": "STL",
    "St Louis Blues": "STL",
    "Tampa Bay Lightning": "TBL",
    "Toronto Maple Leafs": "TOR",
    "Utah Hockey Club": "UTA",
    "Utah Mammoth": "UTA",
    "Vancouver Canucks": "VAN",
    "Vegas Golden Knights": "VGK",
    "Washington Capitals": "WSH",
    "Winnipeg Jets": "WPG",
}

# Cache: { "YYYY-MM-DD": { "fetched_at": datetime, "games": { "AWAY_HOME": GameOdds } } }
_odds_cache: Dict[str, Dict] = {}
CACHE_TTL_MINUTES = 30


class GameOdds:
    """Structured odds for a single game"""
    def __init__(self):
        self.spread_home: Optional[float] = None   # e.g., -1.5 (home favored)
        self.spread_away: Optional[float] = None    # e.g., +1.5
        self.total: Optional[float] = None          # e.g., 6.0
        self.bookmaker: Optional[str] = None        # e.g., "DraftKings"


def _team_name_to_abbrev(name: str) -> Optional[str]:
    """Convert The Odds API team name to HockeyQuant abbreviation"""
    return ODDS_API_TEAM_MAPPING.get(name)


def fetch_nhl_odds(date_str: str, game_utc_dates: Optional[set] = None) -> Dict[str, GameOdds]:
    """
    Fetch NHL spreads and totals for all games on a date.

    Returns: dict keyed by "AWAY_HOME" (e.g., "TOR_MTL") -> GameOdds

    Args:
        date_str: Schedule date (YYYY-MM-DD) used as cache key
        game_utc_dates: Set of UTC dates (YYYY-MM-DD) that games actually start on.
                       NHL games at 7pm ET on Feb 26 have UTC date Feb 27.
                       If None, tries both date_str and date_str + 1 day.

    Uses The Odds API free tier. Requires ODDS_API_KEY env var.
    Falls back gracefully to empty dict if unavailable.
    """
    global _odds_cache

    # Check cache
    if date_str in _odds_cache:
        cached = _odds_cache[date_str]
        if datetime.now() - cached["fetched_at"] < timedelta(minutes=CACHE_TTL_MINUTES):
            return cached["games"]

    api_key = os.getenv("ODDS_API_KEY", "").strip()
    if not api_key:
        return {}

    url = "https://api.the-odds-api.com/v4/sports/icehockey_nhl/odds"
    params = {
        "apiKey": api_key,
        "regions": "us",
        "markets": "spreads,totals",
        "oddsFormat": "american",
    }

    try:
        response = requests.get(url, params=params, timeout=15)
        response.raise_for_status()
        events = response.json()
    except Exception as e:
        print(f"Odds API fetch failed: {e}")
        return _odds_cache.get(date_str, {}).get("games", {})

    # Build set of valid UTC dates for filtering
    # NHL evening games (7pm ET) have UTC dates one day ahead of schedule date
    if game_utc_dates is None:
        try:
            base = datetime.strptime(date_str, "%Y-%m-%d")
            game_utc_dates = {date_str, (base + timedelta(days=1)).strftime("%Y-%m-%d")}
        except ValueError:
            game_utc_dates = {date_str}

    games: Dict[str, GameOdds] = {}
    for event in events:
        commence = event.get("commence_time", "")
        if not commence:
            continue
        event_date = commence[:10]  # "YYYY-MM-DD"
        if event_date not in game_utc_dates:
            continue

        away_name = event.get("away_team", "")
        home_name = event.get("home_team", "")
        away_abbrev = _team_name_to_abbrev(away_name)
        home_abbrev = _team_name_to_abbrev(home_name)
        if not away_abbrev or not home_abbrev:
            continue

        game_key = f"{away_abbrev}_{home_abbrev}"
        odds = GameOdds()

        # Use first bookmaker that has both markets
        bookmakers = event.get("bookmakers", [])
        for bm in bookmakers:
            markets = {m["key"]: m for m in bm.get("markets", [])}
            if "spreads" in markets and "totals" in markets:
                # Extract spread
                for outcome in markets["spreads"]["outcomes"]:
                    name = _team_name_to_abbrev(outcome["name"])
                    if name == home_abbrev:
                        odds.spread_home = outcome.get("point")
                    elif name == away_abbrev:
                        odds.spread_away = outcome.get("point")

                # Extract total
                for outcome in markets["totals"]["outcomes"]:
                    if outcome["name"] == "Over":
                        odds.total = outcome.get("point")

                odds.bookmaker = bm.get("title", "Unknown")
                break  # use first complete bookmaker

        if odds.spread_home is not None or odds.total is not None:
            games[game_key] = odds

    _odds_cache[date_str] = {"fetched_at": datetime.now(), "games": games}
    return games


def get_game_odds(date_str: str, away_abbrev: str, home_abbrev: str) -> Optional[GameOdds]:
    """Get odds for a specific game"""
    all_odds = fetch_nhl_odds(date_str)
    return all_odds.get(f"{away_abbrev}_{home_abbrev}")
