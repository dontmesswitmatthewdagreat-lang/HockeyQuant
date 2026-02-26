import { useState, useEffect } from 'react';
import { fetchAccuracyStats } from '../api';
import { getTeamLogo, getTeamName, TEAM_NAMES } from '../utils/teamLogos';
import AccuracyChart from '../components/AccuracyChart';
import LoadingSpinner from '../components/LoadingSpinner';
import TeamLeaderboard from '../components/TeamLeaderboard';
import './Accuracy.css';

const ALL_TEAMS = Object.entries(TEAM_NAMES)
  .map(([abbrev, name]) => ({ abbrev, name }))
  .sort((a, b) => a.name.localeCompare(b.name));

function Accuracy() {
  const [stats, setStats] = useState(null);
  const [recentPredictions, setRecentPredictions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [chartPredType, setChartPredType] = useState('moneyline');
  const [selectedTeam, setSelectedTeam] = useState('');

  useEffect(() => {
    loadAccuracyData();
  }, [selectedTeam]);

  async function loadAccuracyData() {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchAccuracyStats({ team: selectedTeam || undefined });
      setStats(data.stats);
      setRecentPredictions(data.recent_predictions || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
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

      {/* Team Filter — always visible */}
      <div className="accuracy-filters">
        <div className="team-filter">
          {selectedTeam && (
            <img
              src={getTeamLogo(selectedTeam)}
              alt={selectedTeam}
              className="filter-team-logo"
              onError={(e) => { e.target.style.display = 'none'; }}
            />
          )}
          <select
            value={selectedTeam}
            onChange={(e) => setSelectedTeam(e.target.value)}
            className="team-select"
          >
            <option value="">All Teams</option>
            {ALL_TEAMS.map(({ abbrev, name }) => (
              <option key={abbrev} value={abbrev}>{name}</option>
            ))}
          </select>
          {selectedTeam && (
            <button className="clear-filter-btn" onClick={() => setSelectedTeam('')}>
              ✕ Clear
            </button>
          )}
        </div>
        {selectedTeam && (
          <p className="filter-context">
            Showing accuracy for games involving <strong>{getTeamName(selectedTeam)}</strong>
          </p>
        )}
      </div>

      {/* Inline loading / error states */}
      {loading && <LoadingSpinner message="Loading accuracy data..." />}
      {!loading && error && (
        <div className="error-message">
          <p>Error loading accuracy data: {error}</p>
        </div>
      )}

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

      {/* Puck Line Accuracy */}
      <div className="confidence-section">
        <h2 className="section-title">
          Puck Line Accuracy <span className="section-subtitle">official ±1.5 line</span>
        </h2>
        {(stats?.puck_line_total || 0) === 0 ? (
          <p className="no-data-note">No puck line results tracked yet. Results populate as games are recorded.</p>
        ) : (
          <div className="confidence-cards">
            <div className="confidence-card strong">
              <div className="confidence-header">
                <span className="confidence-label">STRONG</span>
                <span className="confidence-badge">High Confidence</span>
              </div>
              <span className="confidence-value">{stats?.puck_line_strong_pct?.toFixed(1) || '0.0'}%</span>
              <span className="confidence-detail">{stats?.puck_line_strong_correct || 0} / {stats?.puck_line_strong_total || 0} picks</span>
            </div>
            <div className="confidence-card moderate">
              <div className="confidence-header">
                <span className="confidence-label">MODERATE</span>
                <span className="confidence-badge">Medium Confidence</span>
              </div>
              <span className="confidence-value">{stats?.puck_line_moderate_pct?.toFixed(1) || '0.0'}%</span>
              <span className="confidence-detail">{stats?.puck_line_moderate_correct || 0} / {stats?.puck_line_moderate_total || 0} picks</span>
            </div>
            <div className="confidence-card close">
              <div className="confidence-header">
                <span className="confidence-label">CLOSE</span>
                <span className="confidence-badge">Low Confidence</span>
              </div>
              <span className="confidence-value">{stats?.puck_line_close_pct?.toFixed(1) || '0.0'}%</span>
              <span className="confidence-detail">{stats?.puck_line_close_correct || 0} / {stats?.puck_line_close_total || 0} picks</span>
            </div>
          </div>
        )}
        {(stats?.puck_line_total || 0) > 0 && (
          <p className="section-overall">
            Overall: <strong>{stats?.puck_line_pct?.toFixed(1)}%</strong> ({stats?.puck_line_correct_count} / {stats?.puck_line_total} picks)
          </p>
        )}
      </div>

      {/* Over/Under Accuracy */}
      <div className="confidence-section">
        <h2 className="section-title">Over/Under Accuracy</h2>
        {(stats?.ou_total || 0) === 0 ? (
          <p className="no-data-note">No O/U results tracked yet. Results populate as games are recorded.</p>
        ) : (
          <div className="confidence-cards">
            <div className="confidence-card strong">
              <div className="confidence-header">
                <span className="confidence-label">STRONG</span>
                <span className="confidence-badge">High Confidence</span>
              </div>
              <span className="confidence-value">{stats?.ou_strong_pct?.toFixed(1) || '0.0'}%</span>
              <span className="confidence-detail">{stats?.ou_strong_correct || 0} / {stats?.ou_strong_total || 0} picks</span>
            </div>
            <div className="confidence-card moderate">
              <div className="confidence-header">
                <span className="confidence-label">MODERATE</span>
                <span className="confidence-badge">Medium Confidence</span>
              </div>
              <span className="confidence-value">{stats?.ou_moderate_pct?.toFixed(1) || '0.0'}%</span>
              <span className="confidence-detail">{stats?.ou_moderate_correct || 0} / {stats?.ou_moderate_total || 0} picks</span>
            </div>
            <div className="confidence-card close">
              <div className="confidence-header">
                <span className="confidence-label">CLOSE</span>
                <span className="confidence-badge">Low Confidence</span>
              </div>
              <span className="confidence-value">{stats?.ou_close_pct?.toFixed(1) || '0.0'}%</span>
              <span className="confidence-detail">{stats?.ou_close_correct || 0} / {stats?.ou_close_total || 0} picks</span>
            </div>
          </div>
        )}
        {(stats?.ou_total || 0) > 0 && (
          <p className="section-overall">
            Overall: <strong>{stats?.ou_pct?.toFixed(1)}%</strong> ({stats?.ou_correct_count} / {stats?.ou_total} picks)
          </p>
        )}
      </div>

      {/* Accuracy Trend Chart */}
      <div className="chart-type-selector">
        <span className="chart-type-label">Chart:</span>
        <button
          className={`chart-type-btn ${chartPredType === 'moneyline' ? 'active' : ''}`}
          onClick={() => setChartPredType('moneyline')}
        >
          Moneyline
        </button>
        <button
          className={`chart-type-btn ${chartPredType === 'puck_line' ? 'active' : ''}`}
          onClick={() => setChartPredType('puck_line')}
        >
          Puck Line
        </button>
        <button
          className={`chart-type-btn ${chartPredType === 'ou' ? 'active' : ''}`}
          onClick={() => setChartPredType('ou')}
        >
          Over/Under
        </button>
      </div>
      <AccuracyChart predType={chartPredType} team={selectedTeam} />

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
                  <th>Conf</th>
                  <th>ML</th>
                  <th>Puck Line</th>
                  <th>O/U</th>
                </tr>
              </thead>
              <tbody>
                {recentPredictions.slice(0, 20).map((pred, idx) => {
                  const plSide = pred.puck_line_pick;
                  const plLine = pred.puck_line_line;
                  const plLabel = plSide && plLine != null
                    ? `${plSide === 'home' ? pred.home_team : pred.away_team} ${plLine > 0 ? '+' : ''}${plLine}`
                    : null;
                  const ouLabel = pred.ou_pick && pred.ou_line != null
                    ? `${pred.ou_pick.toUpperCase()} ${pred.ou_line}`
                    : null;
                  return (
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
                        </span>
                      )}
                      {pred.correct === false && (
                        <span className="result-badge incorrect">
                          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                          </svg>
                        </span>
                      )}
                      {pred.correct == null && <span className="result-badge pending">—</span>}
                    </td>
                    <td className="result-cell">
                      {plLabel ? (
                        pred.puck_line_correct === true ? (
                          <span className="result-badge correct" title={plLabel}>
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                              <polyline points="20 6 9 17 4 12"></polyline>
                            </svg>
                            <span className="badge-label">{plLabel}</span>
                          </span>
                        ) : pred.puck_line_correct === false ? (
                          <span className="result-badge incorrect" title={plLabel}>
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                              <line x1="18" y1="6" x2="6" y2="18"></line>
                              <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                            <span className="badge-label">{plLabel}</span>
                          </span>
                        ) : (
                          <span className="result-badge pending">{plLabel}</span>
                        )
                      ) : <span className="result-badge pending">—</span>}
                    </td>
                    <td className="result-cell">
                      {ouLabel ? (
                        pred.ou_correct === true ? (
                          <span className="result-badge correct" title={ouLabel}>
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                              <polyline points="20 6 9 17 4 12"></polyline>
                            </svg>
                            <span className="badge-label">{ouLabel}</span>
                          </span>
                        ) : pred.ou_correct === false ? (
                          <span className="result-badge incorrect" title={ouLabel}>
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                              <line x1="18" y1="6" x2="6" y2="18"></line>
                              <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                            <span className="badge-label">{ouLabel}</span>
                          </span>
                        ) : (
                          <span className="result-badge pending">{ouLabel}</span>
                        )
                      ) : <span className="result-badge pending">—</span>}
                    </td>
                  </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Team Leaderboard */}
      <TeamLeaderboard selectedTeam={selectedTeam} onSelectTeam={setSelectedTeam} />
    </div>
  );
}

export default Accuracy;
