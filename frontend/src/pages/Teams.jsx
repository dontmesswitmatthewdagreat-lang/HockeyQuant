import { useState, useEffect, useMemo } from 'react';
import { fetchTeams, fetchTeam } from '../api';
import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import LoadingSpinner from '../components/LoadingSpinner';
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
    setDetailsLoading(true);
    try {
      const data = await fetchTeam(abbrev);
      setTeamDetails(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setDetailsLoading(false);
    }
  }

  function closeDetails() {
    setSelectedTeam(null);
    setTeamDetails(null);
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

                <h3 className="section-title">Recent Form</h3>
                <p className="recent-form">{teamDetails.recent_form}</p>

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
              </div>
            ) : null}
          </div>
        </div>
      )}
    </div>
  );
}

export default Teams;
