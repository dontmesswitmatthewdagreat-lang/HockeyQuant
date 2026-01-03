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
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QTableWidget, QTableWidgetItem, QHeaderView,
    QProgressBar, QDateEdit, QMessageBox
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal, QDate
from PyQt6.QtGui import QFont, QColor


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
                        if pos != 'G' and name:
                            players.append(name)
                if players:
                    all_injuries[team_abbrev] = players
                    self.injury_cache[team_abbrev] = {'injuries': players, 'timestamp': datetime.now().isoformat()}
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
        starter = qualified.nlargest(1, 'games_played').iloc[0]
        xGoals = float(starter['xGoals'])
        goals = float(starter['goals'])
        ongoal = float(starter['ongoal'])
        icetime = float(starter['icetime'])
        gsax = xGoals - goals
        sv_pct = (ongoal - goals) / ongoal if ongoal > 0 else 0.900
        gaa = (goals / (icetime/60)) * 60 if icetime > 0 else 3.0
        return {'name': starter['name'], 'gsax': gsax, 'sv_pct': sv_pct, 'gaa': gaa}

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
        off_quality = xgf_pct * 0.7 + gf_pct * 0.3

        goalie = self.get_starting_goalie(team_abbrev)
        goalie_score = self.calculate_goalie_score(goalie)

        base_score = off_quality * 35 + pts_pct * 25 + goalie_score * 30 + win_pct * 10

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
# LOADING WINDOW
# ============================================================================

class LoadingWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("NHL Moneyline Generator")
        self.setFixedSize(500, 250)

        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.setSpacing(15)

        title = QLabel("NHL Moneyline Generator")
        title.setFont(QFont("Arial", 24, QFont.Weight.Bold))
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title)

        subtitle = QLabel("Phase 7: xG + Goaltending + Fatigue + Streaks + PP/PK + Injuries + H2H")
        subtitle.setFont(QFont("Arial", 10))
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle.setStyleSheet("color: #666;")
        layout.addWidget(subtitle)

        layout.addSpacing(20)

        self.status = QLabel("Initializing...")
        self.status.setFont(QFont("Arial", 12))
        self.status.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self.status)

        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setMinimumWidth(400)
        self.progress.setMinimumHeight(25)
        layout.addWidget(self.progress)


# ============================================================================
# MAIN WINDOW
# ============================================================================

class MainWindow(QMainWindow):
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
        self.init_ui()

    def init_ui(self):
        self.setWindowTitle("NHL Moneyline Generator - Phase 7")
        self.setMinimumSize(1300, 850)

        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setSpacing(15)
        layout.setContentsMargins(25, 25, 25, 25)

        # Header
        header = QLabel("NHL Moneyline Generator")
        header.setFont(QFont("Arial", 28, QFont.Weight.Bold))
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(header)

        subtitle = QLabel("Phase 7: xG + Goaltending + Fatigue + Streaks + PP/PK + Injuries + H2H")
        subtitle.setFont(QFont("Arial", 11))
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle.setStyleSheet("color: #666;")
        layout.addWidget(subtitle)

        layout.addSpacing(10)

        # Controls
        controls = QHBoxLayout()
        date_label = QLabel("Game Date:")
        date_label.setFont(QFont("Arial", 13))
        controls.addWidget(date_label)

        self.date_edit = QDateEdit()
        self.date_edit.setDate(QDate.currentDate())
        self.date_edit.setCalendarPopup(True)
        self.date_edit.setFont(QFont("Arial", 13))
        self.date_edit.setMinimumWidth(160)
        self.date_edit.setMinimumHeight(35)
        controls.addWidget(self.date_edit)

        controls.addStretch()

        self.run_btn = QPushButton("Run Analysis")
        self.run_btn.setFont(QFont("Arial", 14, QFont.Weight.Bold))
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
        layout.addWidget(self.progress)

        self.status_label = QLabel("")
        self.status_label.setFont(QFont("Arial", 11))
        self.status_label.setStyleSheet("color: #666;")
        layout.addWidget(self.status_label)

        # Results table
        self.table = QTableWidget()
        self.table.setColumnCount(10)
        self.table.setHorizontalHeaderLabels([
            "Game", "Pick", "Confidence", "Diff",
            "Away Score", "Home Score",
            "Away Goalie", "Home Goalie",
            "H2H", "Key Factors"
        ])

        header_view = self.table.horizontalHeader()
        header_view.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        header_view.setSectionResizeMode(9, QHeaderView.ResizeMode.Stretch)
        for i in range(1, 9):
            header_view.setSectionResizeMode(i, QHeaderView.ResizeMode.ResizeToContents)

        self.table.setAlternatingRowColors(True)
        self.table.verticalHeader().setDefaultSectionSize(45)
        self.table.setStyleSheet("""
            QTableWidget {
                gridline-color: #ddd;
                font-size: 13px;
            }
            QTableWidget::item { padding: 12px; }
            QHeaderView::section {
                background-color: #1e3a5f;
                color: white;
                padding: 12px;
                font-weight: bold;
                font-size: 12px;
                border: none;
            }
        """)
        layout.addWidget(self.table)

        # Footer
        footer = QLabel("Data: MoneyPuck.com | Injuries: ESPN.com | Schedule: NHL API")
        footer.setFont(QFont("Arial", 10))
        footer.setAlignment(Qt.AlignmentFlag.AlignCenter)
        footer.setStyleSheet("color: #999;")
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
        self.table.setRowCount(0)
        self.status_label.setText(f"Starting analysis for {date}...")

        # Create new worker
        self.worker = AnalysisWorker(self.analyzer, date)
        self.worker.progress.connect(self.update_progress)
        self.worker.result.connect(self.show_results)
        self.worker.error.connect(self.show_error)
        self.worker.finished.connect(self.on_worker_finished)
        self.worker.start()

    def update_progress(self, value, status):
        self.progress.setValue(value)
        self.status_label.setText(status)

    def on_worker_finished(self):
        """Called when worker thread completes"""
        self.run_btn.setEnabled(True)
        self.progress.setVisible(False)

    def show_results(self, results):
        if not results:
            self.status_label.setText("No games found or analysis failed")
            return

        self.table.setRowCount(len(results))

        for row, r in enumerate(results):
            away = r['away']
            home = r['home']

            # Game
            game_item = QTableWidgetItem(f"{away['team']} @ {home['team']}")
            game_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            game_item.setFont(QFont("Arial", 12, QFont.Weight.Bold))
            self.table.setItem(row, 0, game_item)

            # Pick
            pick_item = QTableWidgetItem(r['pick'])
            pick_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            pick_item.setFont(QFont("Arial", 14, QFont.Weight.Bold))
            pick_item.setForeground(QColor("#1e40af"))
            self.table.setItem(row, 1, pick_item)

            # Confidence
            diff = r['diff']
            if diff >= 10:
                conf, color = "STRONG", QColor("#16a34a")
            elif diff >= 5:
                conf, color = "Moderate", QColor("#ca8a04")
            else:
                conf, color = "Close", QColor("#dc2626")

            conf_item = QTableWidgetItem(conf)
            conf_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            conf_item.setForeground(color)
            conf_item.setFont(QFont("Arial", 12, QFont.Weight.Bold))
            self.table.setItem(row, 2, conf_item)

            # Difference
            diff_item = QTableWidgetItem(f"{diff:.1f}")
            diff_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            self.table.setItem(row, 3, diff_item)

            # Scores
            away_score = QTableWidgetItem(f"{away['final_score']:.1f}")
            away_score.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            self.table.setItem(row, 4, away_score)

            home_score = QTableWidgetItem(f"{home['final_score']:.1f}")
            home_score.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            self.table.setItem(row, 5, home_score)

            # Goalies
            away_goalie = QTableWidgetItem(f"{away['goalie']} ({away['goalie_gsax']:+.1f})")
            away_goalie.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            self.table.setItem(row, 6, away_goalie)

            home_goalie = QTableWidgetItem(f"{home['goalie']} ({home['goalie_gsax']:+.1f})")
            home_goalie.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            self.table.setItem(row, 7, home_goalie)

            # H2H
            winner = home if r['pick'] == home['team'] else away
            h2h_item = QTableWidgetItem(winner['h2h'])
            h2h_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            self.table.setItem(row, 8, h2h_item)

            # Key factors
            factors = []
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

            factors_item = QTableWidgetItem(", ".join(factors) if factors else "-")
            self.table.setItem(row, 9, factors_item)

        self.status_label.setText(f"Analysis complete: {len(results)} games analyzed")

    def show_error(self, error):
        self.status_label.setText(f"Error: {error}")
        QMessageBox.warning(self, "Error", error)


# ============================================================================
# MAIN
# ============================================================================

def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")

    # Show loading screen
    loading = LoadingWindow()
    loading.show()

    # Load data in background - keep reference to prevent garbage collection
    loader = DataLoader()
    loader.status.connect(loading.status.setText)
    app.loader = loader  # Keep reference

    def on_data_loaded(data):
        loading.close()
        window = MainWindow(data)
        window.show()
        app.main_window = window  # Keep reference

    def on_error(error):
        loading.close()
        QMessageBox.critical(None, "Data Load Error", f"Failed to load data:\n{error}")
        sys.exit(1)

    loader.finished.connect(on_data_loaded)
    loader.error.connect(on_error)
    loader.start()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
