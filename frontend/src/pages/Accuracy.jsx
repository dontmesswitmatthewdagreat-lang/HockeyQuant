import { useState, useEffect } from 'react';
import { fetchAccuracyStats, fetchTeams } from '../api';
import LoadingSpinner from '../components/LoadingSpinner';
import './Accuracy.css';

function Accuracy() {
  const [stats, setStats] = useState(null);
  const [predictions, setPredictions] = useState([]);
  const [teams, setTeams] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Filters
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [selectedTeam, setSelectedTeam] = useState('');
  const [selectedConfidence, setSelectedConfidence] = useState('');

  useEffect(() => {
    loadTeams();
    loadStats();
  }, []);

  async function loadTeams() {
    try {
      const data = await fetchTeams();
      setTeams(data);
    } catch (err) {
      console.error('Failed to load teams:', err);
    }
  }

  async function loadStats() {
    setLoading(true);
    setError(null);
    try {
      const params = {};
      if (startDate) params.startDate = startDate;
      if (endDate) params.endDate = endDate;
      if (selectedTeam) params.team = selectedTeam;
      if (selectedConfidence) params.confidence = selectedConfidence;

      const data = await fetchAccuracyStats(params);
      setStats(data.stats);
      setPredictions(data.recent_predictions);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  function handleApplyFilters() {
    loadStats();
  }

  function handleClearFilters() {
    setStartDate('');
    setEndDate('');
    setSelectedTeam('');
    setSelectedConfidence('');
    // Reload with no filters
    setTimeout(() => loadStats(), 0);
  }

  if (loading && !stats) {
    return <LoadingSpinner message="Loading accuracy data..." />;
  }

  return (
    <div className="accuracy-page">
      <h1 className="page-title">Model Accuracy</h1>
      <p className="page-subtitle">Track HockeyQuant's prediction performance</p>

      {error && (
        <div className="error-message">
          <p>Error: {error}</p>
        </div>
      )}

      {/* Filters */}
      <div className="filters-section">
        <div className="filter-row">
          <div className="filter-group">
            <label>Start Date</label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
            />
          </div>
          <div className="filter-group">
            <label>End Date</label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
            />
          </div>
          <div className="filter-group">
            <label>Team Picked</label>
            <select
              value={selectedTeam}
              onChange={(e) => setSelectedTeam(e.target.value)}
            >
              <option value="">All Teams</option>
              {teams.map((team) => (
                <option key={team.abbrev} value={team.abbrev}>
                  {team.abbrev} - {team.name}
                </option>
              ))}
            </select>
          </div>
          <div className="filter-group">
            <label>Confidence</label>
            <select
              value={selectedConfidence}
              onChange={(e) => setSelectedConfidence(e.target.value)}
            >
              <option value="">All</option>
              <option value="STRONG">Strong</option>
              <option value="MODERATE">Moderate</option>
              <option value="CLOSE">Close</option>
            </select>
          </div>
          <div className="filter-buttons">
            <button className="apply-btn" onClick={handleApplyFilters}>
              Apply
            </button>
            <button className="clear-btn" onClick={handleClearFilters}>
              Clear
            </button>
          </div>
        </div>
      </div>

      {stats && (
        <>
          {/* Main Stats */}
          <div className="stats-overview">
            <div className="main-stat">
              <div className="stat-number">{stats.accuracy_pct}%</div>
              <div className="stat-label">Overall Accuracy</div>
              <div className="stat-detail">{stats.correct_picks} / {stats.total_games} games</div>
            </div>
          </div>

          {/* Confidence Breakdown */}
          <div className="confidence-breakdown">
            <h2 className="section-title">Accuracy by Confidence Level</h2>
            <div className="confidence-cards">
              <div className="confidence-card strong">
                <div className="confidence-header">STRONG</div>
                <div className="confidence-pct">{stats.strong_pct}%</div>
                <div className="confidence-detail">
                  {stats.strong_correct} / {stats.strong_total} picks
                </div>
              </div>
              <div className="confidence-card moderate">
                <div className="confidence-header">MODERATE</div>
                <div className="confidence-pct">{stats.moderate_pct}%</div>
                <div className="confidence-detail">
                  {stats.moderate_correct} / {stats.moderate_total} picks
                </div>
              </div>
              <div className="confidence-card close">
                <div className="confidence-header">CLOSE</div>
                <div className="confidence-pct">{stats.close_pct}%</div>
                <div className="confidence-detail">
                  {stats.close_correct} / {stats.close_total} picks
                </div>
              </div>
            </div>
          </div>

          {/* Recent Predictions Table */}
          <div className="predictions-section">
            <h2 className="section-title">Recent Predictions</h2>
            {predictions.length === 0 ? (
              <p className="no-data">No predictions recorded yet. Predictions are stored automatically before each game day.</p>
            ) : (
              <div className="predictions-table-wrapper">
                <table className="predictions-table">
                  <thead>
                    <tr>
                      <th>Date</th>
                      <th>Matchup</th>
                      <th>Pick</th>
                      <th>Confidence</th>
                      <th>Result</th>
                      <th>Correct</th>
                    </tr>
                  </thead>
                  <tbody>
                    {predictions.map((pred, i) => (
                      <tr key={i} className={pred.correct === true ? 'correct' : pred.correct === false ? 'incorrect' : ''}>
                        <td>{pred.game_date}</td>
                        <td>{pred.away_team} @ {pred.home_team}</td>
                        <td className="pick-cell">{pred.pick}</td>
                        <td>
                          <span className={`confidence-badge ${pred.confidence.toLowerCase()}`}>
                            {pred.confidence}
                          </span>
                        </td>
                        <td>
                          {pred.away_final !== null ? (
                            `${pred.away_final} - ${pred.home_final}`
                          ) : (
                            <span className="pending">Pending</span>
                          )}
                        </td>
                        <td>
                          {pred.correct === true && <span className="result-icon correct-icon">✓</span>}
                          {pred.correct === false && <span className="result-icon incorrect-icon">✗</span>}
                          {pred.correct === null && <span className="result-icon pending-icon">-</span>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {!stats && !loading && (
        <div className="no-data-message">
          <p>No accuracy data available yet.</p>
          <p>Predictions will be stored automatically before game days.</p>
        </div>
      )}
    </div>
  );
}

export default Accuracy;
