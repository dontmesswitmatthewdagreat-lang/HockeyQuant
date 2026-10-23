import { useState, useEffect, useMemo } from 'react';
import {
  fetchTeams, fetchTeam, fetchAdvancedTeam, fetchTeamLines,
  fetchAdvancedSkaters, fetchAdvancedGoalies, fetchLeaguePulses,
} from '../api';
import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import LoadingSpinner from '../components/LoadingSpinner';
import DecompositionCard from '../components/DecompositionCard';
import LuckMeter from '../components/LuckMeter';
import LineChemistry from '../components/LineChemistry';
import PlayerImpactModal from '../components/PlayerImpactModal';
import './Teams.css';

const DIVISIONS = ['All', 'Atlantic', 'Metropolitan', 'Central', 'Pacific'];

function Teams() {
  const [teams, setTeams] = useState([]);
  const [selectedTeam, setSelectedTeam] = useState(null);
  const [teamDetails, setTeamDetails] = useState(null);
  const [loading, setLoading] = useState(true);
  const [detailsLoading, setDetailsLoading] = useState(false);
  const [error, setError] = useState(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedDivision, setSelectedDivision] = useState('All');
  const [activeTab, setActiveTab] = useState('overview');
  // Advanced surfaces load separately from the team payload and are allowed to
  // fail on their own — a metrics outage should cost you a card, not the page.
  const [advanced, setAdvanced] = useState(null);
  const [lines, setLines] = useState(null);
  const [skaters, setSkaters] = useState([]);
  const [goalies, setGoalies] = useState([]);
  const [luckPulse, setLuckPulse] = useState(null);
  const [selectedPlayer, setSelectedPlayer] = useState(null);

  useEffect(() => {
    loadTeams();
  }, []);

  async function loadTeams() {
    try {
      const data = await fetchTeams();
      setTeams(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  async function handleTeamClick(abbrev) {
    setSelectedTeam(abbrev);
    setActiveTab('overview');
    setDetailsLoading(true);
    setAdvanced(null);
    setLines(null);
    setSkaters([]);
    setGoalies([]);
    try {
      const data = await fetchTeam(abbrev);
      setTeamDetails(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setDetailsLoading(false);
    }

    // Best-effort, in parallel, after the page is already usable.
    fetchAdvancedTeam(abbrev).then(setAdvanced).catch(() => {});
    fetchTeamLines(abbrev).then(setLines).catch(() => {});
    fetchAdvancedSkaters(abbrev).then((d) => setSkaters(d.skaters || [])).catch(() => {});
    fetchAdvancedGoalies(abbrev).then((d) => setGoalies(d.goalies || [])).catch(() => {});
    if (!luckPulse) {
      fetchLeaguePulses()
        .then((d) => setLuckPulse((d.pulses || []).find((p) => p.id === 'luck') || null))
        .catch(() => {});
    }
  }

  function closeDetails() {
    setSelectedTeam(null);
    setTeamDetails(null);
    setSelectedPlayer(null);
  }

  // Filter and sort teams
  const filteredTeams = useMemo(() => {
    let result = [...teams];

    // Filter by division
    if (selectedDivision !== 'All') {
      result = result.filter(team => team.division === selectedDivision);
    }

    // Filter by search query
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      result = result.filter(team =>
        team.name.toLowerCase().includes(query) ||
        team.abbrev.toLowerCase().includes(query)
      );
    }

    // Sort by points (descending), then points percentage
    result.sort((a, b) => {
      const ptsA = a.points || 0;
      const ptsB = b.points || 0;
      if (ptsB !== ptsA) return ptsB - ptsA;
      return (b.points_pct || 0) - (a.points_pct || 0);
    });

    return result;
  }, [teams, selectedDivision, searchQuery]);

  // Calculate streak display
  const getStreakDisplay = (team) => {
    // This would ideally come from the API, but we'll simulate for now
    const wins = team.wins || 0;
    const losses = team.losses || 0;
    const total = wins + losses;
    if (total === 0) return '-';

    // Simulated streak based on recent performance
    const winPct = wins / total;
    if (winPct > 0.6) return { text: 'W3', type: 'win' };
    if (winPct < 0.4) return { text: 'L2', type: 'loss' };
    return { text: 'W1', type: 'win' };
  };

  if (loading) {
    return <LoadingSpinner message="Loading teams..." />;
  }

  return (
    <div className="teams-page">
      {/* Header */}
      <div className="teams-header">
        <h1>Team Statistics</h1>
        <p className="teams-subtitle">Complete NHL team standings and statistics</p>
      </div>

      {/* Search and Filters */}
      <div className="teams-controls">
        <div className="search-box">
          <svg className="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <circle cx="11" cy="11" r="8"></circle>
            <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
          </svg>
          <input
            type="text"
            placeholder="Search teams..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="search-input"
          />
        </div>

        <div className="division-filters">
          {DIVISIONS.map(division => (
            <button
              key={division}
              className={`filter-pill ${selectedDivision === division ? 'active' : ''}`}
              onClick={() => setSelectedDivision(division)}
            >
              {division}
            </button>
          ))}
        </div>
      </div>

      {error && (
        <div className="error-message">
          <p>Error: {error}</p>
        </div>
      )}

      {/* Standings Table */}
      <div className="standings-table-container">
        <table className="standings-table">
          <thead>
            <tr>
              <th className="col-rank">Rank</th>
              <th className="col-team">Team</th>
              <th className="col-gp">GP</th>
              <th className="col-record">W-L-OT</th>
              <th className="col-pts">PTS</th>
              <th className="col-pct">P%</th>
              <th className="col-gf">GF</th>
              <th className="col-ga">GA</th>
              <th className="col-diff">DIFF</th>
              <th className="col-streak">Streak</th>
            </tr>
          </thead>
          <tbody>
            {filteredTeams.map((team, index) => {
              const streak = getStreakDisplay(team);
              const gp = (team.wins || 0) + (team.losses || 0) + (team.otl || 0);
              const diff = (team.goals_for || 0) - (team.goals_against || 0);

              return (
                <tr
                  key={team.abbrev}
                  className="team-row"
                  onClick={() => handleTeamClick(team.abbrev)}
                >
                  <td className="col-rank">{index + 1}</td>
                  <td className="col-team">
                    <div className="team-cell">
                      <img
                        src={getTeamLogo(team.abbrev)}
                        alt={team.abbrev}
                        className="team-logo"
                        onError={(e) => { e.target.style.display = 'none'; }}
                      />
                      <div className="team-info">
                        <span className="team-name">{getTeamName(team.abbrev)}</span>
                        <span className="team-division">{team.division}</span>
                      </div>
                    </div>
                  </td>
                  <td className="col-gp">{gp}</td>
                  <td className="col-record">{team.wins || 0}-{team.losses || 0}-{team.otl || 0}</td>
                  <td className="col-pts">{team.points || 0}</td>
                  <td className="col-pct">{((team.points_pct || 0) * 100).toFixed(1)}</td>
                  <td className="col-gf">{team.goals_for || '-'}</td>
                  <td className="col-ga">{team.goals_against || '-'}</td>
                  <td className={`col-diff ${diff > 0 ? 'positive' : diff < 0 ? 'negative' : ''}`}>
                    {diff > 0 ? '+' : ''}{diff}
                  </td>
                  <td className="col-streak">
                    {typeof streak === 'object' ? (
                      <span className={`streak-badge ${streak.type}`}>
                        {streak.text}
                      </span>
                    ) : streak}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>

        {filteredTeams.length === 0 && (
          <div className="no-results">
            <p>No teams found matching your criteria</p>
          </div>
        )}
      </div>

      {/* Team Details Modal */}
      {selectedTeam && (
        <div className="modal-overlay" onClick={closeDetails}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={closeDetails}>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <line x1="18" y1="6" x2="6" y2="18"></line>
                <line x1="6" y1="6" x2="18" y2="18"></line>
              </svg>
            </button>

            {detailsLoading ? (
              <div className="modal-loading">
                <LoadingSpinner message="Loading team stats..." />
              </div>
            ) : teamDetails ? (
              <div className="team-details">
                <div className="details-header">
                  <img
                    src={getTeamLogo(selectedTeam)}
                    alt={selectedTeam}
                    className="details-logo"
                    onError={(e) => { e.target.style.display = 'none'; }}
                  />
                  <div>
                    <h2 className="details-title">{teamDetails.team.name}</h2>
                    <p className="details-subtitle">
                      {teamDetails.team.conference} - {teamDetails.team.division}
                    </p>
                  </div>
                </div>

                {/* Tab Navigation */}
                <div className="detail-tabs">
                  <button
                    className={`detail-tab ${activeTab === 'overview' ? 'active' : ''}`}
                    onClick={() => setActiveTab('overview')}
                  >
                    Overview
                  </button>
                  <button
                    className={`detail-tab ${activeTab === 'advanced' ? 'active' : ''}`}
                    onClick={() => setActiveTab('advanced')}
                  >
                    Advanced Stats
                  </button>
                  <button
                    className={`detail-tab ${activeTab === 'players' ? 'active' : ''}`}
                    onClick={() => setActiveTab('players')}
                  >
                    Player Impact
                  </button>
                  <button
                    className={`detail-tab ${activeTab === 'roster' ? 'active' : ''}`}
                    onClick={() => setActiveTab('roster')}
                  >
                    Goalies & Injuries
                  </button>
                </div>

                {/* Overview Tab */}
                {activeTab === 'overview' && (
                  <>
                    <div className="stats-grid">
                      <div className="stat-box">
                        <span className="stat-label">Record</span>
                        <span className="stat-value">
                          {teamDetails.stats.wins}-{teamDetails.stats.losses}-{teamDetails.stats.otl}
                        </span>
                      </div>
                      <div className="stat-box">
                        <span className="stat-label">Points</span>
                        <span className="stat-value">{teamDetails.stats.points}</span>
                      </div>
                      <div className="stat-box">
                        <span className="stat-label">Points %</span>
                        <span className="stat-value">
                          {(teamDetails.stats.points_pct * 100).toFixed(1)}%
                        </span>
                      </div>
                      <div className="stat-box">
                        <span className="stat-label">Goal Diff</span>
                        <span className={`stat-value ${teamDetails.stats.goal_diff >= 0 ? 'positive' : 'negative'}`}>
                          {teamDetails.stats.goal_diff >= 0 ? '+' : ''}{teamDetails.stats.goal_diff}
                        </span>
                      </div>
                      {teamDetails.stats.xgf && (
                        <div className="stat-box">
                          <span className="stat-label">xGF</span>
                          <span className="stat-value">{teamDetails.stats.xgf}</span>
                        </div>
                      )}
                      {teamDetails.stats.xga && (
                        <div className="stat-box">
                          <span className="stat-label">xGA</span>
                          <span className="stat-value">{teamDetails.stats.xga}</span>
                        </div>
                      )}
                    </div>
                    <h3 className="section-title">Recent Form</h3>
                    <p className="recent-form">{teamDetails.recent_form}</p>
                  </>
                )}

                {/* Advanced Stats Tab */}
                {activeTab === 'advanced' && teamDetails.advanced_stats && (
                  <div className="advanced-stats-content">
                    {/* Each of these renders nothing until its own fetch lands,
                        so the possession numbers below are never held up. */}
                    <DecompositionCard data={advanced} />
                    <LuckMeter pulse={luckPulse} abbrev={selectedTeam} />
                    <LineChemistry data={lines} />
                    <div className="advanced-section">
                      <h4 className="advanced-section-title">Possession</h4>
                      <div className="stats-grid three-col">
                        <div className="stat-box">
                          <span className="stat-label">Corsi%</span>
                          <span className={`stat-value ${teamDetails.advanced_stats.corsi_pct > 50 ? 'positive' : teamDetails.advanced_stats.corsi_pct < 50 ? 'negative' : ''}`}>
                            {teamDetails.advanced_stats.corsi_pct}%
                          </span>
                        </div>
                        <div className="stat-box">
                          <span className="stat-label">Fenwick%</span>
                          <span className={`stat-value ${teamDetails.advanced_stats.fenwick_pct > 50 ? 'positive' : teamDetails.advanced_stats.fenwick_pct < 50 ? 'negative' : ''}`}>
                            {teamDetails.advanced_stats.fenwick_pct}%
                          </span>
                        </div>
                        <div className="stat-box">
                          <span className="stat-label">xG%</span>
                          <span className={`stat-value ${teamDetails.advanced_stats.xg_pct > 50 ? 'positive' : teamDetails.advanced_stats.xg_pct < 50 ? 'negative' : ''}`}>
                            {teamDetails.advanced_stats.xg_pct}%
                          </span>
                        </div>
                      </div>
                    </div>

                    <div className="advanced-section">
                      <h4 className="advanced-section-title">Efficiency</h4>
                      <div className="stats-grid three-col">
                        <div className="stat-box">
                          <span className="stat-label">PDO</span>
                          <span className={`stat-value ${teamDetails.advanced_stats.pdo > 100.5 ? 'positive' : teamDetails.advanced_stats.pdo < 99.5 ? 'negative' : ''}`}>
                            {teamDetails.advanced_stats.pdo}
                          </span>
                        </div>
                        <div className="stat-box">
                          <span className="stat-label">Sh%</span>
                          <span className="stat-value">{teamDetails.advanced_stats.shooting_pct}%</span>
                        </div>
                        <div className="stat-box">
                          <span className="stat-label">Sv%</span>
                          <span className="stat-value">{teamDetails.advanced_stats.save_pct}%</span>
                        </div>
                      </div>
                    </div>

                    <div className="advanced-section">
                      <h4 className="advanced-section-title">High Danger</h4>
                      <div className="stats-grid three-col">
                        <div className="stat-box">
                          <span className="stat-label">HD CF%</span>
                          <span className={`stat-value ${teamDetails.advanced_stats.hd_cf_pct > 50 ? 'positive' : teamDetails.advanced_stats.hd_cf_pct < 50 ? 'negative' : ''}`}>
                            {teamDetails.advanced_stats.hd_cf_pct}%
                          </span>
                        </div>
                        <div className="stat-box">
                          <span className="stat-label">HD GF</span>
                          <span className="stat-value">{teamDetails.advanced_stats.hd_goals_for}</span>
                        </div>
                        <div className="stat-box">
                          <span className="stat-label">HD GA</span>
                          <span className="stat-value">{teamDetails.advanced_stats.hd_goals_against}</span>
                        </div>
                      </div>
                    </div>

                    <div className="advanced-section">
                      <h4 className="advanced-section-title">Special Teams</h4>
                      <div className="stats-grid two-col">
                        <div className="stat-box">
                          <span className="stat-label">PP%</span>
                          <span className="stat-value">{teamDetails.advanced_stats.pp_pct}%</span>
                        </div>
                        <div className="stat-box">
                          <span className="stat-label">PK%</span>
                          <span className="stat-value">{teamDetails.advanced_stats.pk_pct}%</span>
                        </div>
                      </div>
                    </div>

                    <div className="advanced-section">
                      <h4 className="advanced-section-title">Shot Rates (per game)</h4>
                      <div className="stats-grid two-col">
                        <div className="stat-box">
                          <span className="stat-label">SOG For/G</span>
                          <span className="stat-value">{teamDetails.advanced_stats.shots_for_pg}</span>
                        </div>
                        <div className="stat-box">
                          <span className="stat-label">SOG Against/G</span>
                          <span className="stat-value">{teamDetails.advanced_stats.shots_against_pg}</span>
                        </div>
                      </div>
                    </div>
                  </div>
                )}

                {activeTab === 'advanced' && !teamDetails.advanced_stats && (
                  <p className="recent-form">Advanced stats are not available for this team.</p>
                )}

                {/* Goalies & Injuries Tab */}
                {/* Player Impact Tab — rows open a percentile card */}
                {activeTab === 'players' && (
                  <div className="advanced-stats-content">
                    {skaters.length === 0 && goalies.length === 0 ? (
                      <p className="adv-note">Loading player impact…</p>
                    ) : (
                      <>
                        {skaters.length > 0 && (
                          <div className="adv-card">
                            <div className="adv-card-head"><h4>Skaters</h4></div>
                            <p className="adv-note">
                              Ranked by Game Score per 60. Tap a row for league percentiles.
                            </p>
                            <table className="adv-unit-table">
                              <thead>
                                <tr>
                                  <th>Player</th>
                                  <th>GP</th>
                                  <th>P</th>
                                  <th>GS/60</th>
                                  <th>xGF%</th>
                                </tr>
                              </thead>
                              <tbody>
                                {[...skaters]
                                  .sort((a, b) => (b.game_score_per60 ?? 0) - (a.game_score_per60 ?? 0))
                                  .map((s) => (
                                    <tr
                                      key={s.player_id}
                                      className="adv-clickable"
                                      onClick={() => setSelectedPlayer({ id: s.player_id, goalie: false })}
                                    >
                                      <td>
                                        {s.name}
                                        <span className="adv-unit-sub"> {s.position}</span>
                                      </td>
                                      <td>{s.games_played}</td>
                                      <td>{s.points ?? '—'}</td>
                                      <td>{s.game_score_per60?.toFixed(2) ?? '—'}</td>
                                      <td>{s.xgf_pct?.toFixed(1) ?? '—'}</td>
                                    </tr>
                                  ))}
                              </tbody>
                            </table>
                          </div>
                        )}

                        {goalies.length > 0 && (
                          <div className="adv-card">
                            <div className="adv-card-head"><h4>Goalies</h4></div>
                            <p className="adv-note">
                              GSAx is goals saved above expected. Tap a row for percentiles.
                            </p>
                            <table className="adv-unit-table">
                              <thead>
                                <tr>
                                  <th>Goalie</th>
                                  <th>GP</th>
                                  <th>SV%</th>
                                  <th>GSAx</th>
                                  <th>HD SV%</th>
                                </tr>
                              </thead>
                              <tbody>
                                {[...goalies]
                                  .sort((a, b) => (b.gsax ?? 0) - (a.gsax ?? 0))
                                  .map((g) => (
                                    <tr
                                      key={g.player_id}
                                      className="adv-clickable"
                                      onClick={() => setSelectedPlayer({ id: g.player_id, goalie: true })}
                                    >
                                      <td>{g.name}</td>
                                      <td>{g.games_played}</td>
                                      <td>{g.save_pct?.toFixed(2) ?? '—'}</td>
                                      <td className={(g.gsax ?? 0) >= 0 ? 'adv-pos-text' : 'adv-neg-text'}>
                                        {g.gsax > 0 ? '+' : ''}{g.gsax?.toFixed(2) ?? '—'}
                                      </td>
                                      <td>{g.hd_save_pct?.toFixed(2) ?? '—'}</td>
                                    </tr>
                                  ))}
                              </tbody>
                            </table>
                          </div>
                        )}
                      </>
                    )}
                  </div>
                )}

                {activeTab === 'roster' && (
                  <>
                    <h3 className="section-title">Goalies</h3>
                    <div className="goalies-list">
                      {teamDetails.goalies.map((goalie, i) => (
                        <div key={i} className="goalie-row">
                          <span className="goalie-name">
                            {goalie.name} {goalie.is_starter && <span className="starter-badge">Starter</span>}
                          </span>
                          <div className="goalie-stats">
                            <span className="goalie-stat">GSAx: {goalie.gsax.toFixed(1)}</span>
                            <span className="goalie-stat">Sv%: {(goalie.sv_pct * 100).toFixed(1)}%</span>
                            <span className="goalie-stat">GAA: {goalie.gaa.toFixed(2)}</span>
                          </div>
                        </div>
                      ))}
                    </div>

                    {teamDetails.injuries.length > 0 && (
                      <>
                        <h3 className="section-title">Injuries</h3>
                        <div className="injuries-list">
                          {teamDetails.injuries.map((injury, i) => (
                            <span key={i} className="injury-tag">{injury}</span>
                          ))}
                        </div>
                      </>
                    )}

                    {teamDetails.injuries.length === 0 && (
                      <p className="recent-form" style={{ marginTop: '1rem' }}>No injuries reported.</p>
                    )}
                  </>
                )}
              </div>
            ) : null}
          </div>
        </div>
      )}

      {/* Rendered after the team modal so it stacks above it. */}
      {selectedPlayer && (
        <PlayerImpactModal
          key={selectedPlayer.id}
          playerId={selectedPlayer.id}
          isGoalie={selectedPlayer.goalie}
          onClose={() => setSelectedPlayer(null)}
        />
      )}
    </div>
  );
}

export default Teams;
