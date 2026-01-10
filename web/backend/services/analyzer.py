"""
HockeyQuant NHL Analyzer
Core prediction engine - no UI dependencies
"""

import requests
from datetime import datetime, timedelta
from typing import Optional, Dict, List, Any

from .constants import TEAM_TIMEZONES, NHL_DIVISIONS, NHL_CONFERENCES
from .data_loader import get_data_loader


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


class NHLAnalyzer:
    """NHL Game Prediction Analyzer"""

    def __init__(self, data_loader=None):
        self.base_url = "https://api-web.nhle.com/v1"
        self.data_loader = data_loader or get_data_loader()

        # Runtime caches to reduce API calls
        self._standings_cache = None
        self._schedule_cache = {}
        self._team_schedule_cache = {}

    def clear_runtime_caches(self):
        """Clear caches for a fresh analysis run"""
        self._standings_cache = None
        self._schedule_cache = {}
        self._team_schedule_cache = {}

    def get_team_stats(self, team_abbrev: str) -> Optional[Dict]:
        """Get team standings/stats from NHL API"""
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

    def get_recent_games(self, team_abbrev: str, lookback_days: int = 7) -> List[Dict]:
        """Get recent games for a team"""
        today = datetime.now()
        games = []

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
                    games.append({
                        'date': game_date_str,
                        'home_away': 'home',
                        'opponent': away_team,
                        'days_ago': days_ago
                    })
                elif away_team == team_abbrev:
                    games.append({
                        'date': game_date_str,
                        'home_away': 'away',
                        'opponent': home_team,
                        'days_ago': days_ago
                    })
            except:
                continue

        return sorted(games, key=lambda x: x['days_ago'])

    def get_last_10_games(self, team_abbrev: str) -> List[Dict]:
        """Get last 10 completed games for a team"""
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
                completed_games.append({
                    'date': game.get('gameDate', ''),
                    'opponent': opp,
                    'result': result,
                    'goals_for': gf,
                    'goals_against': ga
                })

        completed_games.sort(key=lambda x: x['date'], reverse=True)
        return completed_games[:10]

    def calculate_fatigue_penalty(self, team_abbrev: str, opponent_abbrev: str, is_away: bool) -> tuple:
        """Calculate fatigue/rest multiplier"""
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
            alternations = sum(
                1 for i in range(len(sorted_games) - 1)
                if sorted_games[i]['home_away'] != sorted_games[i+1]['home_away']
            )
            if alternations >= 2 and away_count >= 2:
                mult *= 0.97
                reasons.append("Choppy travel")
            elif away_count >= 3 and alternations <= 1:
                mult *= 0.98
                reasons.append("Road trip")
            elif away_count == 2 and home_count >= 1:
                mult *= 0.99
                reasons.append("Mixed schedule")

        if home_count >= 3 and away_count == 0:
            mult *= 1.02
            reasons.append("Homestand (+2%)")

        if is_away and recent_games:
            team_tz = TEAM_TIMEZONES.get(team_abbrev, -5)
            from_tz = TEAM_TIMEZONES.get(last_game['opponent'], -5) if last_game['home_away'] == 'away' else team_tz
            to_tz = TEAM_TIMEZONES.get(opponent_abbrev, -5)
            tz_diff = to_tz - from_tz
            if abs(tz_diff) >= 3:
                mult *= 0.97
                reasons.append("Cross-country")

        summary = ", ".join(reasons) if reasons else f"{days_since} days rest"
        return mult, summary

    def calculate_streak_multiplier(self, team_abbrev: str, stats: Dict) -> tuple:
        """Calculate hot/cold streak multiplier"""
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
            reasons.append("Hot")
        elif form_diff >= 0.10:
            mult = 1.03
            reasons.append("Warming")
        elif form_diff <= -0.15:
            mult = 0.95
            reasons.append("Cold")
        elif form_diff <= -0.10:
            mult = 0.97
            reasons.append("Cooling")

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

        # Consecutive wins/losses
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

    def get_special_teams_stats(self, team_abbrev: str) -> Optional[Dict]:
        """Get power play and penalty kill stats"""
        pp_data = self.data_loader.pp_data
        pk_data = self.data_loader.pk_data
        team_data = self.data_loader.team_data

        if pp_data is None or pk_data is None or team_data is None:
            return None

        team_all = team_data[team_data['team'] == team_abbrev]
        team_pp = pp_data[pp_data['team'] == team_abbrev]
        team_pk = pk_data[pk_data['team'] == team_abbrev]

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

    def calculate_special_teams_multiplier(self, team_abbrev: str, opponent_abbrev: str) -> tuple:
        """Calculate special teams matchup multiplier"""
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

    def get_player_importance(self, player_name: str, team_abbrev: str) -> float:
        """Calculate importance score for a player"""
        skater_data = self.data_loader.skater_data
        if skater_data is None:
            return 15

        player_lower = player_name.lower()
        team_players = skater_data[skater_data['team'] == team_abbrev]

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

    def calculate_injury_multiplier(self, team_abbrev: str) -> tuple:
        """Calculate injury impact multiplier"""
        injuries = self.data_loader.get_injuries(team_abbrev)
        if not injuries:
            return 1.0, "Healthy", {}

        total = sum(self.get_player_importance(p, team_abbrev) for p in injuries)
        mult = max(0.90, 1.0 - total * 0.0005)
        summary = f"{len(injuries)} out" if len(injuries) > 2 else ", ".join(injuries[:2])
        return mult, summary, {'count': len(injuries), 'total_impact': total}

    def get_team_relationship(self, team1: str, team2: str) -> tuple:
        """Get divisional/conference relationship and H2H game count"""
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

    def get_head_to_head_history(self, team1: str, team2: str, num_games: int) -> List[Dict]:
        """Get head-to-head game history"""
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

    def calculate_h2h_multiplier(self, team_abbrev: str, opponent_abbrev: str) -> tuple:
        """Calculate head-to-head history multiplier"""
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

    def get_team_xg(self, team_abbrev: str) -> Optional[Dict]:
        """Get expected goals data for a team"""
        team_data = self.data_loader.team_data
        if team_data is None:
            return None
        row = team_data[team_data['team'] == team_abbrev]
        if not row.empty:
            return {
                'xGoalsFor': float(row.iloc[0]['xGoalsFor']),
                'xGoalsAgainst': float(row.iloc[0]['xGoalsAgainst'])
            }
        return None

    def get_starting_goalie(self, team_abbrev: str) -> Optional[Dict]:
        """Get projected starting goalie and their stats"""
        goalie_data = self.data_loader.goalie_data
        if goalie_data is None:
            return None

        team_goalies = goalie_data[goalie_data['team'] == team_abbrev]
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

        return {
            'name': starter['name'],
            'gsax': gsax,
            'sv_pct': sv_pct,
            'gaa': gaa
        }

    def get_backup_goalie(self, team_abbrev: str) -> Optional[Dict]:
        """Get backup goalie and their stats"""
        goalie_data = self.data_loader.goalie_data
        if goalie_data is None:
            return None

        team_goalies = goalie_data[goalie_data['team'] == team_abbrev]
        if team_goalies.empty or len(team_goalies) < 2:
            return None

        qualified = team_goalies[team_goalies['games_played'] >= 3]
        if len(qualified) < 2:
            qualified = team_goalies

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

        return {
            'name': backup['name'],
            'gsax': gsax,
            'sv_pct': sv_pct,
            'gaa': gaa
        }

    def get_goalie_by_name(self, team_abbrev: str, goalie_name: str) -> Optional[Dict]:
        """Get a specific goalie by name for a team"""
        goalie_data = self.data_loader.goalie_data
        if goalie_data is None:
            return None

        team_goalies = goalie_data[goalie_data['team'] == team_abbrev]
        if team_goalies.empty:
            return None

        # Try exact match first
        match = team_goalies[team_goalies['name'] == goalie_name]
        if match.empty:
            # Try case-insensitive partial match
            goalie_lower = goalie_name.lower()
            for _, g in team_goalies.iterrows():
                if goalie_lower in g['name'].lower():
                    match = team_goalies[team_goalies['name'] == g['name']]
                    break

        if match.empty:
            return None

        goalie = match.iloc[0]
        xGoals = float(goalie['xGoals'])
        goals = float(goalie['goals'])
        ongoal = float(goalie['ongoal'])
        icetime = float(goalie['icetime'])
        gsax = xGoals - goals
        sv_pct = (ongoal - goals) / ongoal if ongoal > 0 else 0.900
        gaa = (goals / (icetime/60)) * 60 if icetime > 0 else 3.0

        return {
            'name': goalie['name'],
            'gsax': gsax,
            'sv_pct': sv_pct,
            'gaa': gaa
        }

    def calculate_goalie_score(self, goalie: Optional[Dict]) -> float:
        """Calculate composite goalie score"""
        if not goalie:
            return 0.5
        gsax_norm = max(0, min(1, 0.5 + goalie['gsax']/40))
        sv_norm = max(0, min(1, (goalie['sv_pct'] - 0.890) / 0.040))
        gaa_norm = max(0, min(1, 1 - (goalie['gaa'] - 2.0) / 2.0))
        return gsax_norm * 0.50 + sv_norm * 0.30 + gaa_norm * 0.20

    def analyze_team(self, team_abbrev: str, opponent_abbrev: str, is_away: bool, goalie_override: str = None) -> Optional[Dict]:
        """Full team analysis returning score and all factors

        Args:
            team_abbrev: Team abbreviation
            opponent_abbrev: Opponent team abbreviation
            is_away: Whether the team is playing away
            goalie_override: Optional goalie name to use instead of auto-selected starter
        """
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

        xga_pct = xg['xGoalsAgainst'] / (xg['xGoalsFor'] + xg['xGoalsAgainst']) if xg else 0.5
        ga_pct = ga / (gf + ga) if (gf + ga) > 0 else 0.5
        def_quality = (1 - xga_pct) * 0.8 + (1 - ga_pct) * 0.2

        # Use goalie override if provided, otherwise auto-select
        if goalie_override:
            goalie = self.get_goalie_by_name(team_abbrev, goalie_override)
            if not goalie:
                # Fall back to starter if override not found
                goalie = self.get_starting_goalie(team_abbrev)
        else:
            goalie = self.get_starting_goalie(team_abbrev)

        backup_goalie = self.get_backup_goalie(team_abbrev)
        goalie_score = self.calculate_goalie_score(goalie)

        # Base score calculation
        base_score = off_quality * 40 + def_quality * 15 + pts_pct * 10 + goalie_score * 30 + win_pct * 5

        # Calculate multipliers
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

    def get_games_for_date(self, date_str: str) -> List[Dict]:
        """Get all NHL games for a specific date"""
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

    def analyze_date(self, date_str: str, goalie_overrides: Dict[str, str] = None) -> List[Dict]:
        """Analyze all games for a given date

        Args:
            date_str: Date in YYYY-MM-DD format
            goalie_overrides: Optional dict mapping team abbrev to goalie name
                              e.g., {"TOR": "Joseph Woll", "MTL": "Sam Montembeault"}
        """
        # Only clear caches and re-scrape injuries on fresh analysis (no overrides)
        # When recalculating with goalie overrides, use cached data for speed
        if not goalie_overrides:
            self.clear_runtime_caches()
            self.data_loader.scrape_injuries()

        games = self.get_games_for_date(date_str)
        results = []
        goalie_overrides = goalie_overrides or {}

        for game in games:
            try:
                away_goalie = goalie_overrides.get(game['away'])
                home_goalie = goalie_overrides.get(game['home'])

                away_data = self.analyze_team(game['away'], game['home'], is_away=True, goalie_override=away_goalie)
                home_data = self.analyze_team(game['home'], game['away'], is_away=False, goalie_override=home_goalie)

                if away_data and home_data:
                    diff = home_data['final_score'] - away_data['final_score']
                    pick = home_data['team'] if diff > 0 else away_data['team']

                    # Build factors
                    factors = []
                    winner = home_data if diff > 0 else away_data
                    loser = away_data if diff > 0 else home_data

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

                    results.append({
                        'away': away_data,
                        'home': home_data,
                        'pick': pick,
                        'diff': abs(diff),
                        'factors': factors[:3],
                    })
            except Exception as e:
                print(f"Error analyzing {game['away']} @ {game['home']}: {e}")
                continue

        # Sort by confidence
        return sorted(results, key=lambda r: r['diff'], reverse=True)
