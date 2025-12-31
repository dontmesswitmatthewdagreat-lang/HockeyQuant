#!/usr/bin/env python3
"""
Phase 6: Injury Tracking - COMPLETE VERSION
Adds: Injury impact analysis with player importance scoring, projected starting goalies
Includes: Phase 1-5 (xG, goaltending, fatigue/travel, hot streaks, PP/PK)
100% automated using real NHL schedule data + DailyFaceoff scraping
"""

import requests
import pandas as pd
from datetime import datetime, timedelta
from bs4 import BeautifulSoup
import json
import os

print("\n" + "="*80)
print("PHASE 6: INJURY TRACKING + PROJECTED GOALIES")
print("="*80)

# Load data
print("\nLoading team xG data...")
try:
    TEAM_XG_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/teams.csv"
    TEAM_DATA_FULL = pd.read_csv(TEAM_XG_URL)
    TEAM_DATA = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == 'all']
    PP_DATA = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == '5on4']  # Power Play
    PK_DATA = TEAM_DATA_FULL[TEAM_DATA_FULL['situation'] == '4on5']  # Penalty Kill
    print(f"✅ Team data loaded: {len(TEAM_DATA)} teams (+ PP/PK data)")
except Exception as e:
    print(f"❌ Team data failed: {e}")
    TEAM_DATA = None
    TEAM_DATA_FULL = None
    PP_DATA = None
    PK_DATA = None

print("Loading goalie data...")
try:
    GOALIE_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/goalies.csv"
    GOALIE_DATA = pd.read_csv(GOALIE_URL)
    GOALIE_DATA = GOALIE_DATA[GOALIE_DATA['situation'] == 'all']
    print(f"✅ Goalie data loaded: {len(GOALIE_DATA)} goalies")
except Exception as e:
    print(f"❌ Goalie data failed: {e}")
    GOALIE_DATA = None

print("Loading skater data (for injury impact)...")
try:
    SKATER_URL = "https://moneypuck.com/moneypuck/playerData/seasonSummary/2025/regular/skaters.csv"
    SKATER_DATA = pd.read_csv(SKATER_URL)
    SKATER_DATA = SKATER_DATA[SKATER_DATA['situation'] == 'all']
    print(f"✅ Skater data loaded: {len(SKATER_DATA)} skaters")
except Exception as e:
    print(f"❌ Skater data failed: {e}")
    SKATER_DATA = None

print("\n" + "="*80 + "\n")

# NHL Team Timezones (for travel calculation)
TEAM_TIMEZONES = {
    'VAN': -8, 'SEA': -8, 'LAK': -8, 'ANA': -8, 'SJS': -8,  # Pacific
    'CGY': -7, 'EDM': -7, 'COL': -7, 'UTA': -7,  # Mountain
    'DAL': -6, 'MIN': -6, 'WPG': -6, 'CHI': -6, 'STL': -6, 'NSH': -6,  # Central
    'TOR': -5, 'BOS': -5, 'BUF': -5, 'DET': -5, 'MTL': -5, 'OTT': -5,  # Eastern
    'NYR': -5, 'NYI': -5, 'NJD': -5, 'PHI': -5, 'PIT': -5, 'WSH': -5,
    'CAR': -5, 'CBJ': -5, 'FLA': -5, 'TBL': -5,
}

# Team name mapping for DailyFaceoff URLs
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

# Injury cache file path
INJURY_CACHE_FILE = os.path.join(os.path.dirname(__file__), "injury_cache.json")


class FatigueAnalyzer:
    def __init__(self):
        self.base_url = "https://api-web.nhle.com/v1"
        self.team_data = TEAM_DATA
        self.goalie_data = GOALIE_DATA
        self.pp_data = PP_DATA
        self.pk_data = PK_DATA
        self.skater_data = SKATER_DATA
        self.injury_cache = self._load_injury_cache()

    def _load_injury_cache(self):
        """Load injury cache from file"""
        try:
            if os.path.exists(INJURY_CACHE_FILE):
                with open(INJURY_CACHE_FILE, 'r') as f:
                    return json.load(f)
        except Exception:
            pass
        return {}

    def _save_injury_cache(self):
        """Save injury cache to file"""
        try:
            with open(INJURY_CACHE_FILE, 'w') as f:
                json.dump(self.injury_cache, f, indent=2)
        except Exception:
            pass
    
    def get_team_stats(self, team_abbrev):
        """NHL API - team standings"""
        url = f"{self.base_url}/standings/now"
        try:
            response = requests.get(url)
            data = response.json()
            if 'standings' in data:
                for team in data['standings']:
                    if team.get('teamAbbrev', {}).get('default') == team_abbrev:
                        return team
        except Exception as e:
            print(f"  Error fetching stats: {e}")
        return None
    
    def get_recent_games(self, team_abbrev, lookback_days=7):
        """
        Get team's recent games by checking schedule
        Returns list of games with dates and home/away status
        NOTE: Starts from yesterday (days_ago=1) to avoid counting today's game
        """
        today = datetime.now()
        games = []
        
        print(f"  Checking last {lookback_days} days for {team_abbrev}...")
        
        # Start from 1 (yesterday) not 0 (today) to avoid counting today's game as "last game"
        for days_ago in range(1, lookback_days + 1):
            check_date = today - timedelta(days=days_ago)
            date_str = check_date.strftime("%Y-%m-%d")
            
            url = f"{self.base_url}/schedule/{date_str}"
            
            try:
                response = requests.get(url)
                data = response.json()
                
                if 'gameWeek' in data:
                    for day in data['gameWeek']:
                        if day.get('date') == date_str and 'games' in day:
                            for game in day['games']:
                                home_team = game.get('homeTeam', {}).get('abbrev')
                                away_team = game.get('awayTeam', {}).get('abbrev')
                                
                                if home_team == team_abbrev:
                                    games.append({
                                        'date': date_str,
                                        'home_away': 'home',
                                        'opponent': away_team,
                                        'days_ago': days_ago
                                    })
                                elif away_team == team_abbrev:
                                    games.append({
                                        'date': date_str,
                                        'home_away': 'away',
                                        'opponent': home_team,
                                        'days_ago': days_ago
                                    })
            except Exception as e:
                continue
        
        return sorted(games, key=lambda x: x['days_ago'])

    def get_last_10_games(self, team_abbrev):
        """
        Get team's last 10 completed games with results
        Returns list of games with date, opponent, result (W/L/OTL), goals for/against
        """
        url = f"{self.base_url}/club-schedule-season/{team_abbrev}/now"

        try:
            response = requests.get(url)
            data = response.json()

            completed_games = []

            if 'games' in data:
                for game in data['games']:
                    game_state = game.get('gameState', '')

                    # Only include completed games
                    if game_state in ['OFF', 'FINAL']:
                        home_team = game.get('homeTeam', {})
                        away_team = game.get('awayTeam', {})

                        is_home = home_team.get('abbrev') == team_abbrev

                        if is_home:
                            goals_for = home_team.get('score', 0)
                            goals_against = away_team.get('score', 0)
                            opponent = away_team.get('abbrev', 'UNK')
                        else:
                            goals_for = away_team.get('score', 0)
                            goals_against = home_team.get('score', 0)
                            opponent = home_team.get('abbrev', 'UNK')

                        # Determine result
                        if goals_for > goals_against:
                            result = 'W'
                        elif goals_for < goals_against:
                            # Check if OT/SO loss
                            period = game.get('periodDescriptor', {}).get('number', 3)
                            result = 'OTL' if period > 3 else 'L'
                        else:
                            result = 'L'  # Shouldn't happen in completed games

                        completed_games.append({
                            'date': game.get('gameDate', ''),
                            'opponent': opponent,
                            'result': result,
                            'goals_for': goals_for,
                            'goals_against': goals_against,
                            'is_home': is_home
                        })

            # Sort by date descending and take last 10
            completed_games.sort(key=lambda x: x['date'], reverse=True)
            return completed_games[:10]

        except Exception as e:
            print(f"  Error fetching last 10 games: {e}")
            return []

    def calculate_fatigue_penalty(self, team_abbrev, todays_opponent_abbrev, todays_game_is_away=False):
        """
        Calculate fatigue multiplier based on:
        - Back-to-back games (-4%)
        - Rest days (1 day = -2%, 3+ days = +1%)
        - Travel distance/direction (cross-country, eastbound vs westbound)
        
        Args:
            team_abbrev: The team we're analyzing
            todays_opponent_abbrev: Who they're playing today (needed for travel calc)
            todays_game_is_away: Is today's game away? (True/False)
            
        Returns:
            tuple: (fatigue_multiplier, summary_string)
        """
        recent_games = self.get_recent_games(team_abbrev)
        
        if not recent_games:
            print(f"  No recent games found for {team_abbrev}")
            return 1.0, "No recent data"
        
        last_game = recent_games[0]
        days_since_last = last_game['days_ago']
        
        fatigue_multiplier = 1.0
        reasons = []
        
        # BACK-TO-BACK DETECTION
        if days_since_last == 1:
            fatigue_multiplier *= 0.96  # -4% penalty
            reasons.append("Back-to-back (-4%)")
            
            # Extra penalty if both games away
            if last_game['home_away'] == 'away' and todays_game_is_away:
                fatigue_multiplier *= 0.98  # Additional -2%
                reasons.append("Away back-to-back (-2% extra)")
        
        # REST DAYS
        elif days_since_last == 2:
            fatigue_multiplier *= 0.98  # -2% for short rest
            reasons.append("1 day rest (-2%)")
        
        elif days_since_last >= 4:
            fatigue_multiplier *= 1.01  # +1% well rested
            reasons.append("Well rested 3+ days (+1%)")
        
        # ROAD TRIP / HOMESTAND ANALYSIS (last 7 days)
        # Count home vs away games and detect travel patterns
        away_games = [g for g in recent_games if g['home_away'] == 'away']
        home_games = [g for g in recent_games if g['home_away'] == 'home']
        
        away_count = len(away_games)
        home_count = len(home_games)
        total_recent_games = len(recent_games)
        
        # Detect "choppy" travel (alternating home/away)
        # Sort games by recency and check for alternating pattern
        if total_recent_games >= 3:
            sorted_games = sorted(recent_games, key=lambda x: x['days_ago'])
            alternations = 0
            for i in range(len(sorted_games) - 1):
                if sorted_games[i]['home_away'] != sorted_games[i+1]['home_away']:
                    alternations += 1
            
            # High alternation = choppy travel (more fatiguing)
            if alternations >= 2 and away_count >= 2:
                fatigue_multiplier *= 0.97  # -3% for choppy travel
                reasons.append(f"Choppy travel {away_count}A/{home_count}H (-3%)")
            
            # Extended road trip (3+ away, no choppy pattern)
            elif away_count >= 3 and alternations <= 1:
                fatigue_multiplier *= 0.98  # -2% for extended road trip
                reasons.append(f"Road trip {away_count} games (-2%)")
            
            # Short road trip (2 away games with some home games mixed)
            elif away_count == 2 and home_count >= 1:
                fatigue_multiplier *= 0.99  # -1% for mixed schedule
                reasons.append(f"Mixed schedule {away_count}A/{home_count}H (-1%)")
        
        # HOMESTAND BONUS
        # 3+ consecutive home games = fresh and rested
        if home_count >= 3 and away_count == 0:
            fatigue_multiplier *= 1.02  # +2% homestand bonus
            reasons.append(f"Homestand {home_count} games (+2%)")
        
        # TRAVEL PENALTY (only if playing away)
        if todays_game_is_away and len(recent_games) > 0:
            # Figure out WHERE they're traveling FROM
            team_home_tz = TEAM_TIMEZONES.get(team_abbrev, -5)
            
            if last_game['home_away'] == 'away':
                # They were away last game → traveling from that opponent's city
                travel_from_tz = TEAM_TIMEZONES.get(last_game['opponent'], -5)
            else:
                # They were home last game → traveling from their home city
                travel_from_tz = team_home_tz
            
            # Figure out WHERE they're traveling TO (today's opponent's city)
            travel_to_tz = TEAM_TIMEZONES.get(todays_opponent_abbrev, -5)
            
            # Calculate timezone difference
            # Positive = eastbound (harder), Negative = westbound (easier)
            timezone_diff = travel_to_tz - travel_from_tz
            timezone_diff_abs = abs(timezone_diff)
            
            # Apply penalties based on distance and direction
            if timezone_diff_abs >= 3:  # Cross-country travel (3+ timezones)
                fatigue_multiplier *= 0.97  # -3%
                reasons.append(f"Cross-country {timezone_diff_abs}TZ (-3%)")
                
                # Additional directional penalty
                if timezone_diff > 0:  # Eastbound (harder on body)
                    fatigue_multiplier *= 0.98  # -2% additional
                    reasons.append("Eastbound (-2% extra)")
                else:  # Westbound (still a penalty, but lighter)
                    fatigue_multiplier *= 0.99  # -1% additional
                    reasons.append("Westbound (-1% extra)")
                    
            elif timezone_diff_abs > 0:  # Shorter travel (1-2 timezones)
                if timezone_diff > 0:  # Eastbound
                    fatigue_multiplier *= 0.98  # -2%
                    reasons.append(f"Eastbound {timezone_diff_abs}TZ (-2%)")
                else:  # Westbound
                    fatigue_multiplier *= 0.99  # -1%
                    reasons.append(f"Westbound {timezone_diff_abs}TZ (-1%)")
        
        # Build summary
        summary = f"{days_since_last} days rest. " + ", ".join(reasons) if reasons else f"{days_since_last} days rest, no penalties"
        
        return fatigue_multiplier, summary

    def calculate_streak_multiplier(self, team_abbrev, season_stats):
        """
        Calculate streak/momentum multiplier based on:
        - Recent win % vs season win % (±5%)
        - GF/GA trend vs season average (±2% each)
        - Consecutive win/loss streaks (±2%)

        Args:
            team_abbrev: Team abbreviation
            season_stats: Dict with season totals (wins, losses, otLosses, goalFor, goalAgainst)

        Returns:
            tuple: (streak_multiplier, summary_string, streak_data_dict)
        """
        last_10 = self.get_last_10_games(team_abbrev)

        if len(last_10) < 5:
            print(f"  Not enough games for streak analysis ({len(last_10)} games)")
            return 1.0, "Insufficient data", {}

        # Calculate last 10 stats
        wins_last_10 = sum(1 for g in last_10 if g['result'] == 'W')
        losses_last_10 = sum(1 for g in last_10 if g['result'] == 'L')
        otl_last_10 = sum(1 for g in last_10 if g['result'] == 'OTL')

        gf_last_10 = sum(g['goals_for'] for g in last_10)
        ga_last_10 = sum(g['goals_against'] for g in last_10)

        games_last_10 = len(last_10)
        recent_win_pct = (wins_last_10 + otl_last_10 * 0.5) / games_last_10
        recent_gf_per_game = gf_last_10 / games_last_10
        recent_ga_per_game = ga_last_10 / games_last_10

        # Calculate season stats
        season_wins = season_stats.get('wins', 0)
        season_losses = season_stats.get('losses', 0)
        season_otl = season_stats.get('otLosses', 0)
        season_gf = season_stats.get('goalFor', 0)
        season_ga = season_stats.get('goalAgainst', 0)

        total_games = season_wins + season_losses + season_otl
        if total_games == 0:
            return 1.0, "No season data", {}

        season_win_pct = (season_wins + season_otl * 0.5) / total_games
        season_gf_per_game = season_gf / total_games
        season_ga_per_game = season_ga / total_games

        streak_mult = 1.0
        reasons = []

        # A. RECENT FORM VS SEASON AVERAGE (Win %)
        form_diff = recent_win_pct - season_win_pct

        if form_diff >= 0.15:
            streak_mult = 1.05
            reasons.append(f"Hot streak +{form_diff*100:.0f}% vs season (+5%)")
        elif form_diff >= 0.10:
            streak_mult = 1.03
            reasons.append(f"Warming up +{form_diff*100:.0f}% vs season (+3%)")
        elif form_diff <= -0.15:
            streak_mult = 0.95
            reasons.append(f"Cold streak {form_diff*100:.0f}% vs season (-5%)")
        elif form_diff <= -0.10:
            streak_mult = 0.97
            reasons.append(f"Cooling down {form_diff*100:.0f}% vs season (-3%)")

        # B. GOAL DIFFERENTIAL TREND
        # Offensive trend
        gf_diff = recent_gf_per_game - season_gf_per_game
        if gf_diff >= 0.5:
            streak_mult *= 1.02
            reasons.append(f"Scoring up +{gf_diff:.1f} GF/game (+2%)")
        elif gf_diff >= 0.3:
            streak_mult *= 1.01
            reasons.append(f"Scoring up +{gf_diff:.1f} GF/game (+1%)")
        elif gf_diff <= -0.5:
            streak_mult *= 0.98
            reasons.append(f"Scoring down {gf_diff:.1f} GF/game (-2%)")
        elif gf_diff <= -0.3:
            streak_mult *= 0.99
            reasons.append(f"Scoring down {gf_diff:.1f} GF/game (-1%)")

        # Defensive trend
        ga_diff = recent_ga_per_game - season_ga_per_game
        if ga_diff <= -0.5:
            streak_mult *= 1.02
            reasons.append(f"Defense up {ga_diff:.1f} GA/game (+2%)")
        elif ga_diff <= -0.3:
            streak_mult *= 1.01
            reasons.append(f"Defense up {ga_diff:.1f} GA/game (+1%)")
        elif ga_diff >= 0.5:
            streak_mult *= 0.98
            reasons.append(f"Defense down +{ga_diff:.1f} GA/game (-2%)")
        elif ga_diff >= 0.3:
            streak_mult *= 0.99
            reasons.append(f"Defense down +{ga_diff:.1f} GA/game (-1%)")

        # C. CONSECUTIVE WIN/LOSS STREAK
        consecutive_wins = 0
        consecutive_losses = 0

        for game in last_10:
            if game['result'] == 'W':
                if consecutive_losses == 0:
                    consecutive_wins += 1
                else:
                    break
            else:
                if consecutive_wins == 0:
                    consecutive_losses += 1
                else:
                    break

        if consecutive_wins >= 5:
            streak_mult *= 1.02
            reasons.append(f"{consecutive_wins}-game win streak (+2%)")
        elif consecutive_losses >= 5:
            streak_mult *= 0.98
            reasons.append(f"{consecutive_losses}-game losing streak (-2%)")

        # Build record string
        record_str = f"{wins_last_10}-{losses_last_10}-{otl_last_10}"

        # Build summary
        summary = f"{record_str} in last 10. " + ", ".join(reasons) if reasons else f"{record_str} in last 10, neutral form"

        streak_data = {
            'last_10_record': record_str,
            'recent_win_pct': recent_win_pct,
            'season_win_pct': season_win_pct,
            'recent_gf_per_game': recent_gf_per_game,
            'season_gf_per_game': season_gf_per_game,
            'recent_ga_per_game': recent_ga_per_game,
            'season_ga_per_game': season_ga_per_game,
            'consecutive_wins': consecutive_wins,
            'consecutive_losses': consecutive_losses,
        }

        return streak_mult, summary, streak_data

    def get_special_teams_stats(self, team_abbrev):
        """
        Get PP/PK stats for a team
        Returns: pp_pct, pk_pct, pp_opportunities_per_game, pk_situations_per_game
        """
        if self.team_data is None or self.pp_data is None or self.pk_data is None:
            return None

        # Get base stats (penalties drawn/taken)
        team_all = self.team_data[self.team_data['team'] == team_abbrev]
        team_pp = self.pp_data[self.pp_data['team'] == team_abbrev]
        team_pk = self.pk_data[self.pk_data['team'] == team_abbrev]

        if team_all.empty or team_pp.empty or team_pk.empty:
            return None

        games = float(team_all.iloc[0]['games_played'])
        penalties_drawn = float(team_all.iloc[0]['penaltiesAgainst'])  # PP opportunities
        penalties_taken = float(team_all.iloc[0]['penaltiesFor'])       # PK situations

        pp_goals = float(team_pp.iloc[0]['goalsFor'])
        pk_goals_against = float(team_pk.iloc[0]['goalsAgainst'])

        # Calculate percentages
        pp_pct = pp_goals / penalties_drawn if penalties_drawn > 0 else 0.20
        pk_pct = 1 - (pk_goals_against / penalties_taken) if penalties_taken > 0 else 0.80

        # Calculate opportunities per game
        pp_opps_per_game = penalties_drawn / games if games > 0 else 3.0
        pk_sits_per_game = penalties_taken / games if games > 0 else 3.0

        return {
            'pp_pct': pp_pct,
            'pk_pct': pk_pct,
            'pp_opportunities_per_game': pp_opps_per_game,
            'pk_situations_per_game': pk_sits_per_game,
            'pp_goals': pp_goals,
            'pk_goals_against': pk_goals_against,
        }

    def calculate_special_teams_multiplier(self, team_abbrev, opponent_abbrev):
        """
        Calculate special teams matchup multiplier
        - Team's PP vs Opponent's PK (weighted by opponent's penalties/game)
        - Team's PK vs Opponent's PP (weighted by team's penalties/game)
        """
        team_st = self.get_special_teams_stats(team_abbrev)
        opp_st = self.get_special_teams_stats(opponent_abbrev)

        if not team_st or not opp_st:
            return 1.0, "No ST data", {}

        # TEAM'S PP ADVANTAGE vs OPPONENT'S PK
        # PP edge = team's conversion rate vs opponent's goals allowed rate
        opp_pk_weakness = 1 - opp_st['pk_pct']  # How often opponent allows PP goals
        team_pp_edge = team_st['pp_pct'] - opp_pk_weakness
        # Weight by how often opponent takes penalties
        team_pp_impact = team_pp_edge * opp_st['pk_situations_per_game']

        # TEAM'S PK DISADVANTAGE vs OPPONENT'S PP
        opp_pp_strength = opp_st['pp_pct']
        team_pk_strength = team_st['pk_pct']
        team_pk_edge = team_pk_strength - (1 - opp_pp_strength)
        # Weight by how often team takes penalties
        team_pk_impact = team_pk_edge * team_st['pk_situations_per_game']

        # Net special teams edge (positive = advantage)
        net_st_edge = team_pp_impact + team_pk_impact

        # Convert to multiplier (scale factor tuned for ~±5% max impact)
        multiplier = 1.0 + (net_st_edge * 0.015)
        multiplier = max(0.95, min(1.05, multiplier))

        # Build summary
        reasons = []
        if team_st['pp_pct'] > 0.22:
            reasons.append(f"Strong PP {team_st['pp_pct']*100:.1f}%")
        elif team_st['pp_pct'] < 0.17:
            reasons.append(f"Weak PP {team_st['pp_pct']*100:.1f}%")

        if opp_st['pk_pct'] < 0.78:
            reasons.append(f"vs weak PK {opp_st['pk_pct']*100:.1f}%")
        elif opp_st['pk_pct'] > 0.82:
            reasons.append(f"vs strong PK {opp_st['pk_pct']*100:.1f}%")

        summary = ", ".join(reasons) if reasons else "Neutral ST matchup"

        st_data = {
            'team_pp_pct': team_st['pp_pct'],
            'team_pk_pct': team_st['pk_pct'],
            'opp_pp_pct': opp_st['pp_pct'],
            'opp_pk_pct': opp_st['pk_pct'],
            'net_st_edge': net_st_edge,
        }

        return multiplier, summary, st_data

    def scrape_all_injuries(self):
        """
        Scrape all NHL injuries from ESPN (more reliable than per-team scraping)
        Returns dict of team_abbrev -> list of injured player names
        """
        url = "https://www.espn.com/nhl/injuries"

        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
            }
            response = requests.get(url, headers=headers, timeout=15)
            soup = BeautifulSoup(response.text, 'html.parser')

            all_injuries = {}

            # ESPN organizes injuries in ResponsiveTable sections, one per team
            sections = soup.find_all('div', class_='ResponsiveTable')

            for section in sections:
                # Find team name from injuries__teamName span
                team_span = section.find('span', class_='injuries__teamName')
                if not team_span:
                    continue
                team_name = team_span.get_text(strip=True)
                team_abbrev = self._espn_team_to_abbrev(team_name)

                if not team_abbrev:
                    continue

                # Find the table within this section
                table = section.find('table')
                if not table:
                    continue

                players = []
                rows = table.find_all('tr')[1:]  # Skip header row

                for row in rows:
                    cells = row.find_all('td')
                    if len(cells) >= 2:
                        # First cell has player name, second has position
                        player_name = cells[0].get_text(strip=True)
                        position = cells[1].get_text(strip=True)

                        # Skip goalies (their impact is already in goalie score)
                        if position != 'G' and player_name:
                            players.append(player_name)

                if players:
                    all_injuries[team_abbrev] = players

            # Update cache
            for team, injuries in all_injuries.items():
                if injuries:
                    self.injury_cache[team] = {
                        'injuries': injuries,
                        'timestamp': datetime.now().isoformat()
                    }
            self._save_injury_cache()

            return all_injuries

        except Exception as e:
            print(f"  ESPN injury scrape failed: {e}")
            return {}

    def _espn_team_to_abbrev(self, team_name):
        """Convert ESPN team name to abbreviation"""
        team_map = {
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
            # Also handle partial matches
            'Ducks': 'ANA', 'Bruins': 'BOS', 'Sabres': 'BUF', 'Flames': 'CGY',
            'Hurricanes': 'CAR', 'Blackhawks': 'CHI', 'Avalanche': 'COL', 'Blue Jackets': 'CBJ',
            'Stars': 'DAL', 'Red Wings': 'DET', 'Oilers': 'EDM', 'Panthers': 'FLA',
            'Kings': 'LAK', 'Wild': 'MIN', 'Canadiens': 'MTL', 'Predators': 'NSH',
            'Devils': 'NJD', 'Islanders': 'NYI', 'Rangers': 'NYR', 'Senators': 'OTT',
            'Flyers': 'PHI', 'Penguins': 'PIT', 'Sharks': 'SJS', 'Kraken': 'SEA',
            'Blues': 'STL', 'Lightning': 'TBL', 'Maple Leafs': 'TOR', 'Canucks': 'VAN',
            'Golden Knights': 'VGK', 'Capitals': 'WSH', 'Jets': 'WPG',
        }
        for name, abbrev in team_map.items():
            if name.lower() in team_name.lower():
                return abbrev
        return None

    def scrape_team_injuries(self, team_abbrev):
        """
        Get injuries for a specific team
        Uses cached ESPN data or fetches fresh
        """
        # Check if we have fresh cached data (< 2 hours old)
        if team_abbrev in self.injury_cache:
            cached = self.injury_cache[team_abbrev]
            try:
                cached_time = datetime.fromisoformat(cached['timestamp'])
                if datetime.now() - cached_time < timedelta(hours=2):
                    return cached.get('injuries', [])
            except Exception:
                pass

        # Fetch fresh data from ESPN (gets all teams at once)
        all_injuries = self.scrape_all_injuries()
        return all_injuries.get(team_abbrev, [])

    def get_cached_injuries(self, team_abbrev):
        """Get cached injuries if fresh (< 24 hours old)"""
        if team_abbrev in self.injury_cache:
            cached = self.injury_cache[team_abbrev]
            try:
                cached_time = datetime.fromisoformat(cached['timestamp'])
                if datetime.now() - cached_time < timedelta(hours=24):
                    return cached.get('injuries', [])
            except Exception:
                pass
        return []

    def get_team_injuries(self, team_abbrev):
        """Get injuries - try scraping, fallback to cache"""
        injuries = self.scrape_team_injuries(team_abbrev)
        if not injuries:
            injuries = self.get_cached_injuries(team_abbrev)
        return injuries

    def get_player_importance(self, player_name, team_abbrev):
        """
        Calculate player importance score (0-100)
        Based on points, TOI, and xGF
        """
        if self.skater_data is None:
            return 0

        # Try to find player in skater data
        # Match by name (case-insensitive partial match)
        player_name_lower = player_name.lower()
        team_players = self.skater_data[self.skater_data['team'] == team_abbrev]

        matched_player = None
        for _, player in team_players.iterrows():
            if player_name_lower in str(player.get('name', '')).lower():
                matched_player = player
                break

        if matched_player is None:
            # Try fuzzy match on just last name
            last_name = player_name.split()[-1].lower() if player_name else ''
            for _, player in team_players.iterrows():
                if last_name in str(player.get('name', '')).lower():
                    matched_player = player
                    break

        if matched_player is None:
            return 15  # Default low importance if player not found

        # Get stats
        goals = float(matched_player.get('I_F_goals', 0))
        primary_assists = float(matched_player.get('I_F_primaryAssists', 0))
        secondary_assists = float(matched_player.get('I_F_secondaryAssists', 0))
        points = goals + primary_assists + secondary_assists
        icetime = float(matched_player.get('icetime', 0)) / 3600  # Convert to hours
        xgf = float(matched_player.get('xGoalsFor', 0))

        # Normalize (based on typical max values for a full season)
        # Max points ~130, Max TOI ~2000 mins (~33 hrs), Max xGF ~80
        points_norm = min(1.0, points / 100)
        toi_norm = min(1.0, icetime / 30)
        xgf_norm = min(1.0, xgf / 60)

        # Calculate importance
        importance = (points_norm * 0.40 + toi_norm * 0.35 + xgf_norm * 0.25) * 100

        # Position adjustment (defensemen slightly higher due to fewer of them)
        position = str(matched_player.get('position', ''))
        if 'D' in position.upper():
            importance *= 1.1

        return min(100, importance)

    def calculate_injury_multiplier(self, team_abbrev):
        """
        Calculate injury impact multiplier
        - Gets injured players list
        - Sums their importance scores
        - Returns multiplier (0.90 - 1.00)
        """
        injuries = self.get_team_injuries(team_abbrev)

        if not injuries:
            return 1.0, "No injuries reported", {}

        total_importance = 0
        injured_details = []

        for player_name in injuries:
            importance = self.get_player_importance(player_name, team_abbrev)
            total_importance += importance
            injured_details.append(f"{player_name} ({importance:.0f})")

        # Convert to multiplier: -0.5% per 10 importance points, max -10%
        multiplier = 1.0 - (total_importance * 0.0005)
        multiplier = max(0.90, min(1.00, multiplier))

        # Build summary
        if len(injured_details) <= 3:
            summary = f"Missing: {', '.join(injured_details)}"
        else:
            summary = f"Missing {len(injuries)} players (impact: {total_importance:.0f})"

        injury_data = {
            'injured_players': injuries,
            'total_importance': total_importance,
        }

        return multiplier, summary, injury_data

    def scrape_starting_goalie(self, team_abbrev):
        """
        Scrape tonight's projected starting goalie from DailyFaceoff
        Returns goalie name or None if not found
        """
        try:
            url = "https://www.dailyfaceoff.com/starting-goalies/"
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
            }
            response = requests.get(url, headers=headers, timeout=10)
            soup = BeautifulSoup(response.text, 'html.parser')

            team_name = TEAM_NAMES_DF.get(team_abbrev, '').replace('-', ' ')

            # Look for team name and find associated goalie
            for elem in soup.find_all(string=lambda t: t and team_name.lower() in t.lower()):
                parent = elem.find_parent(['div', 'tr', 'td'])
                if parent:
                    # Look for goalie name nearby
                    links = parent.find_all('a', href=lambda x: x and '/players/' in x)
                    for link in links:
                        goalie_name = link.get_text(strip=True)
                        if goalie_name and len(goalie_name) > 2:
                            return goalie_name

            return None

        except Exception:
            return None

    def get_goalie_stats_by_name(self, goalie_name):
        """Get goalie stats by name (for projected starter)"""
        if self.goalie_data is None or not goalie_name:
            return None

        goalie_name_lower = goalie_name.lower()

        for _, goalie in self.goalie_data.iterrows():
            if goalie_name_lower in str(goalie.get('name', '')).lower():
                xGoals = float(goalie['xGoals'])
                goals = float(goalie['goals'])
                ongoal = float(goalie['ongoal'])
                icetime = float(goalie['icetime'])

                gsax = xGoals - goals
                sv_pct = (ongoal - goals) / ongoal if ongoal > 0 else 0.900
                icetime_minutes = icetime / 60
                gaa = (goals / icetime_minutes) * 60 if icetime_minutes > 0 else 3.0

                return {
                    'name': goalie['name'],
                    'gsax': gsax,
                    'sv_pct': sv_pct,
                    'gaa': gaa,
                }

        return None

    def get_projected_starter(self, team_abbrev):
        """
        Get tonight's projected starting goalie
        Try scraping first, fallback to most games played
        """
        # Try to get tonight's starter from DailyFaceoff
        starter_name = self.scrape_starting_goalie(team_abbrev)
        if starter_name:
            goalie_stats = self.get_goalie_stats_by_name(starter_name)
            if goalie_stats:
                return goalie_stats

        # Fallback to existing method (most games played)
        return self.get_starting_goalie(team_abbrev)

    def get_team_xg(self, team_abbrev):
        """Get xG from MoneyPuck"""
        if self.team_data is None:
            return None
        team_row = self.team_data[self.team_data['team'] == team_abbrev]
        if not team_row.empty:
            return {
                'xGoalsFor': float(team_row.iloc[0]['xGoalsFor']),
                'xGoalsAgainst': float(team_row.iloc[0]['xGoalsAgainst']),
            }
        return None
    
    def get_starting_goalie(self, team_abbrev):
        """Get starting goalie stats"""
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
        icetime_minutes = icetime / 60
        gaa = (goals / icetime_minutes) * 60 if icetime_minutes > 0 else 3.0
        
        return {
            'name': starter['name'],
            'gsax': gsax,
            'sv_pct': sv_pct,
            'gaa': gaa,
        }
    
    def calculate_goalie_score(self, goalie_stats):
        """GSAx 50%, Sv% 30%, GAA 20%"""
        if not goalie_stats:
            return 0.5
        
        gsax = goalie_stats['gsax']
        sv_pct = goalie_stats['sv_pct']
        gaa = goalie_stats['gaa']
        
        gsax_normalized = 0.5 + (gsax / 40)
        gsax_normalized = max(0, min(1, gsax_normalized))
        
        sv_normalized = (sv_pct - 0.890) / 0.040
        sv_normalized = max(0, min(1, sv_normalized))
        
        gaa_normalized = 1 - ((gaa - 2.0) / 2.0)
        gaa_normalized = max(0, min(1, gaa_normalized))
        
        return (gsax_normalized * 0.50) + (sv_normalized * 0.30) + (gaa_normalized * 0.20)
    
    def calculate_full_score(self, team_abbrev, opponent_abbrev, is_away_game=False):
        """
        Calculate complete team score WITH fatigue
        
        Args:
            team_abbrev: Team to analyze
            opponent_abbrev: Today's opponent (needed for travel calculation)
            is_away_game: Is this team playing away? (True/False)
        """
        print(f"\n{'='*80}")
        print(f"Analyzing: {team_abbrev}")
        print(f"{'='*80}")
        
        stats = self.get_team_stats(team_abbrev)
        if not stats:
            print("Could not fetch stats")
            return 0, {}
        
        # Base stats
        wins = stats.get('wins', 0)
        losses = stats.get('losses', 0)
        ot_losses = stats.get('otLosses', 0)
        points = stats.get('points', 0)
        actual_gf = stats.get('goalFor', 0)
        actual_ga = stats.get('goalAgainst', 0)
        
        total_games = wins + losses + ot_losses
        if total_games == 0:
            return 0, {}
        
        win_pct = (wins + (ot_losses * 0.5)) / total_games
        points_pct = points / (total_games * 2)
        
        # xG
        xg = self.get_team_xg(team_abbrev)
        if xg:
            xGF_pct = xg['xGoalsFor'] / (xg['xGoalsFor'] + xg['xGoalsAgainst'])
        else:
            xGF_pct = 0.5
        
        actual_GF_pct = actual_gf / (actual_gf + actual_ga) if (actual_gf + actual_ga) > 0 else 0.5
        offensive_quality = (xGF_pct * 0.7) + (actual_GF_pct * 0.3)
        
        # Goalie (now uses projected starter from DailyFaceoff when available)
        goalie = self.get_projected_starter(team_abbrev)
        goalie_score = self.calculate_goalie_score(goalie)

        # BASE SCORE (before multipliers)
        base_score = (offensive_quality * 35) + (points_pct * 25) + (goalie_score * 30) + (win_pct * 10)

        # FATIGUE CALCULATION (NOW WITH OPPONENT INFO!)
        fatigue_mult, fatigue_summary = self.calculate_fatigue_penalty(team_abbrev, opponent_abbrev, is_away_game)

        # STREAK/MOMENTUM CALCULATION (Phase 4)
        streak_mult, streak_summary, streak_data = self.calculate_streak_multiplier(team_abbrev, stats)

        # SPECIAL TEAMS MATCHUP (Phase 5)
        st_mult, st_summary, st_data = self.calculate_special_teams_multiplier(team_abbrev, opponent_abbrev)

        # INJURY IMPACT (Phase 6)
        injury_mult, injury_summary, injury_data = self.calculate_injury_multiplier(team_abbrev)

        # FINAL SCORE (with all multipliers)
        final_score = base_score * fatigue_mult * streak_mult * st_mult * injury_mult

        print(f"\nBase Score: {base_score:.2f}")
        print(f"Fatigue Analysis: {fatigue_summary}")
        print(f"Fatigue Multiplier: {fatigue_mult:.3f}")
        print(f"Streak Analysis: {streak_summary}")
        print(f"Streak Multiplier: {streak_mult:.3f}")
        print(f"Special Teams: {st_summary}")
        print(f"ST Multiplier: {st_mult:.3f}")
        print(f"Injuries: {injury_summary}")
        print(f"Injury Multiplier: {injury_mult:.3f}")
        print(f"FINAL Score: {final_score:.2f}")

        if goalie:
            print(f"\nGoalie: {goalie['name']} (GSAx: {goalie['gsax']:.1f})")

        return final_score, {
            'base_score': base_score,
            'fatigue_multiplier': fatigue_mult,
            'fatigue_summary': fatigue_summary,
            'streak_multiplier': streak_mult,
            'streak_summary': streak_summary,
            'streak_data': streak_data,
            'st_multiplier': st_mult,
            'st_summary': st_summary,
            'st_data': st_data,
            'injury_multiplier': injury_mult,
            'injury_summary': injury_summary,
            'injury_data': injury_data,
            'goalie': goalie,
        }
    
    def compare_matchup(self, away_abbrev, home_abbrev):
        """Compare two teams with full fatigue analysis"""
        
        print("\n" + "="*80)
        print(f"MATCHUP: {away_abbrev} @ {home_abbrev}")
        print("="*80)
        
        # Calculate scores with opponent info
        away_score, away_data = self.calculate_full_score(
            away_abbrev, 
            opponent_abbrev=home_abbrev, 
            is_away_game=True
        )
        
        home_score, home_data = self.calculate_full_score(
            home_abbrev, 
            opponent_abbrev=away_abbrev, 
            is_away_game=False
        )
        
        print("\n" + "="*80)
        print("RESULT")
        print("="*80)
        
        print(f"\nAway: {away_abbrev} - {away_score:.2f}")
        print(f"Home: {home_abbrev} - {home_score:.2f}")
        
        winner = home_abbrev if home_score > away_score else away_abbrev
        diff = abs(home_score - away_score)
        
        print(f"\n📊 PICK: {winner} (Difference: {diff:.2f})")
        
        print("\n")


def main():
    if TEAM_DATA is None or GOALIE_DATA is None:
        print("ERROR: Data not loaded - check network connection")
        return
    
    analyzer = FatigueAnalyzer()
    
    # Get today's date
    today = datetime.now().strftime("%Y-%m-%d")
    print(f"Fetching games for: {today}")
    
    # Fetch today's schedule
    url = f"https://api-web.nhle.com/v1/schedule/{today}"
    
    try:
        response = requests.get(url)
        data = response.json()
        
        games_found = False
        
        if 'gameWeek' in data:
            for day in data['gameWeek']:
                if day.get('date') == today and 'games' in day:
                    for game in day['games']:
                        away_team = game.get('awayTeam', {}).get('abbrev')
                        home_team = game.get('homeTeam', {}).get('abbrev')
                        
                        if away_team and home_team:
                            games_found = True
                            analyzer.compare_matchup(away_team, home_team)
        
        if not games_found:
            print(f"\nNo games scheduled for {today}")
            print("\nTesting with sample matchup instead:")
            analyzer.compare_matchup("TOR", "BOS")
            
    except Exception as e:
        print(f"Error fetching schedule: {e}")
        print("\nTesting with sample matchup instead:")
        analyzer.compare_matchup("TOR", "BOS")


if __name__ == "__main__":
    main()