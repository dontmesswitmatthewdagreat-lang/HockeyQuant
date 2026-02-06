"""
HockeyQuant Model Engine
Calculates predictions using custom weight configurations
"""

from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta, timezone

from .analyzer import NHLAnalyzer
from .data_loader import get_data_loader


# Official HockeyQuant model weights (baseline)
OFFICIAL_WEIGHTS = {
    'offensive': 40.0,
    'defensive': 15.0,
    'goaltending': 30.0,
    'points_pct': 10.0,
    'win_rate': 5.0
}


class ModelEngine:
    """Engine for running predictions with custom weight configurations"""

    def __init__(self):
        self.data_loader = get_data_loader()
        self.analyzer = NHLAnalyzer(self.data_loader)

    def calculate_base_score_with_weights(
        self,
        off_quality: float,
        def_quality: float,
        goalie_score: float,
        pts_pct: float,
        win_pct: float,
        weights: Dict[str, float]
    ) -> float:
        """
        Calculate base score using custom weights.

        Args:
            off_quality: Offensive quality metric (0-1)
            def_quality: Defensive quality metric (0-1)
            goalie_score: Goalie score metric (0-1)
            pts_pct: Points percentage (0-1)
            win_pct: Win percentage (0-1)
            weights: Dict with keys: offensive, defensive, goaltending, points_pct, win_rate

        Returns:
            Weighted base score
        """
        return (
            off_quality * weights['offensive'] +
            def_quality * weights['defensive'] +
            goalie_score * weights['goaltending'] +
            pts_pct * weights['points_pct'] +
            win_pct * weights['win_rate']
        )

    def analyze_team_with_weights(
        self,
        team_abbrev: str,
        opponent_abbrev: str,
        is_away: bool,
        weights: Dict[str, float]
    ) -> Optional[Dict]:
        """
        Analyze a team using custom weights.
        Similar to analyzer.analyze_team but with custom weight calculation.
        """
        stats = self.analyzer.get_team_stats(team_abbrev)
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

        xg = self.analyzer.get_team_xg(team_abbrev)
        xgf_pct = xg['xGoalsFor'] / (xg['xGoalsFor'] + xg['xGoalsAgainst']) if xg else 0.5
        gf_pct = gf / (gf + ga) if (gf + ga) > 0 else 0.5
        off_quality = xgf_pct * 0.8 + gf_pct * 0.2

        xga_pct = xg['xGoalsAgainst'] / (xg['xGoalsFor'] + xg['xGoalsAgainst']) if xg else 0.5
        ga_pct = ga / (gf + ga) if (gf + ga) > 0 else 0.5
        def_quality = (1 - xga_pct) * 0.8 + (1 - ga_pct) * 0.2

        goalie = self.analyzer.get_starting_goalie(team_abbrev)
        goalie_score = self.analyzer.calculate_goalie_score(goalie)

        # Calculate base score with custom weights
        base_score = self.calculate_base_score_with_weights(
            off_quality, def_quality, goalie_score, pts_pct, win_pct, weights
        )

        # Calculate multipliers (same as official model)
        fatigue_mult, fatigue_sum = self.analyzer.calculate_fatigue_penalty(team_abbrev, opponent_abbrev, is_away)
        streak_mult, streak_sum, _ = self.analyzer.calculate_streak_multiplier(team_abbrev, stats)
        st_mult, st_sum = self.analyzer.calculate_special_teams_multiplier(team_abbrev, opponent_abbrev)
        injury_mult, injury_sum, _ = self.analyzer.calculate_injury_multiplier(team_abbrev)
        h2h_mult, h2h_sum, _ = self.analyzer.calculate_h2h_multiplier(team_abbrev, opponent_abbrev)

        final_score = base_score * fatigue_mult * streak_mult * st_mult * injury_mult * h2h_mult

        return {
            'team': team_abbrev,
            'base_score': base_score,
            'final_score': final_score,
            'goalie': goalie['name'] if goalie else 'Unknown',
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

    def run_predictions_with_weights(
        self,
        date_str: str,
        weights: Dict[str, float]
    ) -> List[Dict]:
        """
        Run predictions for all games on a date using custom weights.

        Args:
            date_str: Date in YYYY-MM-DD format
            weights: Custom weight configuration

        Returns:
            List of prediction results sorted by confidence
        """
        # Clear caches for fresh analysis
        self.analyzer.clear_runtime_caches()
        self.data_loader.scrape_injuries()
        self.data_loader.scrape_confirmed_starters()

        games = self.analyzer.get_games_for_date(date_str)
        results = []

        for game in games:
            try:
                away_data = self.analyze_team_with_weights(
                    game['away'], game['home'], is_away=True, weights=weights
                )
                home_data = self.analyze_team_with_weights(
                    game['home'], game['away'], is_away=False, weights=weights
                )

                if away_data and home_data:
                    diff = home_data['final_score'] - away_data['final_score']
                    pick = home_data['team'] if diff > 0 else away_data['team']

                    # Determine confidence level
                    abs_diff = abs(diff)
                    if abs_diff >= 10:
                        confidence = "STRONG"
                    elif abs_diff >= 5:
                        confidence = "MODERATE"
                    else:
                        confidence = "CLOSE"

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
                        'game_id': f"{date_str}_{game['away']}_{game['home']}",
                        'game_date': date_str,
                        'away_team': game['away'],
                        'home_team': game['home'],
                        'away_score': away_data['final_score'],
                        'home_score': home_data['final_score'],
                        'pick': pick,
                        'diff': abs_diff,
                        'confidence': confidence,
                        'factors': factors[:3],
                        'game_time': game.get('game_time'),
                    })
            except Exception as e:
                print(f"Error analyzing {game['away']} @ {game['home']}: {e}")
                continue

        # Sort by confidence (highest diff first)
        return sorted(results, key=lambda r: r['diff'], reverse=True)


def get_model_engine() -> ModelEngine:
    """Get a ModelEngine instance"""
    return ModelEngine()
