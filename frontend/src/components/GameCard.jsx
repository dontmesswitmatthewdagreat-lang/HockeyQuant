import { useState, useEffect } from 'react';
import { fetchTeamGoalies } from '../api';
import './GameCard.css';

function GameCard({ prediction, onGoalieChange, isRecalculating }) {
  const { away, home, pick, diff, confidence, factors } = prediction;

  const [awayGoalies, setAwayGoalies] = useState([]);
  const [homeGoalies, setHomeGoalies] = useState([]);
  const [selectedAwayGoalie, setSelectedAwayGoalie] = useState(away.goalie);
  const [selectedHomeGoalie, setSelectedHomeGoalie] = useState(home.goalie);
  const [loadingGoalies, setLoadingGoalies] = useState(true);

  // Fetch goalies for both teams on mount
  useEffect(() => {
    async function loadGoalies() {
      setLoadingGoalies(true);
      try {
        const [awayData, homeData] = await Promise.all([
          fetchTeamGoalies(away.team),
          fetchTeamGoalies(home.team),
        ]);
        setAwayGoalies(awayData);
        setHomeGoalies(homeData);
      } catch (err) {
        console.error('Failed to load goalies:', err);
      } finally {
        setLoadingGoalies(false);
      }
    }
    loadGoalies();
  }, [away.team, home.team]);

  // Update selected goalies when prediction changes (after recalculation)
  useEffect(() => {
    setSelectedAwayGoalie(away.goalie);
    setSelectedHomeGoalie(home.goalie);
  }, [away.goalie, home.goalie]);

  const getConfidenceClass = () => {
    if (confidence === 'STRONG') return 'confidence-strong';
    if (confidence === 'MODERATE') return 'confidence-moderate';
    return 'confidence-close';
  };

  const formatGoalieOption = (goalie) => {
    const lastName = goalie.name?.split(' ').pop() || 'TBD';
    const gsaxSign = goalie.gsax >= 0 ? '+' : '';
    return `${lastName} (${gsaxSign}${goalie.gsax.toFixed(1)})`;
  };

  const handleAwayGoalieChange = (e) => {
    const newGoalie = e.target.value;
    setSelectedAwayGoalie(newGoalie);
    if (onGoalieChange) {
      onGoalieChange(away.team, newGoalie);
    }
  };

  const handleHomeGoalieChange = (e) => {
    const newGoalie = e.target.value;
    setSelectedHomeGoalie(newGoalie);
    if (onGoalieChange) {
      onGoalieChange(home.team, newGoalie);
    }
  };

  return (
    <div className={`game-card ${isRecalculating ? 'recalculating' : ''}`}>
      {/* Header */}
      <div className="card-header">
        <h3 className="matchup">{away.team} @ {home.team}</h3>
        <span className={`confidence-badge ${getConfidenceClass()}`}>
          {isRecalculating ? '...' : confidence}
        </span>
      </div>

      <div className="card-divider" />

      {/* Scores Section */}
      <div className="scores-section">
        <div className="team-score">
          <span className="label">AWAY</span>
          <span className="team-abbrev">{away.team}</span>
          <span className="score">{away.final_score.toFixed(1)}</span>
        </div>

        <div className="pick-section">
          <span className="label">PICK</span>
          <div className="pick-box">
            <span className="pick-team">{pick}</span>
          </div>
          <span className="diff">(+{diff.toFixed(1)})</span>
        </div>

        <div className="team-score">
          <span className="label">HOME</span>
          <span className="team-abbrev">{home.team}</span>
          <span className="score">{home.final_score.toFixed(1)}</span>
        </div>
      </div>

      {/* Goalie Selection */}
      <div className="goalie-selection">
        <span className="goalie-label">STARTING GOALIES</span>
        <div className="goalie-dropdowns">
          <div className="goalie-select-wrapper">
            <span className="team-label">{away.team}</span>
            <select
              className="goalie-select"
              value={selectedAwayGoalie}
              onChange={handleAwayGoalieChange}
              disabled={loadingGoalies || isRecalculating}
            >
              {loadingGoalies ? (
                <option>Loading...</option>
              ) : (
                awayGoalies.map((g) => (
                  <option key={g.name} value={g.name}>
                    {formatGoalieOption(g)}{g.is_starter ? ' ★' : ''}
                  </option>
                ))
              )}
            </select>
          </div>

          <div className="goalie-select-wrapper">
            <span className="team-label">{home.team}</span>
            <select
              className="goalie-select"
              value={selectedHomeGoalie}
              onChange={handleHomeGoalieChange}
              disabled={loadingGoalies || isRecalculating}
            >
              {loadingGoalies ? (
                <option>Loading...</option>
              ) : (
                homeGoalies.map((g) => (
                  <option key={g.name} value={g.name}>
                    {formatGoalieOption(g)}{g.is_starter ? ' ★' : ''}
                  </option>
                ))
              )}
            </select>
          </div>
        </div>
      </div>

      {/* Info Boxes */}
      <div className="info-boxes">
        <div className="info-box">
          <span className="info-label">H2H RECORD</span>
          <span className="info-value">{home.h2h || 'N/A'}</span>
        </div>

        <div className="info-box">
          <span className="info-label">KEY FACTORS</span>
          <span className="info-value">
            {factors?.length > 0 ? factors.join(', ') : 'No major factors'}
          </span>
        </div>
      </div>
    </div>
  );
}

export default GameCard;
