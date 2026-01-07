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
from typing import Optional, Dict, List

from .constants import ESPN_TEAM_MAPPING


class DataLoader:
    """Loads and caches data from external sources"""

    # MoneyPuck URLs for current season
    TEAM_DATA_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/teams.csv"
    GOALIE_DATA_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/goalies.csv"
    SKATER_DATA_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/skaters.csv"

    def __init__(self, cache_dir: Optional[str] = None):
        self.cache_dir = cache_dir or os.path.dirname(__file__)
        self._team_data = None
        self._goalie_data = None
        self._skater_data = None
        self._pp_data = None
        self._pk_data = None
        self._injury_cache = {}
        self._last_load_time = None

    def load_all_data(self, force_refresh: bool = False) -> Dict:
        """Load all data from MoneyPuck"""
        # Check if we need to refresh (data older than 1 hour)
        if not force_refresh and self._last_load_time:
            if datetime.now() - self._last_load_time < timedelta(hours=1):
                return self._get_cached_data()

        try:
            # Load team data
            team_data_full = pd.read_csv(self.TEAM_DATA_URL)
            self._team_data = team_data_full[team_data_full['situation'] == 'all']
            self._pp_data = team_data_full[team_data_full['situation'] == '5on4']
            self._pk_data = team_data_full[team_data_full['situation'] == '4on5']

            # Load goalie data
            goalie_data_full = pd.read_csv(self.GOALIE_DATA_URL)
            self._goalie_data = goalie_data_full[goalie_data_full['situation'] == 'all']

            # Load skater data
            skater_data_full = pd.read_csv(self.SKATER_DATA_URL)
            self._skater_data = skater_data_full[skater_data_full['situation'] == 'all']

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
                        pos = cells[1].get_text(strip=True)
                        if pos != 'G' and name:  # Exclude goalies
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


# Global data loader instance
_data_loader: Optional[DataLoader] = None


def get_data_loader() -> DataLoader:
    """Get or create the global data loader instance"""
    global _data_loader
    if _data_loader is None:
        _data_loader = DataLoader()
    return _data_loader
