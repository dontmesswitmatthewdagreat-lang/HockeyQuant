import { useState, useEffect, useRef, Fragment } from 'react';
import { fetchAccuracyStats, fetchParlayStats } from '../api';
import { getTeamLogo, getTeamName, TEAM_NAMES } from '../utils/teamLogos';
import AccuracyChart from '../components/AccuracyChart';
import LoadingSpinner from '../components/LoadingSpinner';
import TeamLeaderboard from '../components/TeamLeaderboard';
import './Accuracy.css';

const ALL_TEAMS = Object.entries(TEAM_NAMES)
  .map(([abbrev, name]) => ({ abbrev, name }))
  .sort((a, b) => a.name.localeCompare(b.name));

function getYesterday() {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  return d.toISOString().split('T')[0];
}

function PctBadge({ correct, total }) {
  if (total === 0) return null;
  const pct = Math.round((correct / total) * 100);
  const cls = pct >= 60 ? 'yday-pct-good' : pct >= 50 ? 'yday-pct-warn' : 'yday-pct-bad';
  return <span className={`yday-pct ${cls}`}>{pct}%</span>;
}

function YesterdayCard({ recentPredictions }) {
  const yesterday = getYesterday();
  const games = recentPredictions.filter(p => p.game_date === yesterday);
  const mlGraded = games.filter(p => p.correct !== null);
  const plGraded = games.filter(p => p.puck_line_correct !== null);
  const ouGraded = games.filter(p => p.ou_correct !== null);
  const mlCorrect = mlGraded.filter(p => p.correct === true).length;
  const plCorrect = plGraded.filter(p => p.puck_line_correct === true).length;
  const ouCorrect = ouGraded.filter(p => p.ou_correct === true).length;
  const d = new Date(yesterday + 'T12:00:00');
  const dateLabel = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  return (
    <div className="yesterday-card">
      <div className="yesterday-header">Yesterday · {dateLabel}</div>
      {games.length === 0 ? (
        <div className="yday-empty">No results yet</div>
      ) : (
        <div className="yesterday-stats">
          <div className="yesterday-stat">
            <span className="yday-label">ML</span>
            <span className="yday-record">{mlCorrect}/{mlGraded.length}</span>
            <PctBadge correct={mlCorrect} total={mlGraded.length} />
          </div>
          {plGraded.length > 0 && (
            <div className="yesterday-stat">
              <span className="yday-label">PL</span>
              <span className="yday-record">{plCorrect}/{plGraded.length}</span>
              <PctBadge correct={plCorrect} total={plGraded.length} />
            </div>
          )}
          {ouGraded.length > 0 && (
            <div className="yesterday-stat">
              <span className="yday-label">O/U</span>
              <span className="yday-record">{ouCorrect}/{ouGraded.length}</span>
              <PctBadge correct={ouCorrect} total={ouGraded.length} />
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function Accuracy() {
  const [stats, setStats] = useState(null);
  const [recentPredictions, setRecentPredictions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [chartPredType, setChartPredType] = useState('moneyline');
  const [selectedTeam, setSelectedTeam] = useState('');
  const [showPlInfo, setShowPlInfo] = useState(false);
  const [showOuInfo, setShowOuInfo] = useState(false);
  const [parlayStats, setParlayStats] = useState(null);
  const [expandedParlayIdx, setExpandedParlayIdx] = useState(null);
  const chartRef = useRef(null);

  function handleLeaderboardSelect(team) {
    setSelectedTeam(team);
    if (team) {
      setTimeout(() => {
        chartRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 50);
    }
  }

  useEffect(() => {
    loadAccuracyData();
  }, [selectedTeam]);

  useEffect(() => {
    fetchParlayStats()
      .then(data => setParlayStats(data))
      .catch(() => {});
  }, []);

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
  const plAllTime = stats?.pl_all_time || {};
  const plCurrentSeason = stats?.pl_current_season || {};
  const plRolling30 = stats?.pl_rolling_30 || {};
  const ouAllTime = stats?.ou_all_time || {};
  const ouCurrentSeason = stats?.ou_current_season || {};
  const ouRolling30 = stats?.ou_rolling_30 || {};

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
      <p className="stat-section-label">Moneyline Predictions</p>
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
        <div className="stat-card highlight-blue">
          <span className="stat-label">Current Season</span>
          <span className="stat-value">
            {currentSeason.pct?.toFixed(1) || '0.0'}%
          </span>
          <span className="stat-detail">
            {currentSeason.correct || 0} / {currentSeason.total || 0} correct
          </span>
        </div>
        <div className="stat-card highlight-grey">
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
        <div className="section-title-row">
          <h2 className="section-title">
            Puck Line Accuracy <span className="section-subtitle">official ±1.5 line</span>
          </h2>
          <button className="info-btn" onClick={() => setShowPlInfo(v => !v)} title="How is confidence calculated?">i</button>
        </div>
        {showPlInfo && (
          <div className="confidence-info-panel">
            The <strong>STRONG / MODERATE / CLOSE</strong> labels are inherited from the moneyline prediction for each game — they reflect the quality score gap between the two teams, not the puck line probability itself. <strong>STRONG</strong> = ≥10 pt gap, <strong>MODERATE</strong> = ≥5 pt gap, <strong>CLOSE</strong> = &lt;5 pt gap. The puck line pick (which side covers ±1.5) is determined separately by the Poisson model.
          </div>
        )}
        {(stats?.puck_line_total || 0) === 0 ? (
          <p className="no-data-note">No puck line results tracked yet. Results populate as games are recorded.</p>
        ) : (
          <>
            <div className="stats-summary">
              <div className="stat-card highlight">
                <span className="stat-label">All-Time</span>
                <span className="stat-value">{plAllTime.pct?.toFixed(1) || '0.0'}%</span>
                <span className="stat-detail">{plAllTime.correct || 0} / {plAllTime.total || 0} correct</span>
              </div>
              <div className="stat-card highlight-blue">
                <span className="stat-label">Current Season</span>
                <span className="stat-value">{plCurrentSeason.pct?.toFixed(1) || '0.0'}%</span>
                <span className="stat-detail">{plCurrentSeason.correct || 0} / {plCurrentSeason.total || 0} correct</span>
              </div>
              <div className="stat-card highlight-grey">
                <span className="stat-label">Last 30 Games</span>
                <span className="stat-value">{plRolling30.pct?.toFixed(1) || '0.0'}%</span>
                <span className="stat-detail">{plRolling30.correct || 0} / {plRolling30.total || 0} correct</span>
              </div>
            </div>
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
          </>
        )}
        {(stats?.puck_line_total || 0) > 0 && (
          <p className="section-overall">
            Overall: <strong>{stats?.puck_line_pct?.toFixed(1)}%</strong> ({stats?.puck_line_correct_count} / {stats?.puck_line_total} picks)
          </p>
        )}
      </div>

      {/* Over/Under Accuracy */}
      <div className="confidence-section">
        <div className="section-title-row">
          <h2 className="section-title">Over/Under Accuracy</h2>
          <button className="info-btn" onClick={() => setShowOuInfo(v => !v)} title="How is confidence calculated?">i</button>
        </div>
        {showOuInfo && (
          <div className="confidence-info-panel">
            The <strong>STRONG / MODERATE / CLOSE</strong> labels are inherited from the moneyline prediction for each game — they reflect the quality score gap between the two teams, not the O/U probability itself. <strong>STRONG</strong> = ≥10 pt gap, <strong>MODERATE</strong> = ≥5 pt gap, <strong>CLOSE</strong> = &lt;5 pt gap. The over/under pick is determined separately by the Poisson model's total goal probabilities.
          </div>
        )}
        {(stats?.ou_total || 0) === 0 ? (
          <p className="no-data-note">No O/U results tracked yet. Results populate as games are recorded.</p>
        ) : (
          <>
            <div className="stats-summary">
              <div className="stat-card highlight">
                <span className="stat-label">All-Time</span>
                <span className="stat-value">{ouAllTime.pct?.toFixed(1) || '0.0'}%</span>
                <span className="stat-detail">{ouAllTime.correct || 0} / {ouAllTime.total || 0} correct</span>
              </div>
              <div className="stat-card highlight-blue">
                <span className="stat-label">Current Season</span>
                <span className="stat-value">{ouCurrentSeason.pct?.toFixed(1) || '0.0'}%</span>
                <span className="stat-detail">{ouCurrentSeason.correct || 0} / {ouCurrentSeason.total || 0} correct</span>
              </div>
              <div className="stat-card highlight-grey">
                <span className="stat-label">Last 30 Games</span>
                <span className="stat-value">{ouRolling30.pct?.toFixed(1) || '0.0'}%</span>
                <span className="stat-detail">{ouRolling30.correct || 0} / {ouRolling30.total || 0} correct</span>
              </div>
            </div>
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
          </>
        )}
        {(stats?.ou_total || 0) > 0 && (
          <p className="section-overall">
            Overall: <strong>{stats?.ou_pct?.toFixed(1)}%</strong> ({stats?.ou_correct_count} / {stats?.ou_total} picks)
          </p>
        )}
      </div>

      {/* Accuracy Trend Chart */}
      <div ref={chartRef}>
      <div className="chart-row">
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
        <YesterdayCard recentPredictions={recentPredictions} />
      </div>
      <AccuracyChart predType={chartPredType} team={selectedTeam} />
      </div>

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
      <TeamLeaderboard selectedTeam={selectedTeam} onSelectTeam={handleLeaderboardSelect} />

      {/* Parlay Accuracy */}
      <div className="confidence-section parlay-section">
        <h2 className="section-title">Daily Parlay Accuracy</h2>
        <p className="section-desc">Optimal parlays generated by the LP optimizer, graded nightly</p>

        {parlayStats && (
          <>
            {parlayStats.graded_parlays === 0 ? (
              <p className="no-data-note">No graded parlays yet — check back after the first game day.</p>
            ) : (
              <>
                <div className="stats-summary parlay-summary-grid">
                  <div className="stat-card highlight">
                    <span className="stat-label">Hit Rate</span>
                    <span className="stat-value">{parlayStats.hit_pct?.toFixed(1) || '0.0'}%</span>
                    <span className="stat-detail">{parlayStats.hit_count} / {parlayStats.graded_parlays} parlays</span>
                  </div>
                  <div className="stat-card highlight-blue">
                    <span className="stat-label">Avg Legs</span>
                    <span className="stat-value">{parlayStats.avg_legs || 0}</span>
                    <span className="stat-detail">per parlay</span>
                  </div>
                  <div className="stat-card highlight-grey">
                    <span className="stat-label">Avg Est. Prob</span>
                    <span className="stat-value">{parlayStats.avg_combined_prob || 0}%</span>
                    <span className="stat-detail">combined probability</span>
                  </div>
                  <div className="stat-card">
                    <span className="stat-label">Avg Legs Correct</span>
                    <span className="stat-value">{parlayStats.avg_legs_correct || 0}</span>
                    <span className="stat-detail">per parlay</span>
                  </div>
                </div>
              </>
            )}

            {parlayStats.recent && parlayStats.recent.length > 0 && (
              <div className="recent-section parlay-recent">
                <h3 className="section-title" style={{ fontSize: '1rem', marginBottom: '0.75rem' }}>Recent Parlays</h3>
                <div className="recent-table-container">
                  <table className="recent-table">
                    <thead>
                      <tr>
                        <th>Date</th>
                        <th>Legs</th>
                        <th>Est. Prob</th>
                        <th>Result</th>
                        <th>Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {parlayStats.recent.map((p, idx) => {
                        const isExpanded = expandedParlayIdx === idx;
                        const graded = p.correct !== null && p.correct !== undefined;
                        const legsCorrect = p.legs_correct ?? 0;
                        return (
                          <Fragment key={idx}>
                            <tr
                              className={`parlay-row ${graded ? (p.correct ? 'correct' : 'incorrect') : ''} ${p.legs?.length ? 'expandable' : ''}`}
                              onClick={() => p.legs?.length ? setExpandedParlayIdx(isExpanded ? null : idx) : null}
                              style={{ cursor: p.legs?.length ? 'pointer' : 'default' }}
                            >
                              <td className="date-cell">{p.game_date}</td>
                              <td>{p.num_legs}</td>
                              <td>{p.combined_prob?.toFixed(1)}%</td>
                              <td>
                                {graded
                                  ? `${p.correct ? '✅' : '❌'} ${legsCorrect}/${p.num_legs}`
                                  : <span className="result-badge pending">Pending</span>
                                }
                              </td>
                              <td>
                                {graded
                                  ? <span className={`confidence-tag ${p.correct ? 'strong' : 'close'}`}>{p.correct ? 'Hit' : 'Miss'}</span>
                                  : '—'
                                }
                              </td>
                            </tr>
                            {isExpanded && p.legs?.map((leg, li) => (
                              <tr key={`${idx}-${li}`} className="parlay-leg-row">
                                <td colSpan={5}>
                                  <div className="parlay-leg-detail">
                                    <span className="leg-detail-label">{leg.label}</span>
                                    <span className="leg-detail-matchup">{leg.away_team} @ {leg.home_team}</span>
                                    <span className="leg-detail-prob">{leg.prob?.toFixed(1)}%</span>
                                    {leg.correct !== null && leg.correct !== undefined
                                      ? <span className={`leg-detail-result ${leg.correct ? 'correct' : 'incorrect'}`}>{leg.correct ? '✅' : '❌'}</span>
                                      : <span className="leg-detail-result pending">—</span>
                                    }
                                  </div>
                                </td>
                              </tr>
                            ))}
                          </Fragment>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

export default Accuracy;
