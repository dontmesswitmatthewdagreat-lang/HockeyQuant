#!/usr/bin/env python3
"""
NHL Moneyline Generator - Desktop Application
A polished PyQt6 GUI for NHL betting analysis
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
    QProgressBar, QFrame, QDateEdit, QMessageBox, QSplitter
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal, QDate
from PyQt6.QtGui import QFont, QColor, QPalette


# ============================================================================
# DATA LOADING (runs once at startup)
# ============================================================================

def load_data():
    """Load all required data from MoneyPuck"""
    data = {}

    try:
        TEAM_XG_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/teams.csv"
        TEAM_DATA_FULL = pd.read_csv(TEAM_XG_URL)
        data['team_data'] = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == 'all']
        data['pp_data'] = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == '5on4']
        data['pk_data'] = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == '4on5']
    except Exception as e:
        print(f"Team data error: {e}")
        data['team_data'] = None
        data['pp_data'] = None
        data['pk_data'] = None

    try:
        GOALIE_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/goalies.csv"
        GOALIE_DATA = pd.read_csv(GOALIE_URL)
        data['goalie_data'] = GOALIE_DATA[GOALIE_DATA['situation'] == 'all']
    except Exception as e:
        print(f"Goalie data error: {e}")
        data['goalie_data'] = None

    try:
        SKATER_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/skaters.csv"
        SKATER_DATA = pd.read_csv(SKATER_URL)
        data['skater_data'] = SKATER_DATA[SKATER_DATA['situation'] == 'all']
    except Exception as e:
        print(f"Skater data error: {e}")
        data['skater_data'] = None

    return data


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

INJURY_CACHE_FILE = os.path.join(os.path.dirname(__file__), "injury_cache.json")


# ============================================================================
# ANALYZER CLASS (Core Logic)
# ============================================================================

class NHLAnalyzer:
    def __init__(self, data):
        self.base_url = "https://api-web.nhle.com/v1"
        self.team_data = data.get('team_data')
        self.goalie_data = data.get('goalie_data')
        self.pp_data = data.get('pp_data')
        self.pk_data = data.get('pk_data')
        self.skater_data = data.get('skater_data')
        self.injury_cache = self._load_injury_cache()

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
        url = f"{self.base_url}/standings/now"
        try:
            response = requests.get(url, timeout=10)
            data = response.json()
            if 'standings' in data:
                for team in data['standings']:
                    if team.get('teamAbbrev', {}).get('default') == team_abbrev:
                        return team
        except:
            pass
        return None

    def get_recent_games(self, team_abbrev, lookback_days=7):
        today = datetime.now()
        games = []
        for days_ago in range(1, lookback_days + 1):
            check_date = today - timedelta(days=days_ago)
            date_str = check_date.strftime("%Y-%m-%d")
            url = f"{self.base_url}/schedule/{date_str}"
            try:
                response = requests.get(url, timeout=10)
                data = response.json()
                if 'gameWeek' in data:
                    for day in data['gameWeek']:
                        if day.get('date') == date_str and 'games' in day:
                            for game in day['games']:
                                home_team = game.get('homeTeam', {}).get('abbrev')
                                away_team = game.get('awayTeam', {}).get('abbrev')
                                if home_team == team_abbrev:
                                    games.append({'date': date_str, 'home_away': 'home', 'opponent': away_team, 'days_ago': days_ago})
                                elif away_team == team_abbrev:
                                    games.append({'date': date_str, 'home_away': 'away', 'opponent': home_team, 'days_ago': days_ago})
            except:
                continue
        return sorted(games, key=lambda x: x['days_ago'])

    def get_last_10_games(self, team_abbrev):
        url = f"{self.base_url}/club-schedule-season/{team_abbrev}/now"
        try:
            response = requests.get(url, timeout=10)
            data = response.json()
            completed_games = []
            if 'games' in data:
                for game in data['games']:
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
        except:
            return []

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

        if is_away:
            team_tz = TEAM_TIMEZONES.get(team_abbrev, -5)
            if last_game['home_away'] == 'away':
                from_tz = TEAM_TIMEZONES.get(last_game['opponent'], -5)
            else:
                from_tz = team_tz
            to_tz = TEAM_TIMEZONES.get(opponent_abbrev, -5)
            tz_diff = to_tz - from_tz
            if abs(tz_diff) >= 3:
                mult *= 0.97
                reasons.append(f"Cross-country (-3%)")

        summary = ", ".join(reasons) if reasons else f"{days_since} days rest"
        return mult, summary

    def calculate_streak_multiplier(self, team_abbrev, stats):
        last_10 = self.get_last_10_games(team_abbrev)
        if len(last_10) < 5:
            return 1.0, "Insufficient data", {}

        wins = sum(1 for g in last_10 if g['result'] == 'W')
        losses = sum(1 for g in last_10 if g['result'] == 'L')
        otl = sum(1 for g in last_10 if g['result'] == 'OTL')

        recent_win_pct = (wins + otl * 0.5) / len(last_10)

        season_wins = stats.get('wins', 0)
        season_losses = stats.get('losses', 0)
        season_otl = stats.get('otLosses', 0)
        total = season_wins + season_losses + season_otl
        if total == 0:
            return 1.0, "No season data", {}

        season_win_pct = (season_wins + season_otl * 0.5) / total
        form_diff = recent_win_pct - season_win_pct

        mult = 1.0
        if form_diff >= 0.15:
            mult = 1.05
        elif form_diff >= 0.10:
            mult = 1.03
        elif form_diff <= -0.15:
            mult = 0.95
        elif form_diff <= -0.10:
            mult = 0.97

        record = f"{wins}-{losses}-{otl}"
        return mult, record, {'recent_win_pct': recent_win_pct, 'season_win_pct': season_win_pct}

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

        summary = f"PP {team_st['pp_pct']*100:.0f}% vs PK {opp_st['pk_pct']*100:.0f}%"
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
            return 1.0, "Healthy"
        total = sum(self.get_player_importance(p, team_abbrev) for p in injuries)
        mult = max(0.90, 1.0 - total * 0.0005)
        summary = f"{len(injuries)} out" if len(injuries) > 2 else ", ".join(injuries[:2])
        return mult, summary

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
        if xg:
            xgf_pct = xg['xGoalsFor'] / (xg['xGoalsFor'] + xg['xGoalsAgainst'])
        else:
            xgf_pct = 0.5

        gf_pct = gf / (gf + ga) if (gf + ga) > 0 else 0.5
        off_quality = xgf_pct * 0.7 + gf_pct * 0.3

        goalie = self.get_starting_goalie(team_abbrev)
        goalie_score = self.calculate_goalie_score(goalie)

        base_score = off_quality * 35 + pts_pct * 25 + goalie_score * 30 + win_pct * 10

        fatigue_mult, fatigue_sum = self.calculate_fatigue_penalty(team_abbrev, opponent_abbrev, is_away)
        streak_mult, streak_sum, _ = self.calculate_streak_multiplier(team_abbrev, stats)
        st_mult, st_sum = self.calculate_special_teams_multiplier(team_abbrev, opponent_abbrev)
        injury_mult, injury_sum = self.calculate_injury_multiplier(team_abbrev)

        final_score = base_score * fatigue_mult * streak_mult * st_mult * injury_mult

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
# WORKER THREAD (Background Analysis)
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
            self.progress.emit(5, "Fetching schedule...")
            games = self.analyzer.get_games_for_date(self.date_str)

            if not games:
                self.error.emit(f"No games found for {self.date_str}")
                return

            self.progress.emit(10, "Loading injury data...")
            self.analyzer.scrape_all_injuries()

            results = []
            total = len(games)

            for i, game in enumerate(games):
                pct = 10 + int((i / total) * 85)
                self.progress.emit(pct, f"Analyzing {game['away']} @ {game['home']}...")

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

            self.progress.emit(100, "Complete!")
            self.result.emit(results)

        except Exception as e:
            self.error.emit(str(e))


# ============================================================================
# MAIN WINDOW
# ============================================================================

class MainWindow(QMainWindow):
    def __init__(self, data):
        super().__init__()
        self.data = data
        self.analyzer = NHLAnalyzer(data)
        self.worker = None
        self.init_ui()

    def init_ui(self):
        self.setWindowTitle("NHL Moneyline Generator")
        self.setMinimumSize(1000, 700)

        # Central widget
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        # Header
        header = QLabel("NHL Moneyline Generator")
        header.setFont(QFont("Arial", 24, QFont.Weight.Bold))
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(header)

        subtitle = QLabel("Advanced analytics for NHL betting")
        subtitle.setFont(QFont("Arial", 12))
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle.setStyleSheet("color: #666;")
        layout.addWidget(subtitle)

        # Controls
        controls = QHBoxLayout()

        date_label = QLabel("Select Date:")
        date_label.setFont(QFont("Arial", 11))
        controls.addWidget(date_label)

        self.date_edit = QDateEdit()
        self.date_edit.setDate(QDate.currentDate())
        self.date_edit.setCalendarPopup(True)
        self.date_edit.setFont(QFont("Arial", 11))
        self.date_edit.setMinimumWidth(150)
        controls.addWidget(self.date_edit)

        controls.addStretch()

        self.run_btn = QPushButton("Run Analysis")
        self.run_btn.setFont(QFont("Arial", 12, QFont.Weight.Bold))
        self.run_btn.setMinimumSize(150, 40)
        self.run_btn.setStyleSheet("""
            QPushButton {
                background-color: #2563eb;
                color: white;
                border: none;
                border-radius: 5px;
            }
            QPushButton:hover {
                background-color: #1d4ed8;
            }
            QPushButton:disabled {
                background-color: #93c5fd;
            }
        """)
        self.run_btn.clicked.connect(self.run_analysis)
        controls.addWidget(self.run_btn)

        layout.addLayout(controls)

        # Progress bar
        self.progress = QProgressBar()
        self.progress.setVisible(False)
        self.progress.setMinimumHeight(25)
        layout.addWidget(self.progress)

        self.status_label = QLabel("")
        self.status_label.setFont(QFont("Arial", 10))
        self.status_label.setStyleSheet("color: #666;")
        layout.addWidget(self.status_label)

        # Results table
        self.table = QTableWidget()
        self.table.setColumnCount(9)
        self.table.setHorizontalHeaderLabels([
            "Game", "Pick", "Confidence", "Diff",
            "Away Score", "Home Score",
            "Away Goalie", "Home Goalie", "Key Factors"
        ])

        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(8, QHeaderView.ResizeMode.Stretch)
        for i in range(1, 8):
            header.setSectionResizeMode(i, QHeaderView.ResizeMode.ResizeToContents)

        self.table.setAlternatingRowColors(True)
        self.table.setStyleSheet("""
            QTableWidget {
                gridline-color: #ddd;
                font-size: 11px;
            }
            QTableWidget::item {
                padding: 8px;
            }
            QHeaderView::section {
                background-color: #f3f4f6;
                padding: 8px;
                font-weight: bold;
                border: 1px solid #ddd;
            }
        """)

        layout.addWidget(self.table)

        # Footer
        footer = QLabel("Data: MoneyPuck.com | Injuries: ESPN.com | Schedule: NHL API")
        footer.setFont(QFont("Arial", 9))
        footer.setAlignment(Qt.AlignmentFlag.AlignCenter)
        footer.setStyleSheet("color: #999;")
        layout.addWidget(footer)

    def run_analysis(self):
        date = self.date_edit.date().toString("yyyy-MM-dd")

        self.run_btn.setEnabled(False)
        self.progress.setVisible(True)
        self.progress.setValue(0)
        self.table.setRowCount(0)

        self.worker = AnalysisWorker(self.analyzer, date)
        self.worker.progress.connect(self.update_progress)
        self.worker.result.connect(self.show_results)
        self.worker.error.connect(self.show_error)
        self.worker.start()

    def update_progress(self, value, status):
        self.progress.setValue(value)
        self.status_label.setText(status)

    def show_results(self, results):
        self.run_btn.setEnabled(True)
        self.progress.setVisible(False)

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
            self.table.setItem(row, 0, game_item)

            # Pick
            pick_item = QTableWidgetItem(r['pick'])
            pick_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            pick_item.setFont(QFont("Arial", 11, QFont.Weight.Bold))
            self.table.setItem(row, 1, pick_item)

            # Confidence
            diff = r['diff']
            if diff >= 10:
                conf = "Strong"
                color = QColor("#22c55e")
            elif diff >= 5:
                conf = "Moderate"
                color = QColor("#eab308")
            else:
                conf = "Close"
                color = QColor("#ef4444")

            conf_item = QTableWidgetItem(conf)
            conf_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            conf_item.setForeground(color)
            conf_item.setFont(QFont("Arial", 10, QFont.Weight.Bold))
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

            # Key factors
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

            factors_item = QTableWidgetItem(", ".join(factors) if factors else "-")
            self.table.setItem(row, 8, factors_item)

        self.status_label.setText(f"Analysis complete: {len(results)} games")

    def show_error(self, error):
        self.run_btn.setEnabled(True)
        self.progress.setVisible(False)
        self.status_label.setText(f"Error: {error}")
        QMessageBox.warning(self, "Error", error)


# ============================================================================
# LOADING SCREEN
# ============================================================================

class LoadingWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("NHL Moneyline Generator")
        self.setFixedSize(400, 200)

        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignmentFlag.AlignCenter)

        title = QLabel("NHL Moneyline Generator")
        title.setFont(QFont("Arial", 18, QFont.Weight.Bold))
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title)

        layout.addSpacing(20)

        self.status = QLabel("Loading data...")
        self.status.setFont(QFont("Arial", 11))
        self.status.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self.status)

        self.progress = QProgressBar()
        self.progress.setRange(0, 0)  # Indeterminate
        self.progress.setMinimumWidth(300)
        layout.addWidget(self.progress)


class DataLoader(QThread):
    finished = pyqtSignal(dict)
    status = pyqtSignal(str)

    def run(self):
        self.status.emit("Loading team data...")
        data = load_data()
        self.finished.emit(data)


# ============================================================================
# MAIN
# ============================================================================

def main():
    app = QApplication(sys.argv)

    # Set app style
    app.setStyle("Fusion")

    # Show loading screen
    loading = LoadingWindow()
    loading.show()

    # Load data in background
    loader = DataLoader()
    loader.status.connect(loading.status.setText)

    def on_data_loaded(data):
        loading.close()
        window = MainWindow(data)
        window.show()
        # Keep reference
        app.main_window = window

    loader.finished.connect(on_data_loaded)
    loader.start()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
