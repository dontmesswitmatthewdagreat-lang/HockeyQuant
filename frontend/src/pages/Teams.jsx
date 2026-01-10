import { useState, useEffect } from 'react';
import { fetchTeams, fetchTeam } from '../api';
import LoadingSpinner from '../components/LoadingSpinner';
import './Teams.css';

function Teams() {
  const [teams, setTeams] = useState([]);
  const [selectedTeam, setSelectedTeam] = useState(null);
  const [teamDetails, setTeamDetails] = useState(null);
  const [loading, setLoading] = useState(true);
  const [detailsLoading, setDetailsLoading] = useState(false);
  const [error, setError] = useState(null);

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

  // Group teams by conference and division
  const groupedTeams = teams.reduce((acc, team) => {
    const key = `${team.conference}-${team.division}`;
    if (!acc[key]) {
      acc[key] = {
        conference: team.conference,
        division: team.division,
        teams: []
      };
    }
    acc[key].teams.push(team);
    return acc;
  }, {});

  if (loading) {
    return <LoadingSpinner message="Loading teams..." />;
  }

  return (
    <div className="teams-page">
      <h1 className="page-title">NHL Teams</h1>

      {error && (
        <div className="error-message">
          <p>Error: {error}</p>
        </div>
      )}

      <div className="teams-grid">
        {Object.values(groupedTeams).map((group) => (
          <div key={`${group.conference}-${group.division}`} className="division-group">
            <h3 className="division-title">
              {group.conference} - {group.division}
            </h3>
            <div className="division-teams">
              {group.teams.map((team) => (
                <button
                  key={team.abbrev}
                  className={`team-button ${selectedTeam === team.abbrev ? 'selected' : ''}`}
                  onClick={() => handleTeamClick(team.abbrev)}
                >
                  <span className="team-abbrev">{team.abbrev}</span>
                  <span className="team-name">{team.name}</span>
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Team Details Modal */}
      {selectedTeam && (
        <div className="modal-overlay" onClick={closeDetails}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={closeDetails}>×</button>

            {detailsLoading ? (
              <LoadingSpinner message="Loading team stats..." />
            ) : teamDetails ? (
              <div className="team-details">
                <h2 className="details-title">{teamDetails.team.name}</h2>
                <p className="details-subtitle">
                  {teamDetails.team.conference} Conference - {teamDetails.team.division} Division
                </p>

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
                        {goalie.name} {goalie.is_starter && '(Starter)'}
                      </span>
                      <span className="goalie-stats">
                        GSAx: {goalie.gsax.toFixed(1)} | Sv%: {(goalie.sv_pct * 100).toFixed(1)}% | GAA: {goalie.gaa.toFixed(2)}
                      </span>
                    </div>
                  ))}
                </div>

                <h3 className="section-title">Recent Form</h3>
                <p className="recent-form">{teamDetails.recent_form}</p>

                {teamDetails.injuries.length > 0 && (
                  <>
                    <h3 className="section-title">Injuries</h3>
                    <p className="injuries">{teamDetails.injuries.join(', ')}</p>
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
