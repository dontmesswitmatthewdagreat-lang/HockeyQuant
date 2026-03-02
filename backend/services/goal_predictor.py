"""
HockeyQuant Goal Predictor
Dixon-Coles/Poisson-based expected goals and probability calculations.

This module predicts ACTUAL expected goals per team (not quality scores),
then uses Poisson distributions to compute spread and total probabilities.
"""

from math import exp, factorial
from typing import Dict, List, Optional, Tuple


def poisson_pmf(k: int, lam: float) -> float:
    """Poisson probability mass function: P(X = k) given mean lam"""
    if k < 0 or lam <= 0:
        return 0.0
    return (lam ** k) * exp(-lam) / factorial(k)


def _build_score_matrix(pred_a: float, pred_b: float, max_goals: int = 10) -> List[List[float]]:
    """
    Build joint probability matrix for (goals_A, goals_B).
    matrix[a][b] = P(A scores a AND B scores b)
    Assumes independence (standard Poisson model).
    """
    matrix = []
    for a in range(max_goals + 1):
        row = []
        for b in range(max_goals + 1):
            row.append(poisson_pmf(a, pred_a) * poisson_pmf(b, pred_b))
        matrix.append(row)
    return matrix


def calc_over_under_prob(pred_away: float, pred_home: float, line: float) -> Dict[str, float]:
    """
    Calculate P(Over) and P(Under) for a given total line.

    Returns: {"over": float, "under": float, "push": float}
    """
    matrix = _build_score_matrix(pred_away, pred_home)
    p_over = 0.0
    p_under = 0.0
    p_push = 0.0

    for a in range(len(matrix)):
        for b in range(len(matrix[0])):
            total = a + b
            prob = matrix[a][b]
            if total > line:
                p_over += prob
            elif total < line:
                p_under += prob
            else:
                p_push += prob

    return {"over": p_over, "under": p_under, "push": p_push}


def calc_spread_prob(pred_away: float, pred_home: float, line: float) -> Dict[str, float]:
    """
    Calculate puck line cover probability.

    Convention: line is from HOME perspective.
    If home is favored, line is negative (e.g., -1.5).
    Home covers when (home_goals - away_goals + line) > 0.

    Returns: {"home_cover": float, "away_cover": float, "push": float}
    """
    matrix = _build_score_matrix(pred_away, pred_home)
    p_home_cover = 0.0
    p_away_cover = 0.0
    p_push = 0.0

    for a in range(len(matrix)):
        for b in range(len(matrix[0])):
            # margin from home perspective: home_goals - away_goals
            margin = b - a
            prob = matrix[a][b]

            # Home covers if margin + line > 0
            # e.g., home -1.5: covers if margin > 1.5 (win by 2+)
            # e.g., home +1.5: covers if margin > -1.5 (lose by 0 or 1, or win)
            result = margin + line
            if result > 0:
                p_home_cover += prob
            elif result < 0:
                p_away_cover += prob
            else:
                p_push += prob

    return {"home_cover": p_home_cover, "away_cover": p_away_cover, "push": p_push}


def calc_moneyline_prob(pred_away: float, pred_home: float) -> Dict[str, float]:
    """
    Regulation win probability from Poisson score matrix.

    Returns: {"home_win": float, "away_win": float, "push": float}
    All values are fractions (0.0–1.0), not percentages.
    """
    matrix = _build_score_matrix(pred_away, pred_home)
    p_home_win = 0.0
    p_away_win = 0.0
    p_push = 0.0
    for a in range(len(matrix)):
        for b in range(len(matrix[0])):
            prob = matrix[a][b]
            if b > a:    # home scores more in regulation
                p_home_win += prob
            elif a > b:  # away scores more
                p_away_win += prob
            else:
                p_push += prob
    return {"home_win": p_home_win, "away_win": p_away_win, "push": p_push}


def find_optimal_total(pred_away: float, pred_home: float) -> Tuple[float, float, str]:
    """
    Find the optimal over/under line. Prefers half-lines (no push).
    Tests nearby lines and picks the one with the strongest edge.

    Returns: (optimal_line, probability, "OVER" or "UNDER")
    """
    predicted_total = pred_away + pred_home
    base_line = round(predicted_total * 2) / 2

    # Use nearest half-line (avoids push scenarios with whole numbers)
    # If base_line is whole (e.g., 6.0), shift to 5.5 or 6.5 based on predicted total
    optimal_line = base_line
    if base_line == int(base_line):  # whole number
        if predicted_total >= base_line:
            optimal_line = base_line - 0.5  # model expects over, so pick lower line
        else:
            optimal_line = base_line + 0.5  # model expects under, so pick higher line

    probs = calc_over_under_prob(pred_away, pred_home, optimal_line)

    if probs["over"] >= probs["under"]:
        return (optimal_line, probs["over"], "OVER")
    else:
        return (optimal_line, probs["under"], "UNDER")


def find_optimal_spread(pred_away: float, pred_home: float) -> Tuple[float, float, str]:
    """
    Find the optimal puck line (nearest 0.5 to predicted margin).
    Returns spread from home perspective.

    Returns: (optimal_line, cover_probability, "home" or "away")
    """
    predicted_margin = pred_home - pred_away  # positive = home favored

    # Always use half-lines (0.5, 1.5, 2.5, ...) — no push scenarios
    abs_margin = abs(predicted_margin)
    rounded = max(1.5, int(abs_margin) + 0.5)  # nearest half-line, minimum 1.5

    if predicted_margin >= 0:
        # Home favored: negative line (e.g., -1.5)
        optimal_line = -rounded
    else:
        # Away favored: positive line (e.g., +1.5)
        optimal_line = rounded

    probs = calc_spread_prob(pred_away, pred_home, optimal_line)

    # Pick whichever side has higher cover probability, not just the predicted winner
    if probs["home_cover"] >= probs["away_cover"]:
        return (optimal_line, probs["home_cover"], "home")
    else:
        return (optimal_line, probs["away_cover"], "away")


class GoalPredictor:
    """
    Predicts actual expected goals per team using a Dixon-Coles/Poisson model.

    This is separate from the NHLAnalyzer quality scoring system.
    The quality score determines WHO wins; this predicts BY HOW MUCH.
    """

    HOME_ICE_BOOST = 1.03  # 3% home advantage in goal scoring

    def __init__(self, data_loader=None, analyzer=None):
        self.data_loader = data_loader
        self.analyzer = analyzer

    def _get_league_avg_goals_per_game(self) -> float:
        """
        Calculate league average goals per team per game from standings.
        Typical value: ~3.0-3.2
        """
        if self.analyzer is None or self.analyzer._standings_cache is None:
            return 3.1  # reasonable default

        standings = self.analyzer._standings_cache
        total_goals = 0
        total_games = 0

        for team in standings:
            gf = team.get("goalFor", 0)
            gp = team.get("gamesPlayed", 0)
            total_goals += gf
            total_games += gp

        if total_games == 0:
            return 3.1

        return total_goals / total_games

    def _get_team_strength(self, team_abbrev: str, league_avg: float) -> Tuple[float, float]:
        """
        Calculate team offensive strength and defensive weakness.
        Blends actual goals (35%) with MoneyPuck xG (65%).

        Returns: (off_strength, def_weakness) as ratios vs league average.
        off_strength > 1.0 = better than avg offense
        def_weakness > 1.0 = worse than avg defense (allows more goals)
        """
        if self.data_loader is None:
            return (1.0, 1.0)

        team_data = self.data_loader.team_data
        if team_data is None:
            return (1.0, 1.0)

        row = team_data[team_data["team"] == team_abbrev]
        if row.empty:
            return (1.0, 1.0)

        r = row.iloc[0]
        games = float(r["games_played"])
        if games == 0:
            return (1.0, 1.0)

        # MoneyPuck xGoals (cumulative totals for the season)
        xgf_pg = float(r["xGoalsFor"]) / games
        xga_pg = float(r["xGoalsAgainst"]) / games

        # Actual goals from MoneyPuck
        actual_gf_pg = float(r["goalsFor"]) / games
        actual_ga_pg = float(r["goalsAgainst"]) / games

        # Blend: 65% xG + 35% actual (xG is more predictive)
        blended_off = actual_gf_pg * 0.35 + xgf_pg * 0.65
        blended_def = actual_ga_pg * 0.35 + xga_pg * 0.65

        # Relative to league average
        off_strength = blended_off / league_avg if league_avg > 0 else 1.0
        def_weakness = blended_def / league_avg if league_avg > 0 else 1.0

        return (off_strength, def_weakness)

    def _goalie_adjustment(self, team_analysis: Dict) -> float:
        """
        Calculate goalie's effect on opponent's goals.
        Uses GSAX per game — a high-GSAX goalie reduces opponent expected goals.

        Returns a factor to multiply the OPPONENT's expected goals by.
        Factor < 1.0 means goalie is good (suppresses opponent goals).
        """
        gsax = team_analysis.get("goalie_gsax", 0.0)

        # Look up games played for per-game rate
        goalie_name = team_analysis.get("goalie", "")
        games_played = 30  # default estimate (mid-season starter)

        if self.data_loader is not None and goalie_name:
            goalie_data = self.data_loader.goalie_data
            if goalie_data is not None:
                match = goalie_data[goalie_data["name"] == goalie_name]
                if not match.empty:
                    games_played = max(1, int(match.iloc[0]["games_played"]))

        gsax_per_game = gsax / games_played

        # Positive GSAX = goalie saves more than expected = reduce opponent goals
        # Scale: 0.3 weight (GSAX of +0.5/game -> 15% reduction)
        goalie_factor = 1.0 - (gsax_per_game * 0.3)
        goalie_factor = max(0.85, min(1.15, goalie_factor))

        return goalie_factor

    def predict_goals(
        self,
        away_abbrev: str,
        home_abbrev: str,
        away_analysis: Dict,
        home_analysis: Dict,
    ) -> Dict:
        """
        Predict expected goals for each team in a game.

        Args:
            away_abbrev: Away team abbreviation
            home_abbrev: Home team abbreviation
            away_analysis: Result dict from analyzer.analyze_team()
            home_analysis: Result dict from analyzer.analyze_team()

        Returns:
            {
                "away_expected_goals": float,
                "home_expected_goals": float,
                "predicted_total": float,
                "predicted_margin": float,  # home - away (positive = home favored)
            }
        """
        league_avg = self._get_league_avg_goals_per_game()

        # Step 1: Team offensive/defensive strengths
        away_off, away_def = self._get_team_strength(away_abbrev, league_avg)
        home_off, home_def = self._get_team_strength(home_abbrev, league_avg)

        # Step 2: Base predicted goals (Dixon-Coles framework)
        pred_away = away_off * home_def * league_avg
        pred_home = home_off * away_def * league_avg

        # Step 3: Goalie adjustment
        away_goalie_factor = self._goalie_adjustment(away_analysis)
        home_goalie_factor = self._goalie_adjustment(home_analysis)

        pred_away *= home_goalie_factor  # home goalie defends against away
        pred_home *= away_goalie_factor  # away goalie defends against home

        # Step 4: Apply existing multipliers
        pred_away *= away_analysis.get("fatigue_mult", 1.0)
        pred_away *= away_analysis.get("injury_mult", 1.0)
        away_st = away_analysis.get("st_mult", 1.0)
        pred_away *= (1.0 + (away_st - 1.0) * 0.5)  # dampened ST effect

        pred_home *= home_analysis.get("fatigue_mult", 1.0)
        pred_home *= home_analysis.get("injury_mult", 1.0)
        home_st = home_analysis.get("st_mult", 1.0)
        pred_home *= (1.0 + (home_st - 1.0) * 0.5)

        # Step 5: Home ice advantage
        pred_home *= self.HOME_ICE_BOOST

        # Step 6: Sanity clamp
        pred_away = max(1.5, min(5.5, pred_away))
        pred_home = max(1.5, min(5.5, pred_home))

        return {
            "away_expected_goals": round(pred_away, 2),
            "home_expected_goals": round(pred_home, 2),
            "predicted_total": round(pred_away + pred_home, 2),
            "predicted_margin": round(pred_home - pred_away, 2),
        }
