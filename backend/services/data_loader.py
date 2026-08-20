"""
HockeyQuant Data Loader
Fetches data from MoneyPuck, ESPN, and NHL API
"""

import pandas as pd
import requests
from bs4 import BeautifulSoup
from datetime import datetime, timedelta
import json
import os
import io
from typing import Optional, Dict, List, Tuple

from .constants import ESPN_TEAM_MAPPING


# Daily Faceoff team abbreviation mapping (their site uses slightly different abbreviations)
DAILY_FACEOFF_TEAM_MAPPING = {
    'ANA': 'ANA', 'ARI': 'ARI', 'BOS': 'BOS', 'BUF': 'BUF', 'CGY': 'CGY',
    'CAR': 'CAR', 'CHI': 'CHI', 'COL': 'COL', 'CBJ': 'CBJ', 'DAL': 'DAL',
    'DET': 'DET', 'EDM': 'EDM', 'FLA': 'FLA', 'LAK': 'LAK', 'MIN': 'MIN',
    'MTL': 'MTL', 'NSH': 'NSH', 'NJD': 'NJD', 'NYI': 'NYI', 'NYR': 'NYR',
    'OTT': 'OTT', 'PHI': 'PHI', 'PIT': 'PIT', 'SJS': 'SJS', 'SEA': 'SEA',
    'STL': 'STL', 'TBL': 'TBL', 'TOR': 'TOR', 'UTA': 'UTA', 'VAN': 'VAN',
    'VGK': 'VGK', 'WSH': 'WSH', 'WPG': 'WPG',
    # Alternate abbreviations Daily Faceoff might use
    'LA': 'LAK', 'NJ': 'NJD', 'NY': 'NYR', 'TB': 'TBL', 'WAS': 'WSH',
    'SJ': 'SJS', 'VEG': 'VGK', 'MON': 'MTL', 'CLB': 'CBJ', 'NAS': 'NSH',
}


class DataLoader:
    """Loads and caches data from external sources"""

    # MoneyPuck season summaries. The season label is its *start* year
    # (2025 = the 2025-26 season). Resolved dynamically each fall, with a
    # fallback to the previous season until MoneyPuck posts the new files.
    _MP_BASE = "https://moneypuck.com/moneypuck/playerData/seasonSummary/{year}/regular/{kind}.csv"
    _mp_season_cache: Optional[int] = None

    @classmethod
    def _moneypuck_season(cls) -> int:
        if cls._mp_season_cache is not None:
            return cls._mp_season_cache
        from datetime import date
        today = date.today()
        candidate = today.year if today.month >= 9 else today.year - 1
        year = candidate
        try:
            import requests as _rq
            r = _rq.head(cls._MP_BASE.format(year=candidate, kind="teams"),
                         headers=cls.HEADERS, timeout=10, allow_redirects=True)
            if r.status_code != 200:
                year = candidate - 1
        except Exception:
            year = candidate - 1
        cls._mp_season_cache = year
        return year

    @property
    def TEAM_DATA_URL(self) -> str:
        return self._MP_BASE.format(year=self._moneypuck_season(), kind="teams")

    @property
    def GOALIE_DATA_URL(self) -> str:
        return self._MP_BASE.format(year=self._moneypuck_season(), kind="goalies")

    @property
    def SKATER_DATA_URL(self) -> str:
        return self._MP_BASE.format(year=self._moneypuck_season(), kind="skaters")

    @property
    def LINES_DATA_URL(self) -> str:
        return self._MP_BASE.format(year=self._moneypuck_season(), kind="lines")

    # Headers to avoid 403 Forbidden from MoneyPuck
    HEADERS = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
    }

    def __init__(self, cache_dir: Optional[str] = None):
        self.cache_dir = cache_dir or os.path.dirname(__file__)
        self._team_data = None
        self._goalie_data = None
        self._skater_data = None
        self._pp_data = None
        self._pk_data = None
        # Strength-state slices for the advanced-metrics surfaces. These come
        # out of dataframes already downloaded and otherwise discarded, so they
        # cost nothing extra to keep.
        self._team_5on5 = None
        self._team_other = None
        self._skater_5on5 = None
        # lines.csv is loaded separately — see the `lines_data` property.
        self._lines_data = None
        self._lines_last_load = None
        self._injury_cache = {}
        self._confirmed_starters_cache = {}
        self._last_load_time = None

    def _fetch_csv(self, url: str, dtype: Optional[Dict] = None) -> pd.DataFrame:
        """Fetch CSV from URL with proper headers to avoid 403 errors"""
        response = requests.get(url, headers=self.HEADERS, timeout=30)
        response.raise_for_status()
        return pd.read_csv(io.StringIO(response.text), dtype=dtype)

    def load_all_data(self, force_refresh: bool = False) -> Dict:
        """Load all data from MoneyPuck"""
        # Check if we need to refresh (data older than 1 hour)
        if not force_refresh and self._last_load_time:
            if datetime.now() - self._last_load_time < timedelta(hours=1):
                return self._get_cached_data()

        try:
            # Load team data (using _fetch_csv to avoid 403 errors)
            team_data_full = self._fetch_csv(self.TEAM_DATA_URL)
            self._team_data = team_data_full[team_data_full['situation'] == 'all']
            self._pp_data = team_data_full[team_data_full['situation'] == '5on4']
            self._pk_data = team_data_full[team_data_full['situation'] == '4on5']
            # 'other' is 3-on-3 OT, 4-on-4 and empty net. Small but not
            # negligible — worth +14 goals to EDM in 2025-26 — and the goal
            # differential decomposition is only exact with it included.
            self._team_5on5 = team_data_full[team_data_full['situation'] == '5on5']
            self._team_other = team_data_full[team_data_full['situation'] == 'other']

            # Load goalie data
            goalie_data_full = self._fetch_csv(self.GOALIE_DATA_URL)
            self._goalie_data = goalie_data_full[goalie_data_full['situation'] == 'all']

            # Load skater data
            skater_data_full = self._fetch_csv(self.SKATER_DATA_URL)
            self._skater_data = skater_data_full[skater_data_full['situation'] == 'all']
            self._skater_5on5 = skater_data_full[skater_data_full['situation'] == '5on5']

            self._last_load_time = datetime.now()

            return self._get_cached_data()

        except Exception as e:
            raise Exception(f"Failed to load data from MoneyPuck: {str(e)}")

    def _get_cached_data(self) -> Dict:
        """Return cached data as dictionary"""
        return {
            'team_data': self._team_data,
            'goalie_data': self._goalie_data,
            'skater_data': self._skater_data,
            'pp_data': self._pp_data,
            'pk_data': self._pk_data,
            'team_5on5': self._team_5on5,
            'team_other': self._team_other,
            'skater_5on5': self._skater_5on5,
        }

    def scrape_injuries(self) -> Dict[str, List[str]]:
        """Scrape injury data from ESPN"""
        url = "https://www.espn.com/nhl/injuries"
        try:
            headers = {'User-Agent': 'Mozilla/5.0'}
            response = requests.get(url, headers=headers, timeout=15)
            soup = BeautifulSoup(response.text, 'html.parser')

            all_injuries = {}
            sections = soup.find_all('div', class_='ResponsiveTable')

            for section in sections:
                team_span = section.find('span', class_='injuries__teamName')
                if not team_span:
                    continue

                team_name = team_span.get_text(strip=True)
                team_abbrev = self._espn_team_to_abbrev(team_name)
                if not team_abbrev:
                    continue

                table = section.find('table')
                if not table:
                    continue

                players = []
                for row in table.find_all('tr')[1:]:
                    cells = row.find_all('td')
                    if len(cells) >= 2:
                        name = cells[0].get_text(strip=True)
                        if name:  # Include all players (goalies too)
                            players.append(name)

                if players:
                    all_injuries[team_abbrev] = players

            self._injury_cache = all_injuries
            return all_injuries

        except Exception:
            return self._injury_cache

    def _espn_team_to_abbrev(self, name: str) -> Optional[str]:
        """Convert ESPN team name to abbreviation"""
        for full_name, abbrev in ESPN_TEAM_MAPPING.items():
            if full_name.lower() in name.lower():
                return abbrev
        return None

    def get_injuries(self, team_abbrev: str) -> List[str]:
        """Get injuries for a specific team"""
        if not self._injury_cache:
            self.scrape_injuries()
        return self._injury_cache.get(team_abbrev, [])

    def scrape_confirmed_starters(self) -> Dict[str, Dict]:
        """
        Scrape starting goalies from Daily Faceoff with confirmation status.
        Returns dict mapping team abbreviation to goalie info:
        Example: {
            'TOR': {'name': 'Joseph Woll', 'confirmed': True},
            'MTL': {'name': 'Sam Montembeault', 'confirmed': False}
        }
        """
        url = "https://www.dailyfaceoff.com/starting-goalies"
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.5',
            }
            response = requests.get(url, headers=headers, timeout=15)
            soup = BeautifulSoup(response.text, 'html.parser')

            starters = {}

            # Daily Faceoff has game matchup cards
            # Each card contains two teams with their starting goalies
            # Structure varies but typically has team names/logos and goalie names

            # Try to find all links to goalie pages (reliable indicator of goalie names)
            goalie_links = soup.find_all('a', href=lambda x: x and '/goalies/' in x if x else False)

            for link in goalie_links:
                try:
                    # Get goalie name from the link text or title
                    goalie_name = link.get_text(strip=True)
                    if not goalie_name or len(goalie_name) < 3:
                        # Try getting from title attribute
                        goalie_name = link.get('title', '')

                    if not goalie_name or len(goalie_name) < 3:
                        continue

                    # Find the parent container to get team info and status
                    parent = link.find_parent(['div', 'td', 'article'])
                    if not parent:
                        continue

                    # Search for team abbreviation in parent or siblings
                    parent_text = parent.get_text()

                    # Look for confirmation status
                    # Daily Faceoff typically shows "Confirmed" or "Expected" or uses color indicators
                    is_confirmed = False
                    status_text = parent_text.lower()
                    if 'confirmed' in status_text:
                        is_confirmed = True
                    elif 'likely' in status_text or 'expected' in status_text or 'unconfirmed' in status_text:
                        is_confirmed = False

                    # Try to find team from nearby elements
                    # Look for team logo images or team name text
                    team_abbrev = None

                    # Check for team logo/link nearby
                    team_links = parent.find_all('a', href=lambda x: x and '/teams/' in x if x else False)
                    for team_link in team_links:
                        href = team_link.get('href', '')
                        # Extract team abbrev from URL like /teams/tor/
                        parts = href.strip('/').split('/')
                        for part in parts:
                            upper_part = part.upper()
                            if upper_part in DAILY_FACEOFF_TEAM_MAPPING:
                                team_abbrev = DAILY_FACEOFF_TEAM_MAPPING[upper_part]
                                break
                        if team_abbrev:
                            break

                    # Also look for team abbreviation text patterns
                    if not team_abbrev:
                        import re
                        # Look for 3-letter abbreviations
                        abbrev_pattern = re.compile(r'\b([A-Z]{2,3})\b')
                        matches = abbrev_pattern.findall(parent_text.upper())
                        for match in matches:
                            if match in DAILY_FACEOFF_TEAM_MAPPING:
                                team_abbrev = DAILY_FACEOFF_TEAM_MAPPING[match]
                                break

                    if team_abbrev and goalie_name:
                        # Only store if we don't already have this team or if this entry is confirmed
                        if team_abbrev not in starters or is_confirmed:
                            starters[team_abbrev] = {
                                'name': goalie_name,
                                'confirmed': is_confirmed
                            }

                except Exception:
                    continue

            # Alternative: Try parsing JavaScript data embedded in page
            if not starters:
                scripts = soup.find_all('script')
                for script in scripts:
                    if script.string and 'goalie' in script.string.lower():
                        try:
                            # Look for JSON-like structures
                            import re
                            # This is a fallback - page structure may have embedded data
                            json_pattern = re.compile(r'\{[^{}]*"name"[^{}]*"team"[^{}]*\}')
                            matches = json_pattern.findall(script.string)
                            for match in matches:
                                try:
                                    data = json.loads(match)
                                    # Process embedded data
                                except json.JSONDecodeError:
                                    continue
                        except Exception:
                            continue

            self._confirmed_starters_cache = starters
            return starters

        except Exception as e:
            print(f"Daily Faceoff scrape failed: {e}")
            return self._confirmed_starters_cache or {}

    def get_confirmed_starter(self, team_abbrev: str) -> Optional[str]:
        """Get starting goalie name for a team, if available from Daily Faceoff"""
        if not self._confirmed_starters_cache:
            self.scrape_confirmed_starters()
        starter_info = self._confirmed_starters_cache.get(team_abbrev)
        if starter_info:
            return starter_info.get('name')
        return None

    def get_starter_with_status(self, team_abbrev: str) -> Tuple[Optional[str], bool]:
        """
        Get starting goalie name and confirmation status for a team.
        Returns (goalie_name, is_confirmed) tuple.
        If no data available, returns (None, False).
        """
        if not self._confirmed_starters_cache:
            self.scrape_confirmed_starters()
        starter_info = self._confirmed_starters_cache.get(team_abbrev)
        if starter_info:
            return (starter_info.get('name'), starter_info.get('confirmed', False))
        return (None, False)

    @property
    def team_data(self):
        if self._team_data is None:
            self.load_all_data()
        return self._team_data

    @property
    def goalie_data(self):
        if self._goalie_data is None:
            self.load_all_data()
        return self._goalie_data

    @property
    def skater_data(self):
        if self._skater_data is None:
            self.load_all_data()
        return self._skater_data

    @property
    def pp_data(self):
        if self._pp_data is None:
            self.load_all_data()
        return self._pp_data

    @property
    def pk_data(self):
        if self._pk_data is None:
            self.load_all_data()
        return self._pk_data

    @property
    def team_5on5(self):
        if self._team_5on5 is None:
            self.load_all_data()
        return self._team_5on5

    @property
    def team_other(self):
        if self._team_other is None:
            self.load_all_data()
        return self._team_other

    @property
    def skater_5on5(self):
        if self._skater_5on5 is None:
            self.load_all_data()
        return self._skater_5on5

    @property
    def lines_data(self):
        """5-on-5 forward lines and defence pairs, or None.

        Deliberately NOT part of `load_all_data`. That method re-raises on any
        failure, so folding this in would mean a lines.csv outage — plausible in
        the autumn before MoneyPuck posts the new season's file — taking down
        every prediction in the app. Only the advanced-metrics surfaces read it,
        and they degrade to "unavailable" on their own.

        A failed fetch serves the last good frame rather than None, and an empty
        result is never cached (ARCHITECTURE §8).
        """
        fresh = (self._lines_last_load
                 and datetime.now() - self._lines_last_load < timedelta(hours=6))
        if self._lines_data is not None and fresh:
            return self._lines_data
        try:
            # lineId is a 21-digit concatenation that overflows int64, and
            # MoneyPuck wraps it in quotes — read it as text and strip.
            df = self._fetch_csv(self.LINES_DATA_URL, dtype={"lineId": str})
            if df is not None and not df.empty:
                df = df.copy()
                df["lineId"] = df["lineId"].astype(str).str.strip("'\" ")
                self._lines_data = df
                self._lines_last_load = datetime.now()
        except Exception:
            pass    # keep whatever we had; never blank out good data
        return self._lines_data


def line_player_ids(line_id) -> List[int]:
    """Split a MoneyPuck lineId into its player ids.

    The id is a plain concatenation of 7-digit NHL player ids — 3 for a forward
    line, 2 for a defence pair. Verified against the whole file: every id parsed
    this way resolves in skaters.csv. Anything that isn't a clean multiple of 7
    means the format changed upstream, so the row is skipped rather than turned
    into garbage joins.
    """
    s = str(line_id).strip("'\" ")
    if not s.isdigit() or len(s) % 7:
        return []
    return [int(s[i:i + 7]) for i in range(0, len(s), 7)]


# Global data loader instance
_data_loader: Optional[DataLoader] = None


def get_data_loader() -> DataLoader:
    """Get or create the global data loader instance"""
    global _data_loader
    if _data_loader is None:
        _data_loader = DataLoader()
    return _data_loader
