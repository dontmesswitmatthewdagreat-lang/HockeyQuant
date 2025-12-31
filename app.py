from flask import Flask, render_template, jsonify
import requests
from datetime import datetime

app = Flask(__name__)

class NHLBettingAnalyzer:
    """
    A program to analyze NHL team statistics and generate betting recommendations.
    """
    
    def __init__(self):
        self.base_url = "https://api-web.nhle.com/v1"
        
    def get_todays_games(self):
        """Fetch all NHL games scheduled for today."""
        today = datetime.now().strftime("%Y-%m-%d")
        url = f"{self.base_url}/schedule/{today}"
        
        try:
            response = requests.get(url)
            response.raise_for_status()
            data = response.json()
            
            games = []
            if 'gameWeek' in data:
                for day in data['gameWeek']:
                    if day.get('date') == today and 'games' in day:
                        games = day['games']
                        break
            
            return games
            
        except requests.exceptions.RequestException as e:
            print(f"Error fetching schedule: {e}")
            return []
    
    def get_team_stats(self, team_abbrev):
        """Fetch season statistics for a specific team using the standings endpoint."""
        url = f"{self.base_url}/standings/now"
        
        try:
            response = requests.get(url)
            response.raise_for_status()
            data = response.json()
            
            if 'standings' in data:
                for team in data['standings']:
                    if team.get('teamAbbrev', {}).get('default') == team_abbrev:
                        return team
            
            return None
            
        except requests.exceptions.RequestException as e:
            print(f"Error fetching stats for {team_abbrev}: {e}")
            return None
    
    def calculate_team_score(self, stats):
        """Create a simple scoring system based on team statistics."""
        if not stats:
            return 0
        
        wins = stats.get('wins', 0)
        losses = stats.get('losses', 0)
        ot_losses = stats.get('otLosses', 0)
        goals_for = stats.get('goalFor', 0)
        goals_against = stats.get('goalAgainst', 0)
        points = stats.get('points', 0)
        
        total_games = wins + losses + ot_losses
        if total_games == 0:
            return 0
        
        win_pct = (wins + (ot_losses * 0.5)) / total_games
        goal_diff = (goals_for - goals_against) / total_games
        max_points = total_games * 2
        points_pct = points / max_points if max_points > 0 else 0
        
        score = (points_pct * 50) + (win_pct * 30) + (goal_diff * 20)
        
        return score
    
    def analyze_matchup(self, home_team, away_team):
        """Compare two teams and determine which has better statistics."""
        home_name = home_team.get('name', {}).get('default') or home_team.get('commonName', {}).get('default') or home_team.get('abbrev', 'Unknown')
        away_name = away_team.get('name', {}).get('default') or away_team.get('commonName', {}).get('default') or away_team.get('abbrev', 'Unknown')
        
        home_stats = self.get_team_stats(home_team['abbrev'])
        away_stats = self.get_team_stats(away_team['abbrev'])
        
        if not home_stats or not away_stats:
            return None
        
        home_score = self.calculate_team_score(home_stats)
        away_score = self.calculate_team_score(away_stats)
        
        if home_score > away_score:
            recommended_team = home_name
            if home_score > 0:
                confidence = ((home_score - away_score) / home_score) * 100
            else:
                confidence = 0
        else:
            recommended_team = away_name
            if away_score > 0:
                confidence = ((away_score - home_score) / away_score) * 100
            else:
                confidence = 0
        
        return {
            'home_team': home_name,
            'away_team': away_name,
            'home_score': round(home_score, 2),
            'away_score': round(away_score, 2),
            'recommendation': recommended_team,
            'confidence': round(confidence, 1),
            'home_record': f"{home_stats.get('wins', 0)}-{home_stats.get('losses', 0)}-{home_stats.get('otLosses', 0)}",
            'away_record': f"{away_stats.get('wins', 0)}-{away_stats.get('losses', 0)}-{away_stats.get('otLosses', 0)}"
        }
    
    def generate_betting_recommendations(self):
        """Main function: Gets today's games and generates betting recommendations."""
        games = self.get_todays_games()
        
        if not games:
            return {'error': 'No games scheduled for today'}
        
        recommendations = []
        
        for game in games:
            home_team = game.get('homeTeam', {})
            away_team = game.get('awayTeam', {})
            
            analysis = self.analyze_matchup(home_team, away_team)
            if analysis:
                recommendations.append(analysis)
        
        return {
            'date': datetime.now().strftime("%B %d, %Y"),
            'game_count': len(recommendations),
            'games': recommendations
        }


# Flask routes
@app.route('/')
def index():
    """Serve the main page"""
    return render_template('index.html')

@app.route('/analyze')
def analyze():
    """API endpoint to analyze games"""
    analyzer = NHLBettingAnalyzer()
    results = analyzer.generate_betting_recommendations()
    return jsonify(results)

if __name__ == '__main__':
    print("=" * 60)
    print("NHL BETTING ANALYZER - WEB VERSION")
    print("=" * 60)
    print("\nStarting server...")
    print("Open your browser and go to: http://127.0.0.1:5000")
    print("\nPress CTRL+C to stop the server")
    print("=" * 60)
    app.run(host="127.0.0.1", port=5000, debug=True)