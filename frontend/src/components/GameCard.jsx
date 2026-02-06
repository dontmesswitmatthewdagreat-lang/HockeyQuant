import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import './GameCard.css';

function GameCard({ prediction }) {
  const {
    away,
    home,
    pick,
    diff,
    confidence,
    factors,
    game_time,
    is_official,
    goalie_status_away,
    goalie_status_home,
  } = prediction;

  // Format game time for display
  const formatGameTime = (isoString) => {
    if (!isoString) return '';
    try {
      const date = new Date(isoString);
      return date.toLocaleTimeString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
        timeZoneName: 'short',
      });
    } catch {
      return '';
    }
  };

  // Calculate win probability (simple approximation based on scores)
  const calculateWinProb = () => {
    const total = away.final_score + home.final_score;
    if (total === 0) return 50;
    const winnerScore = pick === home.team ? home.final_score : away.final_score;
    return Math.round((winnerScore / total) * 100);
  };

  const winProb = calculateWinProb();

  // Determine if a team is the predicted winner
  const awayIsWinner = pick === away.team;
  const homeIsWinner = pick === home.team;

  // Check if team is hot (streak multiplier > 1.02)
  const awayIsHot = away.streak_mult > 1.02;
  const homeIsHot = home.streak_mult > 1.02;

  // Format team record from stats if available
  const formatRecord = (team) => {
    // If we have streak info, extract the record
    if (team.streak && team.streak.includes('L10')) {
      return team.streak.split(' ')[0];
    }
    return '';
  };

  return (
    <div className={`game-card ${is_official ? 'official' : ''}`}>
      {/* Game Time Header */}
      <div className="game-time-header">
        <span className="game-time">{formatGameTime(game_time)}</span>
        {is_official && (
          <span className="live-badge">OFFICIAL</span>
        )}
      </div>

      {/* Teams Section */}
      <div className="teams-section">
        {/* Away Team */}
        <div className={`team-row ${awayIsWinner ? 'winner' : ''}`}>
          <div className="team-info">
            <img
              src={getTeamLogo(away.team)}
              alt={away.team}
              className="team-logo"
              onError={(e) => { e.target.style.display = 'none'; }}
            />
            <div className="team-details">
              <span className="team-name">
                {getTeamName(away.team)}
                {awayIsHot && <span className="hot-indicator" title="Hot streak">&#128293;</span>}
              </span>
              <span className="team-record">{formatRecord(away)}</span>
            </div>
          </div>
          <div className="team-score-section">
            {awayIsWinner && (
              <span className="win-prob-badge">{winProb}%</span>
            )}
            <span className="team-score">{Math.round(away.final_score)}</span>
          </div>
        </div>

        {/* Home Team */}
        <div className={`team-row ${homeIsWinner ? 'winner' : ''}`}>
          <div className="team-info">
            <img
              src={getTeamLogo(home.team)}
              alt={home.team}
              className="team-logo"
              onError={(e) => { e.target.style.display = 'none'; }}
            />
            <div className="team-details">
              <span className="team-name">
                {getTeamName(home.team)}
                {homeIsHot && <span className="hot-indicator" title="Hot streak">&#128293;</span>}
              </span>
              <span className="team-record">{formatRecord(home)}</span>
            </div>
          </div>
          <div className="team-score-section">
            {homeIsWinner && (
              <span className="win-prob-badge">{winProb}%</span>
            )}
            <span className="team-score">{Math.round(home.final_score)}</span>
          </div>
        </div>
      </div>

      {/* Key Factors */}
      <div className="key-factors-section">
        <div className="factors-header">
          <span>Key Factors</span>
          <svg className="expand-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <polyline points="9 18 15 12 9 6"></polyline>
          </svg>
        </div>
        <div className="factors-tags">
          {factors && factors.length > 0 ? (
            factors.map((factor, idx) => (
              <span key={idx} className="factor-tag">{factor}</span>
            ))
          ) : (
            <>
              <span className="factor-tag">
                {confidence === 'STRONG' ? 'Strong xG differential' :
                 confidence === 'MODERATE' ? 'Moderate advantage' : 'Even matchup'}
              </span>
              {(goalie_status_home === 'confirmed' || goalie_status_away === 'confirmed') && (
                <span className="factor-tag">Goalie confirmed</span>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

export default GameCard;
