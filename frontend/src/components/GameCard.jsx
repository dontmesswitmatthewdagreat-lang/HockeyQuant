import { useState } from 'react';
import './GameCard.css';

function GameCard({ prediction, onGoalieToggle, isRecalculating }) {
  const { away, home, pick, diff, confidence, factors } = prediction;

  // Track which team is using backup goalie
  const [awayUsingBackup, setAwayUsingBackup] = useState(false);
  const [homeUsingBackup, setHomeUsingBackup] = useState(false);

  const getConfidenceClass = () => {
    if (confidence === 'STRONG') return 'confidence-strong';
    if (confidence === 'MODERATE') return 'confidence-moderate';
    return 'confidence-close';
  };

  // Format goalie display: "LastName (+GSAX)" or "LastName * (+GSAX)" for backup
  const formatGoalie = (name, gsax, isBackup = false) => {
    const lastName = name?.split(' ').pop() || 'TBD';
    const suffix = isBackup ? ' *' : '';
    const gsaxSign = gsax >= 0 ? '+' : '';
    return `${lastName}${suffix} (${gsaxSign}${gsax?.toFixed(1) || '0.0'})`;
  };

  // Handle clicking on away goalie to toggle
  const handleAwayGoalieClick = () => {
    if (!away.backup_goalie) return; // No backup available

    const newUsingBackup = !awayUsingBackup;
    setAwayUsingBackup(newUsingBackup);

    if (onGoalieToggle) {
      // Pass the goalie name to use (backup if toggling on, starter if toggling off)
      const goalieName = newUsingBackup ? away.backup_goalie : null;
      onGoalieToggle(away.team, goalieName);
    }
  };

  // Handle clicking on home goalie to toggle
  const handleHomeGoalieClick = () => {
    if (!home.backup_goalie) return; // No backup available

    const newUsingBackup = !homeUsingBackup;
    setHomeUsingBackup(newUsingBackup);

    if (onGoalieToggle) {
      const goalieName = newUsingBackup ? home.backup_goalie : null;
      onGoalieToggle(home.team, goalieName);
    }
  };

  // Determine which goalie to display for each team
  const awayGoalieDisplay = awayUsingBackup && away.backup_goalie
    ? { name: away.backup_goalie, gsax: away.backup_goalie_gsax }
    : { name: away.goalie, gsax: away.goalie_gsax };

  const homeGoalieDisplay = homeUsingBackup && home.backup_goalie
    ? { name: home.backup_goalie, gsax: home.backup_goalie_gsax }
    : { name: home.goalie, gsax: home.goalie_gsax };

  // Check if any backups are available for click-to-swap functionality
  const hasBackups = away.backup_goalie || home.backup_goalie;

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

      {/* Goalie Section - Click to Toggle */}
      <div className={`goalie-box ${hasBackups ? 'clickable' : ''}`}>
        <span className="goalie-title">
          {hasBackups ? 'STARTERS (click to swap)' : 'PREDICTED STARTERS'}
        </span>
        <div className="goalie-lines">
          <div
            className={`goalie-line ${away.backup_goalie ? 'has-backup' : ''}`}
            onClick={handleAwayGoalieClick}
          >
            <span className="goalie-team">{away.team}</span>
            <span className="goalie-name">
              {formatGoalie(awayGoalieDisplay.name, awayGoalieDisplay.gsax, awayUsingBackup)}
            </span>
          </div>
          <div
            className={`goalie-line ${home.backup_goalie ? 'has-backup' : ''}`}
            onClick={handleHomeGoalieClick}
          >
            <span className="goalie-team">{home.team}</span>
            <span className="goalie-name">
              {formatGoalie(homeGoalieDisplay.name, homeGoalieDisplay.gsax, homeUsingBackup)}
            </span>
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
