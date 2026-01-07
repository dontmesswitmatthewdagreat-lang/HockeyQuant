#!/usr/bin/env python3
"""
NHL Moneyline Generator - Phase 7: Head-to-Head Matchup History
Full PyQt6 Desktop Application
Includes: xG, goaltending, fatigue/travel, hot streaks, PP/PK, injuries, H2H
"""

import sys
import requests
import pandas as pd
from datetime import datetime, timedelta
from bs4 import BeautifulSoup
import json
import os
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QGridLayout,
    QPushButton, QLabel, QProgressBar, QDateEdit, QMessageBox,
    QGraphicsOpacityEffect, QScrollArea, QFrame
)
from PyQt6.QtCore import (
    Qt, QThread, pyqtSignal, QDate, QTimer, QPropertyAnimation,
    QEasingCurve, QRect, QPoint, pyqtProperty, QSequentialAnimationGroup,
    QParallelAnimationGroup
)
from PyQt6.QtGui import (
    QFont, QColor, QPainter, QLinearGradient, QRadialGradient,
    QPen, QBrush, QPixmap
)
import random
import math


# ============================================================================
# UI STYLE CONSTANTS
# ============================================================================

COLORS = {
    'bg_dark': '#0a1628',
    'bg_gradient_top': '#0d2137',
    'bg_gradient_bottom': '#050d18',
    'accent_blue': '#2196F3',
    'accent_green': '#4CAF50',
    'accent_yellow': '#FFD700',
    'text_primary': '#ffffff',
    'text_secondary': '#7eb8da',
    'glow': '#4CAF50',
}


# ============================================================================
# CONSTANTS
# ============================================================================

TEAM_TIMEZONES = {
    'VAN': -8, 'SEA': -8, 'LAK': -8, 'ANA': -8, 'SJS': -8,
    'CGY': -7, 'EDM': -7, 'COL': -7, 'UTA': -7,
    'DAL': -6, 'MIN': -6, 'WPG': -6, 'CHI': -6, 'STL': -6, 'NSH': -6,
    'TOR': -5, 'BOS': -5, 'BUF': -5, 'DET': -5, 'MTL': -5, 'OTT': -5,
    'NYR': -5, 'NYI': -5, 'NJD': -5, 'PHI': -5, 'PIT': -5, 'WSH': -5,
    'CAR': -5, 'CBJ': -5, 'FLA': -5, 'TBL': -5,
}

NHL_DIVISIONS = {
    'Atlantic': ['BOS', 'BUF', 'DET', 'FLA', 'MTL', 'OTT', 'TBL', 'TOR'],
    'Metropolitan': ['CAR', 'CBJ', 'NJD', 'NYI', 'NYR', 'PHI', 'PIT', 'WSH'],
    'Central': ['CHI', 'COL', 'DAL', 'MIN', 'NSH', 'STL', 'WPG', 'UTA'],
    'Pacific': ['ANA', 'CGY', 'EDM', 'LAK', 'SJS', 'SEA', 'VAN', 'VGK'],
}

NHL_CONFERENCES = {
    'Eastern': ['Atlantic', 'Metropolitan'],
    'Western': ['Central', 'Pacific'],
}

TEAM_NAMES_DF = {
    'ANA': 'anaheim-ducks', 'BOS': 'boston-bruins', 'BUF': 'buffalo-sabres',
    'CGY': 'calgary-flames', 'CAR': 'carolina-hurricanes', 'CHI': 'chicago-blackhawks',
    'COL': 'colorado-avalanche', 'CBJ': 'columbus-blue-jackets', 'DAL': 'dallas-stars',
    'DET': 'detroit-red-wings', 'EDM': 'edmonton-oilers', 'FLA': 'florida-panthers',
    'LAK': 'los-angeles-kings', 'MIN': 'minnesota-wild', 'MTL': 'montreal-canadiens',
    'NSH': 'nashville-predators', 'NJD': 'new-jersey-devils', 'NYI': 'new-york-islanders',
    'NYR': 'new-york-rangers', 'OTT': 'ottawa-senators', 'PHI': 'philadelphia-flyers',
    'PIT': 'pittsburgh-penguins', 'SJS': 'san-jose-sharks', 'SEA': 'seattle-kraken',
    'STL': 'st-louis-blues', 'TBL': 'tampa-bay-lightning', 'TOR': 'toronto-maple-leafs',
    'UTA': 'utah-hockey-club', 'VAN': 'vancouver-canucks', 'VGK': 'vegas-golden-knights',
    'WSH': 'washington-capitals', 'WPG': 'winnipeg-jets',
}

INJURY_CACHE_FILE = os.path.join(os.path.dirname(__file__), "injury_cache.json")


def get_nhl_seasons():
    """Get current and previous NHL season codes based on current date"""
    today = datetime.now()
    if today.month >= 10:
        current_year = today.year
    else:
        current_year = today.year - 1
    current_season = f"{current_year}{current_year + 1}"
    previous_season = f"{current_year - 1}{current_year}"
    return current_season, previous_season


# ============================================================================
# NHL ANALYZER CLASS
# ============================================================================

class NHLAnalyzer:
    def __init__(self, team_data, goalie_data, pp_data, pk_data, skater_data):
        self.base_url = "https://api-web.nhle.com/v1"
        self.team_data = team_data
        self.goalie_data = goalie_data
        self.pp_data = pp_data
        self.pk_data = pk_data
        self.skater_data = skater_data
        self.injury_cache = self._load_injury_cache()
        # Runtime caches to reduce API calls
        self._standings_cache = None
        self._schedule_cache = {}
        self._team_schedule_cache = {}
        # Goalie IR tracking for 1-game delay after return
        self._goalie_ir_cache = self._load_goalie_ir_cache()
        self._recently_returned_goalies = {}  # Goalies who just came off IR

    def clear_runtime_caches(self):
        """Clear caches for a fresh analysis run"""
        self._standings_cache = None
        self._schedule_cache = {}
        self._team_schedule_cache = {}

    def _load_injury_cache(self):
        try:
            if os.path.exists(INJURY_CACHE_FILE):
                with open(INJURY_CACHE_FILE, 'r') as f:
                    return json.load(f)
        except:
            pass
        return {}

    def _save_injury_cache(self):
        try:
            with open(INJURY_CACHE_FILE, 'w') as f:
                json.dump(self.injury_cache, f, indent=2)
        except:
            pass

    def _load_goalie_ir_cache(self):
        """Load previous goalie IR status to detect recently returned goalies"""
        try:
            cache_file = os.path.join(os.path.dirname(__file__), "goalie_ir_cache.json")
            if os.path.exists(cache_file):
                with open(cache_file, 'r') as f:
                    return json.load(f)
        except:
            pass
        return {}

    def _save_goalie_ir_cache(self, current_goalies_on_ir):
        """Save current goalie IR status for future comparison"""
        try:
            cache_file = os.path.join(os.path.dirname(__file__), "goalie_ir_cache.json")
            with open(cache_file, 'w') as f:
                json.dump(current_goalies_on_ir, f, indent=2)
        except:
            pass

    def get_team_stats(self, team_abbrev):
        # Use cached standings if available
        if self._standings_cache is None:
            url = f"{self.base_url}/standings/now"
            try:
                response = requests.get(url, timeout=10)
                data = response.json()
                self._standings_cache = data.get('standings', [])
            except:
                return None

        for team in self._standings_cache:
            if team.get('teamAbbrev', {}).get('default') == team_abbrev:
                return team
        return None

    def get_recent_games(self, team_abbrev, lookback_days=7):
        """Get recent games using cached schedule data"""
        today = datetime.now()
        games = []

        # Use team schedule endpoint - 1 API call instead of 7
        cache_key = team_abbrev
        if cache_key not in self._team_schedule_cache:
            url = f"{self.base_url}/club-schedule-season/{team_abbrev}/now"
            try:
                response = requests.get(url, timeout=10)
                data = response.json()
                self._team_schedule_cache[cache_key] = data.get('games', [])
            except:
                self._team_schedule_cache[cache_key] = []

        for game in self._team_schedule_cache[cache_key]:
            if game.get('gameState') not in ['OFF', 'FINAL']:
                continue
            game_date_str = game.get('gameDate', '')[:10]
            try:
                game_date = datetime.strptime(game_date_str, '%Y-%m-%d')
                days_ago = (today - game_date).days
                if days_ago < 1 or days_ago > lookback_days:
                    continue
                home_team = game.get('homeTeam', {}).get('abbrev')
                away_team = game.get('awayTeam', {}).get('abbrev')
                if home_team == team_abbrev:
                    games.append({'date': game_date_str, 'home_away': 'home', 'opponent': away_team, 'days_ago': days_ago})
                elif away_team == team_abbrev:
                    games.append({'date': game_date_str, 'home_away': 'away', 'opponent': home_team, 'days_ago': days_ago})
            except:
                continue

        return sorted(games, key=lambda x: x['days_ago'])

    def get_last_10_games(self, team_abbrev):
        """Get last 10 games using cached team schedule"""
        # Use cached team schedule
        if team_abbrev not in self._team_schedule_cache:
            url = f"{self.base_url}/club-schedule-season/{team_abbrev}/now"
            try:
                response = requests.get(url, timeout=10)
                data = response.json()
                self._team_schedule_cache[team_abbrev] = data.get('games', [])
            except:
                self._team_schedule_cache[team_abbrev] = []

        completed_games = []
        for game in self._team_schedule_cache[team_abbrev]:
            if game.get('gameState') in ['OFF', 'FINAL']:
                home_team = game.get('homeTeam', {})
                away_team = game.get('awayTeam', {})
                is_home = home_team.get('abbrev') == team_abbrev
                if is_home:
                    gf, ga = home_team.get('score', 0), away_team.get('score', 0)
                    opp = away_team.get('abbrev', 'UNK')
                else:
                    gf, ga = away_team.get('score', 0), home_team.get('score', 0)
                    opp = home_team.get('abbrev', 'UNK')
                if gf > ga:
                    result = 'W'
                else:
                    period = game.get('periodDescriptor', {}).get('number', 3)
                    result = 'OTL' if period > 3 else 'L'
                completed_games.append({'date': game.get('gameDate', ''), 'opponent': opp, 'result': result, 'goals_for': gf, 'goals_against': ga})

        completed_games.sort(key=lambda x: x['date'], reverse=True)
        return completed_games[:10]

    def calculate_fatigue_penalty(self, team_abbrev, opponent_abbrev, is_away):
        recent_games = self.get_recent_games(team_abbrev)
        if not recent_games:
            return 1.0, "No recent data"

        last_game = recent_games[0]
        days_since = last_game['days_ago']
        mult = 1.0
        reasons = []

        if days_since == 1:
            mult *= 0.96
            reasons.append("B2B (-4%)")
            if last_game['home_away'] == 'away' and is_away:
                mult *= 0.98
                reasons.append("Away B2B (-2%)")
        elif days_since == 2:
            mult *= 0.98
            reasons.append("1 day rest (-2%)")
        elif days_since >= 4:
            mult *= 1.01
            reasons.append("Well rested (+1%)")

        away_games = [g for g in recent_games if g['home_away'] == 'away']
        home_games = [g for g in recent_games if g['home_away'] == 'home']
        away_count = len(away_games)
        home_count = len(home_games)

        if len(recent_games) >= 3:
            sorted_games = sorted(recent_games, key=lambda x: x['days_ago'])
            alternations = sum(1 for i in range(len(sorted_games) - 1) if sorted_games[i]['home_away'] != sorted_games[i+1]['home_away'])
            if alternations >= 2 and away_count >= 2:
                mult *= 0.97
                reasons.append(f"Choppy travel")
            elif away_count >= 3 and alternations <= 1:
                mult *= 0.98
                reasons.append(f"Road trip")
            elif away_count == 2 and home_count >= 1:
                mult *= 0.99
                reasons.append(f"Mixed schedule")

        if home_count >= 3 and away_count == 0:
            mult *= 1.02
            reasons.append(f"Homestand (+2%)")

        if is_away and recent_games:
            team_tz = TEAM_TIMEZONES.get(team_abbrev, -5)
            from_tz = TEAM_TIMEZONES.get(last_game['opponent'], -5) if last_game['home_away'] == 'away' else team_tz
            to_tz = TEAM_TIMEZONES.get(opponent_abbrev, -5)
            tz_diff = to_tz - from_tz
            if abs(tz_diff) >= 3:
                mult *= 0.97
                reasons.append(f"Cross-country")

        summary = ", ".join(reasons) if reasons else f"{days_since} days rest"
        return mult, summary

    def calculate_streak_multiplier(self, team_abbrev, stats):
        last_10 = self.get_last_10_games(team_abbrev)
        if len(last_10) < 5:
            return 1.0, "Insufficient data", {}

        wins = sum(1 for g in last_10 if g['result'] == 'W')
        losses = sum(1 for g in last_10 if g['result'] == 'L')
        otl = sum(1 for g in last_10 if g['result'] == 'OTL')
        gf = sum(g['goals_for'] for g in last_10)
        ga = sum(g['goals_against'] for g in last_10)

        recent_win_pct = (wins + otl * 0.5) / len(last_10)
        recent_gf_pg = gf / len(last_10)
        recent_ga_pg = ga / len(last_10)

        season_wins = stats.get('wins', 0)
        season_losses = stats.get('losses', 0)
        season_otl = stats.get('otLosses', 0)
        season_gf = stats.get('goalFor', 0)
        season_ga = stats.get('goalAgainst', 0)
        total = season_wins + season_losses + season_otl
        if total == 0:
            return 1.0, "No season data", {}

        season_win_pct = (season_wins + season_otl * 0.5) / total
        season_gf_pg = season_gf / total
        season_ga_pg = season_ga / total

        form_diff = recent_win_pct - season_win_pct
        mult = 1.0
        reasons = []

        if form_diff >= 0.15:
            mult = 1.05
            reasons.append(f"Hot")
        elif form_diff >= 0.10:
            mult = 1.03
            reasons.append(f"Warming")
        elif form_diff <= -0.15:
            mult = 0.95
            reasons.append(f"Cold")
        elif form_diff <= -0.10:
            mult = 0.97
            reasons.append(f"Cooling")

        gf_diff = recent_gf_pg - season_gf_pg
        if gf_diff >= 0.5:
            mult *= 1.02
        elif gf_diff >= 0.3:
            mult *= 1.01
        elif gf_diff <= -0.5:
            mult *= 0.98
        elif gf_diff <= -0.3:
            mult *= 0.99

        ga_diff = recent_ga_pg - season_ga_pg
        if ga_diff <= -0.5:
            mult *= 1.02
        elif ga_diff <= -0.3:
            mult *= 1.01
        elif ga_diff >= 0.5:
            mult *= 0.98
        elif ga_diff >= 0.3:
            mult *= 0.99

        consec_w = consec_l = 0
        for g in last_10:
            if g['result'] == 'W':
                if consec_l == 0:
                    consec_w += 1
                else:
                    break
            else:
                if consec_w == 0:
                    consec_l += 1
                else:
                    break

        if consec_w >= 5:
            mult *= 1.02
            reasons.append(f"{consec_w}W streak")
        elif consec_l >= 5:
            mult *= 0.98
            reasons.append(f"{consec_l}L streak")

        record = f"{wins}-{losses}-{otl}"
        summary = f"{record} L10" + (f" ({', '.join(reasons)})" if reasons else "")
        return mult, summary, {'record': record}

    def get_special_teams_stats(self, team_abbrev):
        if self.pp_data is None or self.pk_data is None:
            return None
        team_all = self.team_data[self.team_data['team'] == team_abbrev]
        team_pp = self.pp_data[self.pp_data['team'] == team_abbrev]
        team_pk = self.pk_data[self.pk_data['team'] == team_abbrev]
        if team_all.empty or team_pp.empty or team_pk.empty:
            return None
        games = float(team_all.iloc[0]['games_played'])
        pen_drawn = float(team_all.iloc[0]['penaltiesAgainst'])
        pen_taken = float(team_all.iloc[0]['penaltiesFor'])
        pp_goals = float(team_pp.iloc[0]['goalsFor'])
        pk_ga = float(team_pk.iloc[0]['goalsAgainst'])
        return {
            'pp_pct': pp_goals / pen_drawn if pen_drawn > 0 else 0.20,
            'pk_pct': 1 - (pk_ga / pen_taken) if pen_taken > 0 else 0.80,
            'pk_situations_per_game': pen_taken / games if games > 0 else 3.0,
        }

    def calculate_special_teams_multiplier(self, team_abbrev, opponent_abbrev):
        team_st = self.get_special_teams_stats(team_abbrev)
        opp_st = self.get_special_teams_stats(opponent_abbrev)
        if not team_st or not opp_st:
            return 1.0, "No ST data"

        opp_pk_weak = 1 - opp_st['pk_pct']
        pp_edge = team_st['pp_pct'] - opp_pk_weak
        pp_impact = pp_edge * opp_st['pk_situations_per_game']
        pk_edge = team_st['pk_pct'] - (1 - opp_st['pp_pct'])
        pk_impact = pk_edge * opp_st['pk_situations_per_game']
        net_edge = pp_impact + pk_impact
        mult = 1.0 + (net_edge * 0.015)
        mult = max(0.95, min(1.05, mult))

        reasons = []
        if team_st['pp_pct'] > 0.22:
            reasons.append(f"PP {team_st['pp_pct']*100:.0f}%")
        elif team_st['pp_pct'] < 0.17:
            reasons.append(f"PP {team_st['pp_pct']*100:.0f}%")
        if opp_st['pk_pct'] < 0.78:
            reasons.append(f"vs PK {opp_st['pk_pct']*100:.0f}%")
        elif opp_st['pk_pct'] > 0.82:
            reasons.append(f"vs PK {opp_st['pk_pct']*100:.0f}%")

        summary = ", ".join(reasons) if reasons else "Neutral ST"
        return mult, summary

    def scrape_all_injuries(self):
        url = "https://www.espn.com/nhl/injuries"
        try:
            headers = {'User-Agent': 'Mozilla/5.0'}
            response = requests.get(url, headers=headers, timeout=15)
            soup = BeautifulSoup(response.text, 'html.parser')
            all_injuries = {}
            current_goalies_on_ir = {}  # Track goalies currently on IR
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
                goalies_on_ir = []
                for row in table.find_all('tr')[1:]:
                    cells = row.find_all('td')
                    if len(cells) >= 2:
                        name = cells[0].get_text(strip=True)
                        pos = cells[1].get_text(strip=True)
                        if pos == 'G' and name:
                            goalies_on_ir.append(name)
                        elif name:
                            players.append(name)
                if players:
                    all_injuries[team_abbrev] = players
                    self.injury_cache[team_abbrev] = {'injuries': players, 'timestamp': datetime.now().isoformat()}
                if goalies_on_ir:
                    current_goalies_on_ir[team_abbrev] = goalies_on_ir

            # Detect goalies who just came off IR (were on IR before, not anymore)
            self._recently_returned_goalies = {}
            for team, prev_goalies in self._goalie_ir_cache.items():
                current_ir = current_goalies_on_ir.get(team, [])
                for goalie in prev_goalies:
                    if goalie not in current_ir:
                        # This goalie was on IR but is no longer - just returned
                        if team not in self._recently_returned_goalies:
                            self._recently_returned_goalies[team] = []
                        self._recently_returned_goalies[team].append(goalie)

            # Save current goalie IR status for next comparison
            self._goalie_ir_cache = current_goalies_on_ir
            self._save_goalie_ir_cache(current_goalies_on_ir)
            self._save_injury_cache()
            return all_injuries
        except:
            return {}

    def _espn_team_to_abbrev(self, name):
        mapping = {
            'Anaheim Ducks': 'ANA', 'Boston Bruins': 'BOS', 'Buffalo Sabres': 'BUF',
            'Calgary Flames': 'CGY', 'Carolina Hurricanes': 'CAR', 'Chicago Blackhawks': 'CHI',
            'Colorado Avalanche': 'COL', 'Columbus Blue Jackets': 'CBJ', 'Dallas Stars': 'DAL',
            'Detroit Red Wings': 'DET', 'Edmonton Oilers': 'EDM', 'Florida Panthers': 'FLA',
            'Los Angeles Kings': 'LAK', 'Minnesota Wild': 'MIN', 'Montreal Canadiens': 'MTL',
            'Nashville Predators': 'NSH', 'New Jersey Devils': 'NJD', 'New York Islanders': 'NYI',
            'New York Rangers': 'NYR', 'Ottawa Senators': 'OTT', 'Philadelphia Flyers': 'PHI',
            'Pittsburgh Penguins': 'PIT', 'San Jose Sharks': 'SJS', 'Seattle Kraken': 'SEA',
            'St. Louis Blues': 'STL', 'Tampa Bay Lightning': 'TBL', 'Toronto Maple Leafs': 'TOR',
            'Utah Hockey Club': 'UTA', 'Vancouver Canucks': 'VAN', 'Vegas Golden Knights': 'VGK',
            'Washington Capitals': 'WSH', 'Winnipeg Jets': 'WPG',
        }
        for full_name, abbrev in mapping.items():
            if full_name.lower() in name.lower():
                return abbrev
        return None

    def get_team_injuries(self, team_abbrev):
        if team_abbrev in self.injury_cache:
            cached = self.injury_cache[team_abbrev]
            try:
                cached_time = datetime.fromisoformat(cached['timestamp'])
                if datetime.now() - cached_time < timedelta(hours=2):
                    return cached.get('injuries', [])
            except:
                pass
        all_injuries = self.scrape_all_injuries()
        return all_injuries.get(team_abbrev, [])

    def get_player_importance(self, player_name, team_abbrev):
        if self.skater_data is None:
            return 15
        player_lower = player_name.lower()
        team_players = self.skater_data[self.skater_data['team'] == team_abbrev]
        matched = None
        for _, p in team_players.iterrows():
            if player_lower in str(p.get('name', '')).lower():
                matched = p
                break
        if matched is None:
            last = player_name.split()[-1].lower() if player_name else ''
            for _, p in team_players.iterrows():
                if last in str(p.get('name', '')).lower():
                    matched = p
                    break
        if matched is None:
            return 15
        pts = float(matched.get('I_F_goals', 0)) + float(matched.get('I_F_primaryAssists', 0)) + float(matched.get('I_F_secondaryAssists', 0))
        toi = float(matched.get('icetime', 0)) / 3600
        xgf = float(matched.get('xGoalsFor', 0))
        importance = (min(1, pts/100)*0.4 + min(1, toi/30)*0.35 + min(1, xgf/60)*0.25) * 100
        return min(100, importance)

    def calculate_injury_multiplier(self, team_abbrev):
        injuries = self.get_team_injuries(team_abbrev)
        if not injuries:
            return 1.0, "Healthy", {}
        total = sum(self.get_player_importance(p, team_abbrev) for p in injuries)
        mult = max(0.90, 1.0 - total * 0.0005)
        summary = f"{len(injuries)} out" if len(injuries) > 2 else ", ".join(injuries[:2])
        return mult, summary, {'count': len(injuries), 'total_impact': total}

    def get_team_relationship(self, team1, team2):
        team1_div = team2_div = None
        team1_conf = team2_conf = None
        for div, teams in NHL_DIVISIONS.items():
            if team1 in teams:
                team1_div = div
            if team2 in teams:
                team2_div = div
        for conf, divs in NHL_CONFERENCES.items():
            if team1_div in divs:
                team1_conf = conf
            if team2_div in divs:
                team2_conf = conf
        if team1_div == team2_div:
            return 'same_division', 8
        elif team1_conf == team2_conf:
            return 'same_conference', 6
        else:
            return 'different_conference', 4

    def get_head_to_head_history(self, team1, team2, num_games):
        """Get H2H history using cached schedule data"""
        current_season, previous_season = get_nhl_seasons()
        all_games = []

        for season in [current_season, previous_season]:
            cache_key = f"{team1}_{season}"
            if cache_key not in self._team_schedule_cache:
                url = f"{self.base_url}/club-schedule-season/{team1}/{season}"
                try:
                    response = requests.get(url, timeout=10)
                    data = response.json()
                    self._team_schedule_cache[cache_key] = data.get('games', [])
                except:
                    self._team_schedule_cache[cache_key] = []

            for game in self._team_schedule_cache[cache_key]:
                if game.get('gameState') not in ['OFF', 'FINAL']:
                    continue
                home = game.get('homeTeam', {})
                away = game.get('awayTeam', {})
                home_abbrev = home.get('abbrev', '')
                away_abbrev = away.get('abbrev', '')
                if team2 not in [home_abbrev, away_abbrev]:
                    continue
                home_score = home.get('score', 0)
                away_score = away.get('score', 0)
                if home_abbrev == team1:
                    team1_gf, team1_ga = home_score, away_score
                else:
                    team1_gf, team1_ga = away_score, home_score
                all_games.append({
                    'date': game.get('gameDate', ''),
                    'team1_goals': team1_gf,
                    'team2_goals': team1_ga,
                    'team1_won': team1_gf > team1_ga,
                    'goal_diff': team1_gf - team1_ga
                })

        all_games.sort(key=lambda x: x['date'], reverse=True)
        return all_games[:num_games]

    def calculate_h2h_multiplier(self, team_abbrev, opponent_abbrev):
        relationship, num_games = self.get_team_relationship(team_abbrev, opponent_abbrev)
        games = self.get_head_to_head_history(team_abbrev, opponent_abbrev, num_games)
        if len(games) < 2:
            return 1.0, "No H2H data", {}
        wins = sum(1 for g in games if g['team1_won'])
        total = len(games)
        total_gd = sum(g['goal_diff'] for g in games)
        win_pct = wins / total
        avg_gd = total_gd / total
        win_bonus = (win_pct - 0.5) * 0.08
        gd_bonus = avg_gd * 0.01
        multiplier = 1.0 + win_bonus + gd_bonus
        multiplier = max(0.94, min(1.06, multiplier))
        summary = f"{wins}-{total - wins} ({avg_gd:+.1f} GD)"
        return multiplier, summary, {'wins': wins, 'losses': total - wins, 'avg_gd': avg_gd}

    def get_team_xg(self, team_abbrev):
        if self.team_data is None:
            return None
        row = self.team_data[self.team_data['team'] == team_abbrev]
        if not row.empty:
            return {'xGoalsFor': float(row.iloc[0]['xGoalsFor']), 'xGoalsAgainst': float(row.iloc[0]['xGoalsAgainst'])}
        return None

    def get_starting_goalie(self, team_abbrev):
        if self.goalie_data is None:
            return None
        team_goalies = self.goalie_data[self.goalie_data['team'] == team_abbrev]
        if team_goalies.empty:
            return None
        qualified = team_goalies[team_goalies['games_played'] >= 5]
        if qualified.empty:
            qualified = team_goalies

        # Get top 2 goalies by games played
        top_goalies = qualified.nlargest(2, 'games_played')
        starter = top_goalies.iloc[0]

        # Check if starter just came off IR (1-game delay rule)
        recently_returned = self._recently_returned_goalies.get(team_abbrev, [])
        if recently_returned and starter['name'] in recently_returned:
            # Starter just came off IR - use backup if available
            if len(top_goalies) > 1:
                starter = top_goalies.iloc[1]  # Use backup

        xGoals = float(starter['xGoals'])
        goals = float(starter['goals'])
        ongoal = float(starter['ongoal'])
        icetime = float(starter['icetime'])
        gsax = xGoals - goals
        sv_pct = (ongoal - goals) / ongoal if ongoal > 0 else 0.900
        gaa = (goals / (icetime/60)) * 60 if icetime > 0 else 3.0
        return {'name': starter['name'], 'gsax': gsax, 'sv_pct': sv_pct, 'gaa': gaa}

    def get_backup_goalie(self, team_abbrev):
        """Get the backup goalie for a team (2nd by games played)"""
        if self.goalie_data is None:
            return None
        team_goalies = self.goalie_data[self.goalie_data['team'] == team_abbrev]
        if team_goalies.empty or len(team_goalies) < 2:
            return None
        qualified = team_goalies[team_goalies['games_played'] >= 3]
        if len(qualified) < 2:
            qualified = team_goalies

        # Get top 2 goalies by games played
        top_goalies = qualified.nlargest(2, 'games_played')
        if len(top_goalies) < 2:
            return None

        backup = top_goalies.iloc[1]
        xGoals = float(backup['xGoals'])
        goals = float(backup['goals'])
        ongoal = float(backup['ongoal'])
        icetime = float(backup['icetime'])
        gsax = xGoals - goals
        sv_pct = (ongoal - goals) / ongoal if ongoal > 0 else 0.900
        gaa = (goals / (icetime/60)) * 60 if icetime > 0 else 3.0
        return {'name': backup['name'], 'gsax': gsax, 'sv_pct': sv_pct, 'gaa': gaa}

    def calculate_goalie_score(self, goalie):
        if not goalie:
            return 0.5
        gsax_norm = max(0, min(1, 0.5 + goalie['gsax']/40))
        sv_norm = max(0, min(1, (goalie['sv_pct'] - 0.890) / 0.040))
        gaa_norm = max(0, min(1, 1 - (goalie['gaa'] - 2.0) / 2.0))
        return gsax_norm * 0.50 + sv_norm * 0.30 + gaa_norm * 0.20

    def analyze_team(self, team_abbrev, opponent_abbrev, is_away):
        stats = self.get_team_stats(team_abbrev)
        if not stats:
            return None

        wins = stats.get('wins', 0)
        losses = stats.get('losses', 0)
        otl = stats.get('otLosses', 0)
        points = stats.get('points', 0)
        gf = stats.get('goalFor', 0)
        ga = stats.get('goalAgainst', 0)

        total = wins + losses + otl
        if total == 0:
            return None

        win_pct = (wins + otl * 0.5) / total
        pts_pct = points / (total * 2)

        xg = self.get_team_xg(team_abbrev)
        xgf_pct = xg['xGoalsFor'] / (xg['xGoalsFor'] + xg['xGoalsAgainst']) if xg else 0.5
        gf_pct = gf / (gf + ga) if (gf + ga) > 0 else 0.5
        off_quality = xgf_pct * 0.8 + gf_pct * 0.2

        # Defensive quality - lower xGA% and GA% is better (inverted)
        xga_pct = xg['xGoalsAgainst'] / (xg['xGoalsFor'] + xg['xGoalsAgainst']) if xg else 0.5
        ga_pct = ga / (gf + ga) if (gf + ga) > 0 else 0.5
        def_quality = (1 - xga_pct) * 0.8 + (1 - ga_pct) * 0.2

        goalie = self.get_starting_goalie(team_abbrev)
        backup_goalie = self.get_backup_goalie(team_abbrev)
        goalie_score = self.calculate_goalie_score(goalie)

        base_score = off_quality * 40 + def_quality * 15 + pts_pct * 10 + goalie_score * 30 + win_pct * 5

        fatigue_mult, fatigue_sum = self.calculate_fatigue_penalty(team_abbrev, opponent_abbrev, is_away)
        streak_mult, streak_sum, _ = self.calculate_streak_multiplier(team_abbrev, stats)
        st_mult, st_sum = self.calculate_special_teams_multiplier(team_abbrev, opponent_abbrev)
        injury_mult, injury_sum, _ = self.calculate_injury_multiplier(team_abbrev)
        h2h_mult, h2h_sum, _ = self.calculate_h2h_multiplier(team_abbrev, opponent_abbrev)

        final_score = base_score * fatigue_mult * streak_mult * st_mult * injury_mult * h2h_mult

        return {
            'team': team_abbrev,
            'base_score': base_score,
            'final_score': final_score,
            'goalie': goalie['name'] if goalie else 'Unknown',
            'goalie_gsax': goalie['gsax'] if goalie else 0,
            'goalie_sv_pct': goalie['sv_pct'] if goalie else 0.900,
            'goalie_gaa': goalie['gaa'] if goalie else 3.0,
            'backup_goalie': backup_goalie['name'] if backup_goalie else None,
            'backup_goalie_gsax': backup_goalie['gsax'] if backup_goalie else 0,
            'backup_goalie_sv_pct': backup_goalie['sv_pct'] if backup_goalie else 0.900,
            'backup_goalie_gaa': backup_goalie['gaa'] if backup_goalie else 3.0,
            'fatigue': fatigue_sum,
            'fatigue_mult': fatigue_mult,
            'streak': streak_sum,
            'streak_mult': streak_mult,
            'special_teams': st_sum,
            'st_mult': st_mult,
            'injuries': injury_sum,
            'injury_mult': injury_mult,
            'h2h': h2h_sum,
            'h2h_mult': h2h_mult,
        }

    def get_games_for_date(self, date_str):
        url = f"{self.base_url}/schedule/{date_str}"
        games = []
        try:
            response = requests.get(url, timeout=10)
            data = response.json()
            if 'gameWeek' in data:
                for day in data['gameWeek']:
                    if day.get('date') == date_str and 'games' in day:
                        for game in day['games']:
                            away = game.get('awayTeam', {}).get('abbrev')
                            home = game.get('homeTeam', {}).get('abbrev')
                            if away and home:
                                games.append({'away': away, 'home': home})
        except:
            pass
        return games


# ============================================================================
# DATA LOADER THREAD
# ============================================================================

class DataLoader(QThread):
    finished = pyqtSignal(dict)
    status = pyqtSignal(str)
    error = pyqtSignal(str)

    def run(self):
        data = {}
        try:
            self.status.emit("Loading team data from MoneyPuck...")
            TEAM_XG_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/teams.csv"
            TEAM_DATA_FULL = pd.read_csv(TEAM_XG_URL)
            data['team_data'] = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == 'all']
            data['pp_data'] = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == '5on4']
            data['pk_data'] = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == '4on5']

            self.status.emit("Loading goalie data...")
            GOALIE_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/goalies.csv"
            GOALIE_DATA = pd.read_csv(GOALIE_URL)
            data['goalie_data'] = GOALIE_DATA[GOALIE_DATA['situation'] == 'all']

            self.status.emit("Loading skater data...")
            SKATER_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/skaters.csv"
            SKATER_DATA = pd.read_csv(SKATER_URL)
            data['skater_data'] = SKATER_DATA[SKATER_DATA['situation'] == 'all']

            self.finished.emit(data)
        except Exception as e:
            self.error.emit(str(e))


# ============================================================================
# ANALYSIS WORKER THREAD
# ============================================================================

class AnalysisWorker(QThread):
    progress = pyqtSignal(int, str)
    result = pyqtSignal(list)
    error = pyqtSignal(str)

    def __init__(self, analyzer, date_str):
        super().__init__()
        self.analyzer = analyzer
        self.date_str = date_str

    def run(self):
        try:
            # Clear caches for fresh data
            self.analyzer.clear_runtime_caches()

            self.progress.emit(5, "Fetching schedule...")
            games = self.analyzer.get_games_for_date(self.date_str)

            if not games:
                self.error.emit(f"No games found for {self.date_str}")
                return

            self.progress.emit(10, f"Found {len(games)} games. Loading injuries...")
            self.analyzer.scrape_all_injuries()

            results = []
            total = len(games)

            for i, game in enumerate(games):
                try:
                    pct = 10 + int(((i + 1) / total) * 85)
                    self.progress.emit(pct, f"Analyzing {game['away']} @ {game['home']} ({i+1}/{total})...")

                    away_data = self.analyzer.analyze_team(game['away'], game['home'], is_away=True)
                    home_data = self.analyzer.analyze_team(game['home'], game['away'], is_away=False)

                    if away_data and home_data:
                        diff = home_data['final_score'] - away_data['final_score']
                        pick = home_data['team'] if diff > 0 else away_data['team']
                        results.append({
                            'away': away_data,
                            'home': home_data,
                            'pick': pick,
                            'diff': abs(diff),
                        })
                except Exception as game_error:
                    # Skip failed games but continue with others
                    print(f"Error analyzing {game['away']} @ {game['home']}: {game_error}")
                    continue

            self.progress.emit(100, f"Complete! Analyzed {len(results)}/{total} games")
            self.result.emit(results)

        except Exception as e:
            import traceback
            traceback.print_exc()
            self.error.emit(str(e))


# ============================================================================
# PARTICLE CLASS FOR LOADING SCREEN
# ============================================================================

class Particle:
    """A floating particle for the loading screen background"""
    def __init__(self, width, height):
        self.x = random.uniform(0, width)
        self.y = random.uniform(0, height)
        self.size = random.uniform(2, 6)
        self.speed = random.uniform(0.3, 1.0)
        self.opacity = random.uniform(0.3, 0.8)
        self.width = width
        self.height = height
        # Slight horizontal drift
        self.drift = random.uniform(-0.2, 0.2)

    def update(self):
        self.y -= self.speed
        self.x += self.drift
        # Reset when off screen
        if self.y < -10:
            self.y = self.height + 10
            self.x = random.uniform(0, self.width)
        if self.x < -10:
            self.x = self.width + 10
        elif self.x > self.width + 10:
            self.x = -10


# ============================================================================
# PREMIUM LOADING WINDOW
# ============================================================================

class LoadingWindow(QWidget):
    """Premium animated loading screen with intro animation and slide transition"""

    # Signals
    intro_complete = pyqtSignal()
    ready_for_transition = pyqtSignal()

    def __init__(self):
        super().__init__()
        self.setWindowTitle("HockeyQuant")
        self.setFixedSize(600, 450)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, False)

        # Animation state
        self._logo_opacity = 0.0
        self._logo_scale = 1.0  # No zoom effect - start at full size
        self._title_opacity = 0.0
        self._progress_opacity = 0.0
        self._particle_opacity = 0.0
        self._glow_intensity = 0.0
        self._status_text = ""
        self._progress_value = 0
        self._is_intro_complete = False
        self._show_progress = False

        # Load logo
        logo_path = os.path.join(os.path.dirname(__file__), "logo.png")
        self._logo_pixmap = QPixmap(logo_path)
        if self._logo_pixmap.isNull():
            # Fallback: create a placeholder
            self._logo_pixmap = QPixmap(200, 200)
            self._logo_pixmap.fill(QColor(COLORS['accent_green']))

        # Scale logo to target size
        self._logo_pixmap = self._logo_pixmap.scaled(
            180, 180,
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        )

        # Create particles
        self._particles = [Particle(600, 450) for _ in range(25)]

        # Animation timer for particles and glow pulse
        self._anim_timer = QTimer(self)
        self._anim_timer.timeout.connect(self._update_animations)
        self._anim_timer.start(33)  # ~30 FPS

        # Glow pulse state
        self._glow_phase = 0.0

        # Status label (invisible, used for signal connection)
        self.status = type('obj', (object,), {'setText': self._set_status})()

        # Start intro animation after a brief delay
        QTimer.singleShot(100, self._start_intro_animation)

    def _set_status(self, text):
        """Update status text"""
        self._status_text = text
        self.update()

    # Properties for animation
    def _get_logo_opacity(self):
        return self._logo_opacity
    def _set_logo_opacity(self, val):
        self._logo_opacity = val
        self.update()
    logo_opacity = pyqtProperty(float, _get_logo_opacity, _set_logo_opacity)

    def _get_logo_scale(self):
        return self._logo_scale
    def _set_logo_scale(self, val):
        self._logo_scale = val
        self.update()
    logo_scale = pyqtProperty(float, _get_logo_scale, _set_logo_scale)

    def _get_title_opacity(self):
        return self._title_opacity
    def _set_title_opacity(self, val):
        self._title_opacity = val
        self.update()
    title_opacity = pyqtProperty(float, _get_title_opacity, _set_title_opacity)

    def _get_progress_opacity(self):
        return self._progress_opacity
    def _set_progress_opacity(self, val):
        self._progress_opacity = val
        self.update()
    progress_opacity = pyqtProperty(float, _get_progress_opacity, _set_progress_opacity)

    def _get_particle_opacity(self):
        return self._particle_opacity
    def _set_particle_opacity(self, val):
        self._particle_opacity = val
        self.update()
    particle_opacity = pyqtProperty(float, _get_particle_opacity, _set_particle_opacity)

    def _get_progress_value(self):
        return self._progress_value
    def _set_progress_value(self, val):
        self._progress_value = val
        self.update()
    progress_value = pyqtProperty(float, _get_progress_value, _set_progress_value)

    def _start_intro_animation(self):
        """4-second intro animation sequence"""
        # Phase 1: Logo fade in (0-1.5s) - no zoom, just fade
        self._logo_anim_opacity = QPropertyAnimation(self, b"logo_opacity")
        self._logo_anim_opacity.setDuration(1500)
        self._logo_anim_opacity.setStartValue(0.0)
        self._logo_anim_opacity.setEndValue(1.0)
        self._logo_anim_opacity.setEasingCurve(QEasingCurve.Type.OutCubic)

        # Phase 2: Title fade in (1.5-2.5s) - starts at 1500ms
        self._title_anim = QPropertyAnimation(self, b"title_opacity")
        self._title_anim.setDuration(1000)
        self._title_anim.setStartValue(0.0)
        self._title_anim.setEndValue(1.0)
        self._title_anim.setEasingCurve(QEasingCurve.Type.OutCubic)

        # Phase 3: Particles fade in (2.5-4s) - starts at 2500ms
        self._particle_anim = QPropertyAnimation(self, b"particle_opacity")
        self._particle_anim.setDuration(1500)
        self._particle_anim.setStartValue(0.0)
        self._particle_anim.setEndValue(1.0)
        self._particle_anim.setEasingCurve(QEasingCurve.Type.OutCubic)

        # Start animations with delays
        self._logo_anim_opacity.start()
        QTimer.singleShot(1500, self._title_anim.start)
        QTimer.singleShot(2500, self._particle_anim.start)

        # After 4 seconds, emit intro complete signal
        QTimer.singleShot(4000, self._on_intro_complete)

    def _on_intro_complete(self):
        """Called when intro animation finishes"""
        self._is_intro_complete = True
        self._show_progress = True

        # Fade in progress bar
        self._progress_anim = QPropertyAnimation(self, b"progress_opacity")
        self._progress_anim.setDuration(500)
        self._progress_anim.setStartValue(0.0)
        self._progress_anim.setEndValue(1.0)
        self._progress_anim.start()

        self.intro_complete.emit()

    def _update_animations(self):
        """Called by timer to update particles and glow"""
        # Update particles
        for p in self._particles:
            p.update()

        # Update glow pulse
        self._glow_phase += 0.05
        self._glow_intensity = 0.5 + 0.3 * math.sin(self._glow_phase)

        self.update()

    def set_progress(self, value):
        """Set progress bar value (0-100) with smooth animation"""
        # Stop any existing animation
        if hasattr(self, '_progress_anim_smooth') and self._progress_anim_smooth is not None:
            self._progress_anim_smooth.stop()

        # Animate from current value to target
        self._progress_anim_smooth = QPropertyAnimation(self, b"progress_value")
        self._progress_anim_smooth.setDuration(300)
        self._progress_anim_smooth.setStartValue(self._progress_value)
        self._progress_anim_smooth.setEndValue(float(value))
        self._progress_anim_smooth.setEasingCurve(QEasingCurve.Type.OutCubic)
        self._progress_anim_smooth.start()

    def show_ready_state(self):
        """Show 'Ready!' and prepare for transition"""
        self._status_text = "Ready!"
        self.update()
        # Brief pause then signal ready for transition
        QTimer.singleShot(300, self.ready_for_transition.emit)  # Brief pause

    def paintEvent(self, event):
        """Custom paint for premium visual effects"""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        w, h = self.width(), self.height()

        # Draw gradient background
        bg_gradient = QLinearGradient(0, 0, 0, h)
        bg_gradient.setColorAt(0, QColor(COLORS['bg_gradient_top']))
        bg_gradient.setColorAt(1, QColor(COLORS['bg_gradient_bottom']))
        painter.fillRect(0, 0, w, h, bg_gradient)

        # Draw subtle radial glow in center
        center_glow = QRadialGradient(w/2, h/2 - 50, 200)
        glow_color = QColor(COLORS['glow'])
        glow_color.setAlphaF(0.15 * self._glow_intensity)
        center_glow.setColorAt(0, glow_color)
        center_glow.setColorAt(1, QColor(0, 0, 0, 0))
        painter.fillRect(0, 0, w, h, center_glow)

        # Draw particles
        if self._particle_opacity > 0:
            for p in self._particles:
                particle_color = QColor(COLORS['accent_green'])
                particle_color.setAlphaF(p.opacity * self._particle_opacity)
                painter.setPen(Qt.PenStyle.NoPen)
                painter.setBrush(particle_color)
                painter.drawEllipse(int(p.x - p.size/2), int(p.y - p.size/2),
                                   int(p.size), int(p.size))

        # Draw logo with glow effect
        if self._logo_opacity > 0:
            logo_x = (w - self._logo_pixmap.width() * self._logo_scale) / 2
            logo_y = 80

            # Draw glow behind logo
            if self._glow_intensity > 0 and self._is_intro_complete:
                glow_radius = 100 * self._glow_intensity
                logo_glow = QRadialGradient(
                    w/2, logo_y + self._logo_pixmap.height() * self._logo_scale / 2,
                    glow_radius
                )
                glow_c = QColor(COLORS['glow'])
                glow_c.setAlphaF(0.3 * self._glow_intensity * self._logo_opacity)
                logo_glow.setColorAt(0, glow_c)
                logo_glow.setColorAt(1, QColor(0, 0, 0, 0))
                painter.fillRect(0, 0, w, h, logo_glow)

            # Draw scaled logo
            painter.setOpacity(self._logo_opacity)
            scaled_logo = self._logo_pixmap.scaled(
                int(self._logo_pixmap.width() * self._logo_scale),
                int(self._logo_pixmap.height() * self._logo_scale),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation
            )
            painter.drawPixmap(int(logo_x), int(logo_y), scaled_logo)
            painter.setOpacity(1.0)

        # Draw title
        if self._title_opacity > 0:
            painter.setOpacity(self._title_opacity)
            painter.setPen(QColor(COLORS['text_primary']))
            painter.setFont(QFont("Raleway Dots", 28, QFont.Weight.Bold))
            title_rect = QRect(0, 270, w, 40)
            painter.drawText(title_rect, Qt.AlignmentFlag.AlignCenter, "HockeyQuant")

            # Version subtitle
            painter.setFont(QFont("Space Mono", 11))
            painter.setPen(QColor(COLORS['text_secondary']))
            version_rect = QRect(0, 305, w, 25)
            painter.drawText(version_rect, Qt.AlignmentFlag.AlignCenter, "Version 7.0")
            painter.setOpacity(1.0)

        # Draw progress bar
        if self._show_progress and self._progress_opacity > 0:
            painter.setOpacity(self._progress_opacity)

            bar_width = 350
            bar_height = 8
            bar_x = (w - bar_width) / 2
            bar_y = 355
            bar_radius = 4

            # Background
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(QColor(255, 255, 255, 30))
            painter.drawRoundedRect(int(bar_x), int(bar_y), bar_width, bar_height,
                                   bar_radius, bar_radius)

            # Progress fill with gradient
            if self._progress_value > 0:
                fill_width = int(bar_width * self._progress_value / 100)
                progress_gradient = QLinearGradient(bar_x, 0, bar_x + bar_width, 0)
                progress_gradient.setColorAt(0, QColor(COLORS['accent_blue']))
                progress_gradient.setColorAt(0.5, QColor(COLORS['accent_green']))
                progress_gradient.setColorAt(1, QColor(COLORS['accent_yellow']))
                painter.setBrush(progress_gradient)
                painter.drawRoundedRect(int(bar_x), int(bar_y), fill_width, bar_height,
                                       bar_radius, bar_radius)

            # Status text
            painter.setPen(QColor(COLORS['text_secondary']))
            painter.setFont(QFont("Space Mono", 11))
            status_rect = QRect(0, 375, w, 30)
            painter.drawText(status_rect, Qt.AlignmentFlag.AlignCenter, self._status_text)
            painter.setOpacity(1.0)

        painter.end()

    def start_fade_out(self, callback):
        """Fade this window out smoothly"""
        self._window_opacity = 1.0
        self._fade_anim = QPropertyAnimation(self, b"windowOpacity")
        self._fade_anim.setDuration(400)  # Quick fade out
        self._fade_anim.setStartValue(1.0)
        self._fade_anim.setEndValue(0.0)
        self._fade_anim.setEasingCurve(QEasingCurve.Type.InOutQuad)
        self._fade_anim.finished.connect(callback)
        self._fade_anim.start()


# ============================================================================
# NAVIGATION CARD WIDGET
# ============================================================================

class NavigationCard(QWidget):
    """Clickable card for home page navigation"""
    clicked = pyqtSignal()

    def __init__(self, title, description, icon_text, enabled=True, parent=None):
        super().__init__(parent)
        self.title = title
        self.description = description
        self.icon_text = icon_text
        self.enabled = enabled
        self._hovered = False

        self.setFixedSize(280, 160)
        self.setCursor(Qt.CursorShape.PointingHandCursor if enabled else Qt.CursorShape.ArrowCursor)
        self.setMouseTracking(True)

    def enterEvent(self, event):
        if self.enabled:
            self._hovered = True
            self.update()

    def leaveEvent(self, event):
        self._hovered = False
        self.update()

    def mousePressEvent(self, event):
        if self.enabled and event.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        w, h = self.width(), self.height()

        # Card background
        if self.enabled and self._hovered:
            bg_color = QColor(255, 255, 255, 25)
            border_color = QColor(COLORS['accent_green'])
        elif self.enabled:
            bg_color = QColor(255, 255, 255, 15)
            border_color = QColor(255, 255, 255, 40)
        else:
            bg_color = QColor(255, 255, 255, 8)
            border_color = QColor(255, 255, 255, 20)

        # Draw rounded rect background
        painter.setPen(QPen(border_color, 2))
        painter.setBrush(bg_color)
        painter.drawRoundedRect(1, 1, w-2, h-2, 12, 12)

        # Draw glow effect on hover
        if self.enabled and self._hovered:
            glow = QRadialGradient(w/2, h/2, w/2)
            glow_color = QColor(COLORS['accent_green'])
            glow_color.setAlphaF(0.1)
            glow.setColorAt(0, glow_color)
            glow.setColorAt(1, QColor(0, 0, 0, 0))
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(glow)
            painter.drawRoundedRect(0, 0, w, h, 12, 12)

        # Icon/emoji
        painter.setPen(QColor(COLORS['text_primary'] if self.enabled else COLORS['text_secondary']))
        painter.setFont(QFont("Arial", 32))
        painter.drawText(QRect(0, 20, w, 50), Qt.AlignmentFlag.AlignCenter, self.icon_text)

        # Title
        title_color = QColor(COLORS['text_primary'] if self.enabled else COLORS['text_secondary'])
        painter.setPen(title_color)
        painter.setFont(QFont("Space Mono", 14, QFont.Weight.Bold))
        painter.drawText(QRect(0, 70, w, 30), Qt.AlignmentFlag.AlignCenter, self.title)

        # Description
        painter.setPen(QColor(COLORS['text_secondary']))
        painter.setFont(QFont("Space Mono", 10))
        painter.drawText(QRect(10, 100, w-20, 40), Qt.AlignmentFlag.AlignCenter | Qt.TextFlag.TextWordWrap, self.description)

        # "Coming Soon" badge
        if not self.enabled:
            painter.setFont(QFont("Space Mono", 9))
            painter.setPen(QColor(COLORS['accent_yellow']))
            painter.drawText(QRect(0, 135, w, 20), Qt.AlignmentFlag.AlignCenter, "Coming Soon")

        painter.end()


# ============================================================================
# GAME CARD WIDGET
# ============================================================================

class GameCard(QWidget):
    """Card displaying a single game analysis result"""

    # Signal emitted when goalie is switched: (game_idx, team, is_using_backup)
    goalie_switched = pyqtSignal(int, str, bool)

    def __init__(self, game_data, parent=None):
        super().__init__(parent)
        self.data = game_data
        self.setFixedHeight(220)
        self.setMinimumWidth(600)

        # Game index for recalculation reference
        self.game_idx = game_data.get('game_idx', 0)

        # Extract data (now in simplified string format)
        self.away_team = game_data['away']
        self.home_team = game_data['home']
        self.away_score = game_data['away_score']
        self.home_score = game_data['home_score']
        self.pick = game_data['pick']
        self.diff = game_data['diff']

        # Starter goalies
        self.away_goalie = game_data['away_goalie']
        self.home_goalie = game_data['home_goalie']
        self.away_goalie_gsax = game_data['away_goalie_gsax']
        self.home_goalie_gsax = game_data['home_goalie_gsax']

        # Backup goalies
        self.away_backup_goalie = game_data.get('away_backup_goalie')
        self.home_backup_goalie = game_data.get('home_backup_goalie')
        self.away_backup_goalie_gsax = game_data.get('away_backup_goalie_gsax', 0)
        self.home_backup_goalie_gsax = game_data.get('home_backup_goalie_gsax', 0)

        # Track which goalie is currently selected (False = starter, True = backup)
        self.away_using_backup = False
        self.home_using_backup = False

        self.h2h = game_data['h2h']
        self.factors = game_data.get('factors', [])[:3]  # Max 3 factors

        # Store separate click regions for away and home goalie lines
        self.away_goalie_rect = None
        self.home_goalie_rect = None

        # Determine confidence
        if self.diff >= 10:
            self.confidence = "STRONG"
            self.conf_color = QColor("#16a34a")  # Green
        elif self.diff >= 5:
            self.confidence = "MODERATE"
            self.conf_color = QColor("#ca8a04")  # Amber
        else:
            self.confidence = "CLOSE"
            self.conf_color = QColor("#dc2626")  # Red

        # Animation properties for entrance animation
        self._card_opacity = 0.0
        self._card_offset_y = 30.0
        self._has_animated = False

    # Animation property getters/setters for QPropertyAnimation
    def _get_card_opacity(self):
        return self._card_opacity

    def _set_card_opacity(self, val):
        self._card_opacity = val
        self.update()

    card_opacity = pyqtProperty(float, _get_card_opacity, _set_card_opacity)

    def _get_card_offset_y(self):
        return self._card_offset_y

    def _set_card_offset_y(self, val):
        self._card_offset_y = val
        self.update()

    card_offset_y = pyqtProperty(float, _get_card_offset_y, _set_card_offset_y)

    def start_entrance_animation(self, delay_ms=0):
        """Start the fade+slide entrance animation with optional delay"""
        if self._has_animated:
            return
        self._has_animated = True

        # Opacity animation (0 -> 1)
        self._opacity_anim = QPropertyAnimation(self, b"card_opacity")
        self._opacity_anim.setDuration(250)
        self._opacity_anim.setStartValue(0.0)
        self._opacity_anim.setEndValue(1.0)
        self._opacity_anim.setEasingCurve(QEasingCurve.Type.OutCubic)

        # Slide up animation (30 -> 0)
        self._offset_anim = QPropertyAnimation(self, b"card_offset_y")
        self._offset_anim.setDuration(250)
        self._offset_anim.setStartValue(30.0)
        self._offset_anim.setEndValue(0.0)
        self._offset_anim.setEasingCurve(QEasingCurve.Type.OutCubic)

        # Run both animations in parallel
        self._entrance_group = QParallelAnimationGroup()
        self._entrance_group.addAnimation(self._opacity_anim)
        self._entrance_group.addAnimation(self._offset_anim)

        if delay_ms > 0:
            QTimer.singleShot(delay_ms, self._entrance_group.start)
        else:
            self._entrance_group.start()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Apply entrance animation effects
        painter.setOpacity(self._card_opacity)
        painter.translate(0, self._card_offset_y)

        w, h = self.width(), self.height()
        margin = 15

        # Card background - light gray
        card_color = QColor("#f0f4f8")
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(card_color)
        painter.drawRoundedRect(margin, 5, w - margin*2, h - 10, 12, 12)

        # Subtle shadow effect (draw darker rect behind)
        shadow_color = QColor(0, 0, 0, 30)
        painter.setBrush(shadow_color)
        painter.drawRoundedRect(margin + 3, 8, w - margin*2, h - 10, 12, 12)
        painter.setBrush(card_color)
        painter.drawRoundedRect(margin, 5, w - margin*2, h - 10, 12, 12)

        # Content area
        cx = margin + 20  # Content x start
        cw = w - margin*2 - 40  # Content width

        # === HEADER ROW ===
        # Matchup text
        painter.setPen(QColor("#1e3a5f"))
        painter.setFont(QFont("Space Mono", 14, QFont.Weight.Bold))
        matchup = f"  {self.away_team} @ {self.home_team}"
        painter.drawText(cx, 35, matchup)

        # Confidence badge
        badge_x = w - margin - 120
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(self.conf_color)
        painter.drawRoundedRect(badge_x, 18, 90, 26, 13, 13)
        painter.setPen(QColor("white"))
        painter.setFont(QFont("Space Mono", 10, QFont.Weight.Bold))
        painter.drawText(QRect(badge_x, 18, 90, 26), Qt.AlignmentFlag.AlignCenter, self.confidence)

        # Divider line
        painter.setPen(QPen(QColor("#d1d5db"), 1))
        painter.drawLine(cx, 50, w - margin - 20, 50)

        # === CENTER SECTION - SCORES AND PICK ===
        center_y = 70

        # Away team (left)
        painter.setPen(QColor("#6b7280"))
        painter.setFont(QFont("Space Mono", 10))
        painter.drawText(QRect(cx, center_y, 120, 20), Qt.AlignmentFlag.AlignCenter, "AWAY")
        painter.setPen(QColor("#1e3a5f"))
        painter.setFont(QFont("Space Mono", 18, QFont.Weight.Bold))
        painter.drawText(QRect(cx, center_y + 20, 120, 30), Qt.AlignmentFlag.AlignCenter, self.away_team)
        painter.setFont(QFont("Space Mono", 14))
        painter.drawText(QRect(cx, center_y + 50, 120, 25), Qt.AlignmentFlag.AlignCenter, f"{self.away_score:.1f}")

        # Home team (right)
        home_x = w - margin - 140
        painter.setPen(QColor("#6b7280"))
        painter.setFont(QFont("Space Mono", 10))
        painter.drawText(QRect(home_x, center_y, 120, 20), Qt.AlignmentFlag.AlignCenter, "HOME")
        painter.setPen(QColor("#1e3a5f"))
        painter.setFont(QFont("Space Mono", 18, QFont.Weight.Bold))
        painter.drawText(QRect(home_x, center_y + 20, 120, 30), Qt.AlignmentFlag.AlignCenter, self.home_team)
        painter.setFont(QFont("Space Mono", 14))
        painter.drawText(QRect(home_x, center_y + 50, 120, 25), Qt.AlignmentFlag.AlignCenter, f"{self.home_score:.1f}")

        # PICK (center)
        pick_x = w // 2 - 80
        painter.setPen(QColor("#6b7280"))
        painter.setFont(QFont("Space Mono", 10))
        painter.drawText(QRect(pick_x, center_y, 160, 20), Qt.AlignmentFlag.AlignCenter, "PICK")

        # Pick box with accent color
        painter.setPen(Qt.PenStyle.NoPen)
        pick_bg = QColor(COLORS['accent_green'])
        pick_bg.setAlphaF(0.15)
        painter.setBrush(pick_bg)
        painter.drawRoundedRect(pick_x + 20, center_y + 18, 120, 40, 8, 8)

        painter.setPen(QColor(COLORS['accent_green']))
        painter.setFont(QFont("Space Mono", 22, QFont.Weight.Bold))
        painter.drawText(QRect(pick_x, center_y + 20, 160, 40), Qt.AlignmentFlag.AlignCenter, self.pick)

        # Differential
        painter.setPen(QColor("#6b7280"))
        painter.setFont(QFont("Space Mono", 11))
        diff_text = f"(+{self.diff:.1f})"
        painter.drawText(QRect(pick_x, center_y + 58, 160, 20), Qt.AlignmentFlag.AlignCenter, diff_text)

        # === BOTTOM ROW - INFO BOXES ===
        box_y = 155
        box_h = 50
        box_w = (cw - 30) // 3

        # Box 1: Predicted Starting Goalies (clickable)
        # Determine which goalie to display based on selection
        if self.away_using_backup and self.away_backup_goalie:
            away_goalie_display = self.away_backup_goalie
            away_gsax_display = self.away_backup_goalie_gsax
            away_suffix = " *"
        else:
            away_goalie_display = self.away_goalie
            away_gsax_display = self.away_goalie_gsax
            away_suffix = ""

        if self.home_using_backup and self.home_backup_goalie:
            home_goalie_display = self.home_backup_goalie
            home_gsax_display = self.home_backup_goalie_gsax
            home_suffix = " *"
        else:
            home_goalie_display = self.home_goalie
            home_gsax_display = self.home_goalie_gsax
            home_suffix = ""

        away_goalie_name = away_goalie_display.split()[-1] if away_goalie_display else "TBD"
        home_goalie_name = home_goalie_display.split()[-1] if home_goalie_display else "TBD"

        # Store separate click regions for away and home goalie lines
        # Away goalie line is at y+20 to y+35 (approx), Home at y+35 to y+50
        self.away_goalie_rect = QRect(int(cx), int(box_y + 18), int(box_w), 17)
        self.home_goalie_rect = QRect(int(cx), int(box_y + 35), int(box_w), 17)

        # Draw goalie box with clickable indicator
        has_backups = self.away_backup_goalie or self.home_backup_goalie
        self._draw_goalie_box(painter, cx, box_y, box_w, box_h,
                             f"{away_goalie_name}{away_suffix} ({away_gsax_display:+.1f})",
                             f"{home_goalie_name}{home_suffix} ({home_gsax_display:+.1f})",
                             has_backups)

        # Box 2: H2H
        self._draw_info_box(painter, cx + box_w + 15, box_y, box_w, box_h, "H2H RECORD",
                           self.h2h, "")

        # Box 3: Key Factors
        factors_text = ", ".join(self.factors) if self.factors else "No major factors"
        self._draw_info_box(painter, cx + (box_w + 15) * 2, box_y, box_w, box_h, "KEY FACTORS",
                           factors_text, "")

        painter.end()

    def _draw_info_box(self, painter, x, y, w, h, title, line1, line2):
        """Draw an info box with title and content"""
        # Box background
        painter.setPen(QPen(QColor("#e5e7eb"), 1))
        painter.setBrush(QColor("#f9fafb"))
        painter.drawRoundedRect(int(x), int(y), int(w), int(h), 6, 6)

        # Title
        painter.setPen(QColor("#9ca3af"))
        painter.setFont(QFont("Space Mono", 8))
        painter.drawText(int(x + 8), int(y + 14), title)

        # Content
        painter.setPen(QColor("#374151"))
        painter.setFont(QFont("Space Mono", 9))
        if line1:
            painter.drawText(int(x + 8), int(y + 30), line1[:25])
        if line2:
            painter.drawText(int(x + 8), int(y + 43), line2[:25])

    def _draw_goalie_box(self, painter, x, y, w, h, away_line, home_line, clickable):
        """Draw the goalie box with clickable indicator"""
        # Box background - slightly different color if clickable
        if clickable:
            painter.setPen(QPen(QColor("#93c5fd"), 1))  # Blue border for clickable
            painter.setBrush(QColor("#f0f7ff"))  # Slight blue tint
        else:
            painter.setPen(QPen(QColor("#e5e7eb"), 1))
            painter.setBrush(QColor("#f9fafb"))
        painter.drawRoundedRect(int(x), int(y), int(w), int(h), 6, 6)

        # Title with click hint
        painter.setPen(QColor("#9ca3af"))
        painter.setFont(QFont("Space Mono", 8))
        title = "STARTERS (click to swap)" if clickable else "PREDICTED STARTERS"
        painter.drawText(int(x + 8), int(y + 14), title[:25])

        # Away goalie
        painter.setPen(QColor("#374151"))
        painter.setFont(QFont("Space Mono", 9))
        painter.drawText(int(x + 8), int(y + 30), away_line[:25])

        # Home goalie
        painter.drawText(int(x + 8), int(y + 43), home_line[:25])

    def mousePressEvent(self, event):
        """Handle mouse clicks on individual goalie lines"""
        clicked = False

        # Check if away goalie line was clicked
        if self.away_goalie_rect and self.away_goalie_rect.contains(event.pos()):
            if self.away_backup_goalie:
                self.away_using_backup = not self.away_using_backup
                self.goalie_switched.emit(self.game_idx, self.away_team, self.away_using_backup)
                clicked = True

        # Check if home goalie line was clicked
        elif self.home_goalie_rect and self.home_goalie_rect.contains(event.pos()):
            if self.home_backup_goalie:
                self.home_using_backup = not self.home_using_backup
                self.goalie_switched.emit(self.game_idx, self.home_team, self.home_using_backup)
                clicked = True

        if clicked:
            self.update()  # Trigger repaint

        super().mousePressEvent(event)

    def update_after_recalc(self, new_data):
        """Update card display after recalculation"""
        self.away_score = new_data['away_score']
        self.home_score = new_data['home_score']
        self.pick = new_data['pick']
        self.diff = new_data['diff']
        self.factors = new_data.get('factors', [])[:3]

        # Update confidence
        if self.diff >= 10:
            self.confidence = "STRONG"
            self.conf_color = QColor("#16a34a")
        elif self.diff >= 5:
            self.confidence = "MODERATE"
            self.conf_color = QColor("#ca8a04")
        else:
            self.confidence = "CLOSE"
            self.conf_color = QColor("#dc2626")

        self.update()  # Trigger repaint


# ============================================================================
# HOME PAGE
# ============================================================================

class HomePage(QWidget):
    """Navigation hub displayed after loading"""
    navigate_to_model = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("HockeyQuant")
        self.setFixedSize(700, 600)

        # Load logo
        logo_path = os.path.join(os.path.dirname(__file__), "logo.png")
        self._logo_pixmap = QPixmap(logo_path)
        if not self._logo_pixmap.isNull():
            self._logo_pixmap = self._logo_pixmap.scaled(
                120, 120,
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation
            )

        self._init_ui()

    def _init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)
        layout.setContentsMargins(40, 30, 40, 30)

        # Logo
        logo_label = QLabel()
        if not self._logo_pixmap.isNull():
            logo_label.setPixmap(self._logo_pixmap)
        logo_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(logo_label)

        # Title
        title = QLabel("HockeyQuant")
        title.setFont(QFont("Raleway Dots", 32, QFont.Weight.Bold))
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.setStyleSheet(f"color: {COLORS['text_primary']};")
        layout.addWidget(title)

        layout.addSpacing(20)

        # Cards grid
        cards_layout = QGridLayout()
        cards_layout.setSpacing(20)
        cards_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # Row 1
        run_model_card = NavigationCard(
            "Run Model", "Analyze today's NHL matchups", "🏒", enabled=True
        )
        run_model_card.clicked.connect(self.navigate_to_model.emit)
        cards_layout.addWidget(run_model_card, 0, 0)

        custom_models_card = NavigationCard(
            "Custom Models", "Build & explore prediction models", "📊", enabled=False
        )
        cards_layout.addWidget(custom_models_card, 0, 1)

        # Row 2
        stats_card = NavigationCard(
            "Stats", "Team & player statistics", "📈", enabled=False
        )
        cards_layout.addWidget(stats_card, 1, 0)

        leaderboard_card = NavigationCard(
            "Leaderboard", "Compare model accuracy", "🏆", enabled=False
        )
        cards_layout.addWidget(leaderboard_card, 1, 1)

        layout.addLayout(cards_layout)

        layout.addStretch()

        # Version footer
        version = QLabel("Version 7.0")
        version.setFont(QFont("Space Mono", 10))
        version.setAlignment(Qt.AlignmentFlag.AlignCenter)
        version.setStyleSheet(f"color: {COLORS['text_secondary']};")
        layout.addWidget(version)

    def paintEvent(self, event):
        """Draw gradient background"""
        painter = QPainter(self)
        w, h = self.width(), self.height()

        # Gradient background
        gradient = QLinearGradient(0, 0, 0, h)
        gradient.setColorAt(0, QColor(COLORS['bg_gradient_top']))
        gradient.setColorAt(1, QColor(COLORS['bg_gradient_bottom']))
        painter.fillRect(0, 0, w, h, gradient)

        painter.end()

    def start_fade_out(self, callback):
        """Fade out this window"""
        self._fade_anim = QPropertyAnimation(self, b"windowOpacity")
        self._fade_anim.setDuration(300)
        self._fade_anim.setStartValue(1.0)
        self._fade_anim.setEndValue(0.0)
        self._fade_anim.setEasingCurve(QEasingCurve.Type.InOutQuad)
        self._fade_anim.finished.connect(callback)
        self._fade_anim.start()


# ============================================================================
# MAIN WINDOW
# ============================================================================

class MainWindow(QMainWindow):
    """Main model results window"""
    navigate_back = pyqtSignal()

    def __init__(self, data):
        super().__init__()
        self.data = data
        self.analyzer = NHLAnalyzer(
            data.get('team_data'),
            data.get('goalie_data'),
            data.get('pp_data'),
            data.get('pk_data'),
            data.get('skater_data')
        )
        self.worker = None
        self.game_cards = []
        self.current_results = []
        self.init_ui()

    def init_ui(self):
        self.setWindowTitle("HockeyQuant")
        self.setMinimumSize(1300, 850)

        central = QWidget()
        central.setStyleSheet("""
            QWidget {
                background: qlineargradient(
                    x1:0, y1:0, x2:0, y2:1,
                    stop:0 #0d2137,
                    stop:1 #0a1628
                );
            }
        """)
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setSpacing(15)
        layout.setContentsMargins(25, 25, 25, 25)

        # Header with back button
        header_layout = QHBoxLayout()

        self.back_btn = QPushButton("← Back")
        self.back_btn.setFont(QFont("Space Mono", 11))
        self.back_btn.setFixedSize(80, 35)
        self.back_btn.setStyleSheet("""
            QPushButton {
                background-color: transparent;
                color: #7eb8da;
                border: 1px solid #7eb8da;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: rgba(126, 184, 218, 0.1);
                color: white;
                border-color: white;
            }
        """)
        self.back_btn.clicked.connect(self.navigate_back.emit)
        header_layout.addWidget(self.back_btn)

        header_layout.addStretch()

        header = QLabel("HockeyQuant")
        header.setFont(QFont("Raleway Dots", 28, QFont.Weight.Bold))
        header.setStyleSheet("color: white; background: transparent;")
        header_layout.addWidget(header)

        header_layout.addStretch()

        # Spacer to balance the back button
        spacer = QWidget()
        spacer.setFixedSize(80, 35)
        header_layout.addWidget(spacer)

        layout.addLayout(header_layout)

        subtitle = QLabel("Version 7.0")
        subtitle.setFont(QFont("Space Mono", 11))
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle.setStyleSheet("color: #7eb8da; background: transparent;")
        layout.addWidget(subtitle)

        layout.addSpacing(10)

        # Controls
        controls = QHBoxLayout()
        date_label = QLabel("Game Date:")
        date_label.setFont(QFont("Space Mono", 13))
        date_label.setStyleSheet("color: white; background: transparent;")
        controls.addWidget(date_label)

        self.date_edit = QDateEdit()
        self.date_edit.setDate(QDate.currentDate())
        self.date_edit.setCalendarPopup(True)
        self.date_edit.setFont(QFont("Space Mono", 13))
        self.date_edit.setMinimumWidth(160)
        self.date_edit.setMinimumHeight(35)
        self.date_edit.setStyleSheet("""
            QDateEdit {
                background-color: #1a3550;
                color: white;
                border: 1px solid #4a7090;
                border-radius: 6px;
                padding: 5px 10px;
            }
            QDateEdit:hover {
                border-color: #7eb8da;
            }
            QDateEdit::drop-down {
                border: none;
                width: 25px;
            }
            QDateEdit::down-arrow {
                image: none;
                border-left: 5px solid transparent;
                border-right: 5px solid transparent;
                border-top: 6px solid #7eb8da;
            }
        """)
        controls.addWidget(self.date_edit)

        controls.addStretch()

        self.run_btn = QPushButton("Run HockeyQuant Model")
        self.run_btn.setFont(QFont("Space Mono", 13, QFont.Weight.Bold))
        self.run_btn.setMinimumSize(180, 50)
        self.run_btn.setStyleSheet("""
            QPushButton {
                background-color: #2563eb;
                color: white;
                border: none;
                border-radius: 8px;
            }
            QPushButton:hover { background-color: #1d4ed8; }
            QPushButton:disabled { background-color: #93c5fd; }
        """)
        self.run_btn.clicked.connect(self.run_analysis)
        controls.addWidget(self.run_btn)

        layout.addLayout(controls)

        # Progress
        self.progress = QProgressBar()
        self.progress.setVisible(False)
        self.progress.setMinimumHeight(30)
        self.progress.setStyleSheet("""
            QProgressBar {
                background-color: #1a3550;
                border: none;
                border-radius: 8px;
                text-align: center;
                color: white;
            }
            QProgressBar::chunk {
                background: qlineargradient(
                    x1:0, y1:0, x2:1, y2:0,
                    stop:0 #2196F3,
                    stop:0.5 #4CAF50,
                    stop:1 #FFD700
                );
                border-radius: 8px;
            }
        """)
        layout.addWidget(self.progress)

        self.status_label = QLabel("")
        self.status_label.setFont(QFont("Space Mono", 11))
        self.status_label.setStyleSheet("color: #7eb8da; background: transparent;")
        layout.addWidget(self.status_label)

        # Scrollable results area with game cards
        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.scroll_area.setStyleSheet("""
            QScrollArea {
                border: none;
                background: transparent;
            }
            QScrollBar:vertical {
                background: #1a3550;
                width: 10px;
                border-radius: 5px;
            }
            QScrollBar::handle:vertical {
                background: #4a7090;
                border-radius: 5px;
                min-height: 30px;
            }
            QScrollBar::handle:vertical:hover {
                background: #5a8aa0;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
            }
        """)

        # Container widget for cards
        self.cards_container = QWidget()
        self.cards_container.setStyleSheet("background: transparent;")
        self.cards_layout = QVBoxLayout(self.cards_container)
        self.cards_layout.setSpacing(16)
        self.cards_layout.setContentsMargins(20, 20, 20, 20)
        self.cards_layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        # Placeholder message when no results
        self.no_results_label = QLabel("Run analysis to see game predictions")
        self.no_results_label.setFont(QFont("Space Mono", 14))
        self.no_results_label.setStyleSheet("color: #7eb8da;")
        self.no_results_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.cards_layout.addWidget(self.no_results_label)

        self.scroll_area.setWidget(self.cards_container)
        layout.addWidget(self.scroll_area)

        # Connect scroll bar to check for cards entering viewport
        self.scroll_area.verticalScrollBar().valueChanged.connect(self.check_visible_cards)

        # Footer
        footer = QLabel("Data: MoneyPuck.com | Injuries: ESPN.com | Schedule: NHL API")
        footer.setFont(QFont("Space Mono", 10))
        footer.setAlignment(Qt.AlignmentFlag.AlignCenter)
        footer.setStyleSheet("color: #5a7a90; background: transparent;")
        layout.addWidget(footer)

    def run_analysis(self):
        # Properly cleanup previous worker
        if self.worker is not None:
            if self.worker.isRunning():
                self.status_label.setText("Analysis already running, please wait...")
                return
            # Disconnect all signals first to prevent stale signals
            try:
                self.worker.progress.disconnect()
                self.worker.result.disconnect()
                self.worker.error.disconnect()
                self.worker.finished.disconnect()
            except:
                pass
            # Wait for thread to fully terminate
            self.worker.wait()
            self.worker = None

        date = self.date_edit.date().toString("yyyy-MM-dd")
        self.run_btn.setEnabled(False)
        self.progress.setVisible(True)
        self.progress.setValue(0)
        self.progress.setRange(0, 100)
        # Clear existing cards
        self.clear_cards()
        self.status_label.setText(f"Starting analysis for {date}...")

        # Create new worker
        self.worker = AnalysisWorker(self.analyzer, date)
        self.worker.progress.connect(self.update_progress)
        self.worker.result.connect(self.show_results)
        self.worker.error.connect(self.show_error)
        self.worker.finished.connect(self.on_worker_finished)
        self.worker.start()

    def update_progress(self, value, status):
        # Animate progress bar smoothly
        if not hasattr(self, '_progress_anim') or self._progress_anim is None:
            self._progress_anim = QPropertyAnimation(self.progress, b"value")
            self._progress_anim.setEasingCurve(QEasingCurve.Type.OutCubic)

        # Stop existing animation and start new one
        self._progress_anim.stop()
        self._progress_anim.setDuration(200)
        self._progress_anim.setStartValue(self.progress.value())
        self._progress_anim.setEndValue(value)
        self._progress_anim.start()

        self.status_label.setText(status)

    def on_worker_finished(self):
        """Called when worker thread completes"""
        self.run_btn.setEnabled(True)
        self.progress.setVisible(False)

    def clear_cards(self):
        """Remove all game cards from the layout"""
        # Hide the no results label
        self.no_results_label.setVisible(False)
        # Remove all widgets from layout except the no_results_label
        while self.cards_layout.count() > 1:
            item = self.cards_layout.takeAt(1)
            if item.widget():
                item.widget().deleteLater()

    def check_visible_cards(self):
        """Check which cards are visible in viewport and animate them"""
        if not self.game_cards:
            return

        # Get the viewport rect in scroll area coordinates
        viewport = self.scroll_area.viewport()
        viewport_rect = viewport.rect()

        # Stagger delay counter for cards entering view together
        stagger_delay = 0

        for card in self.game_cards:
            if card._has_animated:
                continue

            # Get card position relative to scroll area viewport
            card_pos = card.mapTo(viewport, QPoint(0, 0))
            card_rect = QRect(card_pos.x(), card_pos.y(), card.width(), card.height())

            # Check if card intersects with viewport (with some margin for early trigger)
            expanded_viewport = QRect(
                viewport_rect.x(),
                viewport_rect.y() - 50,  # Start animation slightly before fully visible
                viewport_rect.width(),
                viewport_rect.height() + 100
            )

            if expanded_viewport.intersects(card_rect):
                card.start_entrance_animation(stagger_delay)
                stagger_delay += 80  # 80ms stagger between cards

    def show_results(self, results):
        if not results:
            self.status_label.setText("No games found or analysis failed")
            self.no_results_label.setVisible(True)
            return

        # Clear any existing cards
        self.clear_cards()

        # Sort by confidence (diff) descending - STRONG first, then MODERATE, then CLOSE
        sorted_results = sorted(results, key=lambda r: r['diff'], reverse=True)

        # Store results and cards for potential recalculation
        self.current_results = sorted_results
        self.game_cards = []

        for idx, r in enumerate(sorted_results):
            away = r['away']
            home = r['home']

            # Build key factors list
            factors = []
            winner = home if r['pick'] == home['team'] else away
            loser = away if r['pick'] == home['team'] else home

            if winner['streak_mult'] > 1.02:
                factors.append(f"{winner['team']} hot")
            if loser['streak_mult'] < 0.95:
                factors.append(f"{loser['team']} cold")
            if winner['injury_mult'] > loser['injury_mult'] + 0.02:
                factors.append(f"{loser['team']} injuries")
            if loser['fatigue_mult'] < 0.95:
                factors.append(f"{loser['team']} fatigued")
            if winner['h2h_mult'] > 1.02:
                factors.append(f"{winner['team']} H2H edge")

            # Create game data dict for GameCard (including backup goalie info)
            game_data = {
                'game_idx': idx,
                'away': away['team'],
                'home': home['team'],
                'away_score': away['final_score'],
                'home_score': home['final_score'],
                'pick': r['pick'],
                'diff': r['diff'],
                'away_goalie': away['goalie'],
                'home_goalie': home['goalie'],
                'away_goalie_gsax': away['goalie_gsax'],
                'home_goalie_gsax': home['goalie_gsax'],
                'away_backup_goalie': away.get('backup_goalie'),
                'home_backup_goalie': home.get('backup_goalie'),
                'away_backup_goalie_gsax': away.get('backup_goalie_gsax', 0),
                'home_backup_goalie_gsax': home.get('backup_goalie_gsax', 0),
                'h2h': winner['h2h'],
                'factors': factors,
                # Store full team data for recalculation
                'away_data': away,
                'home_data': home,
            }

            # Create and add GameCard
            card = GameCard(game_data)
            card.goalie_switched.connect(self.recalculate_game)
            self.game_cards.append(card)
            self.cards_layout.addWidget(card)

        self.status_label.setText(f"Analysis complete: {len(sorted_results)} games analyzed")

        # Trigger initial animation for visible cards after layout settles
        QTimer.singleShot(50, self.check_visible_cards)

    def show_error(self, error):
        self.status_label.setText(f"Error: {error}")
        QMessageBox.warning(self, "Error", error)

    def recalculate_game(self, game_idx, team, is_using_backup):
        """Recalculate a game's prediction when goalie is switched"""
        if game_idx >= len(self.game_cards):
            return

        card = self.game_cards[game_idx]
        away_data = card.data.get('away_data', {})
        home_data = card.data.get('home_data', {})

        # Determine which team's goalie was switched and get new goalie stats
        if team == card.away_team:
            if is_using_backup and card.away_backup_goalie:
                new_goalie = {
                    'gsax': away_data.get('backup_goalie_gsax', 0),
                    'sv_pct': away_data.get('backup_goalie_sv_pct', 0.900),
                    'gaa': away_data.get('backup_goalie_gaa', 3.0)
                }
                old_goalie = {
                    'gsax': away_data.get('goalie_gsax', 0),
                    'sv_pct': away_data.get('goalie_sv_pct', 0.900),
                    'gaa': away_data.get('goalie_gaa', 3.0)
                }
            else:
                # Switching back to starter
                new_goalie = {
                    'gsax': away_data.get('goalie_gsax', 0),
                    'sv_pct': away_data.get('goalie_sv_pct', 0.900),
                    'gaa': away_data.get('goalie_gaa', 3.0)
                }
                old_goalie = {
                    'gsax': away_data.get('backup_goalie_gsax', 0),
                    'sv_pct': away_data.get('backup_goalie_sv_pct', 0.900),
                    'gaa': away_data.get('backup_goalie_gaa', 3.0)
                }

            # Calculate score difference
            old_score = self.analyzer.calculate_goalie_score(old_goalie)
            new_score = self.analyzer.calculate_goalie_score(new_goalie)
            score_diff = (new_score - old_score) * 30  # Goalie contributes 30 points

            # Adjust away team's scores
            new_away_base = away_data.get('base_score', 50) + score_diff
            mults = (away_data.get('fatigue_mult', 1) * away_data.get('streak_mult', 1) *
                    away_data.get('st_mult', 1) * away_data.get('injury_mult', 1) *
                    away_data.get('h2h_mult', 1))
            new_away_final = new_away_base * mults
            new_home_final = home_data.get('final_score', 50)
        else:
            # Home team goalie switched
            if is_using_backup and card.home_backup_goalie:
                new_goalie = {
                    'gsax': home_data.get('backup_goalie_gsax', 0),
                    'sv_pct': home_data.get('backup_goalie_sv_pct', 0.900),
                    'gaa': home_data.get('backup_goalie_gaa', 3.0)
                }
                old_goalie = {
                    'gsax': home_data.get('goalie_gsax', 0),
                    'sv_pct': home_data.get('goalie_sv_pct', 0.900),
                    'gaa': home_data.get('goalie_gaa', 3.0)
                }
            else:
                new_goalie = {
                    'gsax': home_data.get('goalie_gsax', 0),
                    'sv_pct': home_data.get('goalie_sv_pct', 0.900),
                    'gaa': home_data.get('goalie_gaa', 3.0)
                }
                old_goalie = {
                    'gsax': home_data.get('backup_goalie_gsax', 0),
                    'sv_pct': home_data.get('backup_goalie_sv_pct', 0.900),
                    'gaa': home_data.get('backup_goalie_gaa', 3.0)
                }

            old_score = self.analyzer.calculate_goalie_score(old_goalie)
            new_score = self.analyzer.calculate_goalie_score(new_goalie)
            score_diff = (new_score - old_score) * 30

            new_home_base = home_data.get('base_score', 50) + score_diff
            mults = (home_data.get('fatigue_mult', 1) * home_data.get('streak_mult', 1) *
                    home_data.get('st_mult', 1) * home_data.get('injury_mult', 1) *
                    home_data.get('h2h_mult', 1))
            new_home_final = new_home_base * mults
            new_away_final = away_data.get('final_score', 50)

        # Determine new pick
        diff = new_home_final - new_away_final
        pick = card.home_team if diff > 0 else card.away_team

        # Update card with new data
        card.update_after_recalc({
            'away_score': new_away_final,
            'home_score': new_home_final,
            'pick': pick,
            'diff': abs(diff),
            'factors': card.factors  # Keep same factors
        })

        self.status_label.setText(f"Recalculated {card.away_team} @ {card.home_team} with new goalie")

    def start_fade_out(self, callback):
        """Fade out this window"""
        self._fade_anim = QPropertyAnimation(self, b"windowOpacity")
        self._fade_anim.setDuration(300)
        self._fade_anim.setStartValue(1.0)
        self._fade_anim.setEndValue(0.0)
        self._fade_anim.setEasingCurve(QEasingCurve.Type.InOutQuad)
        self._fade_anim.finished.connect(callback)
        self._fade_anim.start()


# ============================================================================
# MAIN
# ============================================================================

def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")

    # Get screen geometry for centering windows
    screen = app.primaryScreen().geometry()

    # Show loading screen
    loading = LoadingWindow()
    loading.show()
    loading.move(
        (screen.width() - loading.width()) // 2,
        (screen.height() - loading.height()) // 2
    )

    # Create data loader
    loader = DataLoader()
    app.loader = loader
    app.loaded_data = None
    app.home_page = None
    app.main_window = None

    def center_window(window):
        """Center a window on screen"""
        window.move(
            (screen.width() - window.width()) // 2,
            (screen.height() - window.height()) // 2
        )

    def show_home_page():
        """Show the home page with fade-in"""
        if app.home_page is None:
            app.home_page = HomePage()
            app.home_page.navigate_to_model.connect(on_navigate_to_model)

        app.home_page.setWindowOpacity(0.0)
        center_window(app.home_page)
        app.home_page.show()

        # Fade in
        fade = QPropertyAnimation(app.home_page, b"windowOpacity")
        fade.setDuration(300)
        fade.setStartValue(0.0)
        fade.setEndValue(1.0)
        fade.setEasingCurve(QEasingCurve.Type.OutQuad)
        app.home_fade = fade
        fade.start()

    def show_main_window():
        """Show the main window with fade-in"""
        if app.main_window is None:
            app.main_window = MainWindow(app.loaded_data)
            app.main_window.navigate_back.connect(on_navigate_back)

        app.main_window.setWindowOpacity(0.0)
        center_window(app.main_window)
        app.main_window.show()

        # Fade in
        fade = QPropertyAnimation(app.main_window, b"windowOpacity")
        fade.setDuration(300)
        fade.setStartValue(0.0)
        fade.setEndValue(1.0)
        fade.setEasingCurve(QEasingCurve.Type.OutQuad)
        app.main_fade = fade
        fade.start()

    def on_navigate_to_model():
        """Navigate from HomePage to MainWindow"""
        def on_fade_done():
            app.home_page.hide()
            show_main_window()

        app.home_page.start_fade_out(on_fade_done)

    def on_navigate_back():
        """Navigate from MainWindow back to HomePage"""
        def on_fade_done():
            app.main_window.hide()
            show_home_page()
 
        app.main_window.start_fade_out(on_fade_done)

    def on_status_update(text):
        """Update loading screen status"""
        loading.status.setText(text)

    def on_intro_complete():
        """Called when intro animation finishes - start loading data"""
        loader.status.connect(on_status_update)
        loader.finished.connect(on_data_loaded)
        loader.error.connect(on_error)
        loader.start()

    def on_data_loaded(data):
        """Called when data finishes loading"""
        app.loaded_data = data
        loading.set_progress(100)
        loading.show_ready_state()

    def on_ready_for_transition():
        """Called after 'Ready!' - transition to HomePage"""
        def on_loading_fade_done():
            loading.close()
            show_home_page()

        loading.start_fade_out(on_loading_fade_done)

    def on_error(error):
        loading.close()
        QMessageBox.critical(None, "Data Load Error", f"Failed to load data:\n{error}")
        sys.exit(1)

    # Connect signals
    loading.intro_complete.connect(on_intro_complete)
    loading.ready_for_transition.connect(on_ready_for_transition)

    # Progress updates
    def on_loader_status(text):
        loading.status.setText(text)
        if "team" in text.lower():
            loading.set_progress(20)
        elif "goalie" in text.lower():
            loading.set_progress(50)
        elif "skater" in text.lower():
            loading.set_progress(80)

    loader.status.connect(on_loader_status)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
