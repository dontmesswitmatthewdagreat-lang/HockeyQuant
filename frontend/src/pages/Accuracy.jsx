import { useState, useEffect } from 'react';
import { fetchAccuracyStats } from '../api';
import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import AccuracyChart from '../components/AccuracyChart';
import LoadingSpinner from '../components/LoadingSpinner';
import './Accuracy.css';

function Accuracy() {
  const [stats, setStats] = useState(null);
  const [recentPredictions, setRecentPredictions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    loadAccuracyData();
  }, []);

  async function loadAccuracyData() {
    try {
      const data = await fetchAccuracyStats();
      setStats(data.stats);
      setRecentPredictions(data.recent_predictions || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  if (loading) {
    return <LoadingSpinner message="Loading accuracy data..." />;
  }

  if (error) {
    return (
      <div className="accuracy-page">
        <div className="error-message">
          <p>Error loading accuracy data: {error}</p>
        </div>
      </div>
    );
  }

  // Extract multi-window stats
  const allTime = stats?.all_time || {};
  const currentSeason = stats?.current_season || {};
  const rolling30 = stats?.rolling_30 || {};

  return (
    <div className="accuracy-page">
      {/* Header */}
      <div className="accuracy-header">
        <h1>Official Model Accuracy</h1>
        <p className="accuracy-subtitle">
          Track the performance of HockeyQuant's prediction model
        </p>
      </div>

      {/* Summary Stats */}
      <div className="stats-summary">
        <div className="stat-card highlight">
          <span className="stat-label">All-Time</span>
          <span className="stat-value">
            {allTime.pct?.toFixed(1) || '0.0'}%
          </span>
          <span className="stat-detail">
            {allTime.correct || 0} / {allTime.total || 0} correct
          </span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Current Season</span>
          <span className="stat-value">
            {currentSeason.pct?.toFixed(1) || '0.0'}%
          </span>
          <span className="stat-detail">
            {currentSeason.correct || 0} / {currentSeason.total || 0} correct
          </span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Last 30 Games</span>
          <span className="stat-value">
            {rolling30.pct?.toFixed(1) || '0.0'}%
          </span>
          <span className="stat-detail">
            {rolling30.correct || 0} / {rolling30.total || 0} correct
          </span>
        </div>
      </div>

      {/* Confidence Breakdown */}
      <div className="confidence-section">
        <h2 className="section-title">Accuracy by Confidence Level</h2>
        <div className="confidence-cards">
          <div className="confidence-card strong">
            <div className="confidence-header">
              <span className="confidence-label">STRONG</span>
              <span className="confidence-badge">High Confidence</span>
            </div>
            <span className="confidence-value">
              {stats?.strong_pct?.toFixed(1) || '0.0'}%
            </span>
            <span className="confidence-detail">
              {stats?.strong_correct || 0} / {stats?.strong_total || 0} picks
            </span>
          </div>
          <div className="confidence-card moderate">
            <div className="confidence-header">
              <span className="confidence-label">MODERATE</span>
              <span className="confidence-badge">Medium Confidence</span>
            </div>
            <span className="confidence-value">
              {stats?.moderate_pct?.toFixed(1) || '0.0'}%
            </span>
            <span className="confidence-detail">
              {stats?.moderate_correct || 0} / {stats?.moderate_total || 0} picks
            </span>
          </div>
          <div className="confidence-card close">
            <div className="confidence-header">
              <span className="confidence-label">CLOSE</span>
              <span className="confidence-badge">Low Confidence</span>
            </div>
            <span className="confidence-value">
              {stats?.close_pct?.toFixed(1) || '0.0'}%
            </span>
            <span className="confidence-detail">
              {stats?.close_correct || 0} / {stats?.close_total || 0} picks
            </span>
          </div>
        </div>
      </div>

      {/* Accuracy Trend Chart */}
      <AccuracyChart />

      {/* Recent Predictions */}
      {recentPredictions.length > 0 && (
        <div className="recent-section">
          <h2 className="section-title">Recent Predictions</h2>
          <div className="recent-table-container">
            <table className="recent-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Matchup</th>
                  <th>Pick</th>
                  <th>Confidence</th>
                  <th>Result</th>
                </tr>
              </thead>
              <tbody>
                {recentPredictions.slice(0, 20).map((pred, idx) => (
                  <tr key={idx} className={pred.correct ? 'correct' : pred.correct === false ? 'incorrect' : ''}>
                    <td className="date-cell">{pred.game_date}</td>
                    <td className="matchup-cell">
                      <div className="matchup">
                        <img
                          src={getTeamLogo(pred.away_team)}
                          alt={pred.away_team}
                          className="team-logo-small"
                          onError={(e) => { e.target.style.display = 'none'; }}
                        />
                        <span className="team-abbrev">{pred.away_team}</span>
                        <span className="vs">@</span>
                        <img
                          src={getTeamLogo(pred.home_team)}
                          alt={pred.home_team}
                          className="team-logo-small"
                          onError={(e) => { e.target.style.display = 'none'; }}
                        />
                        <span className="team-abbrev">{pred.home_team}</span>
                      </div>
                    </td>
                    <td className="pick-cell">
                      <span className={`pick-badge ${pred.pick === pred.home_team ? 'home' : 'away'}`}>
                        {getTeamName(pred.pick)}
                      </span>
                    </td>
                    <td className="confidence-cell">
                      <span className={`confidence-tag ${pred.confidence?.toLowerCase()}`}>
                        {pred.confidence}
                      </span>
                    </td>
                    <td className="result-cell">
                      {pred.correct === true && (
                        <span className="result-badge correct">
                          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                            <polyline points="20 6 9 17 4 12"></polyline>
                          </svg>
                          Win
                        </span>
                      )}
                      {pred.correct === false && (
                        <span className="result-badge incorrect">
                          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                          </svg>
                          Loss
                        </span>
                      )}
                      {pred.correct === null && (
                        <span className="result-badge pending">Pending</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

export default Accuracy;
