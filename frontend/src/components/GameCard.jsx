import './GameCard.css';

function GameCard({ prediction }) {
  const {
    away,
    home,
    pick,
    diff,
    confidence,
    factors,
    is_official,
    official_at,
    goalie_status_away,
    goalie_status_home,
  } = prediction;

  const getConfidenceClass = () => {
    if (confidence === 'STRONG') return 'confidence-strong';
    if (confidence === 'MODERATE') return 'confidence-moderate';
    return 'confidence-close';
  };

  // Format goalie display: "LastName (+GSAX)"
  const formatGoalie = (name, gsax) => {
    const lastName = name?.split(' ').pop() || 'TBD';
    const gsaxSign = gsax >= 0 ? '+' : '';
    return `${lastName} (${gsaxSign}${gsax?.toFixed(1) || '0.0'})`;
  };

  // Format time for display
  const formatOfficialTime = (isoString) => {
    if (!isoString) return '';
    try {
      const date = new Date(isoString);
      return date.toLocaleTimeString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
      });
    } catch {
      return '';
    }
  };

  return (
    <div className={`game-card ${is_official ? 'official' : 'estimated'}`}>
      {/* Status Banner */}
      {!is_official && (
        <div className="status-banner estimated">
          <span className="status-icon">&#9203;</span>
          <span>Estimated prediction - Official at {formatOfficialTime(official_at)}</span>
        </div>
      )}
      {is_official && (
        <div className="status-banner official">
          <span className="status-icon">&#10003;</span>
          <span>Official prediction (locked)</span>
        </div>
      )}

      <div className="card-body">
        {/* Header */}
        <div className="card-header">
        <h3 className="matchup">{away.team} @ {home.team}</h3>
        <span className={`confidence-badge ${getConfidenceClass()}`}>
          {confidence}
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

      {/* Goalie Section - Display Only (no toggle) */}
      <div className="goalie-box">
        <span className="goalie-title">STARTING GOALIES</span>
        <div className="goalie-lines">
          <div className="goalie-line">
            <span className="goalie-team">{away.team}</span>
            <span className="goalie-name">
              {formatGoalie(away.goalie, away.goalie_gsax)}
              <span className={`confirmation-badge ${goalie_status_away}`}>
                {goalie_status_away === 'confirmed' ? ' ✓' : ' ?'}
              </span>
            </span>
          </div>
          <div className="goalie-line">
            <span className="goalie-team">{home.team}</span>
            <span className="goalie-name">
              {formatGoalie(home.goalie, home.goalie_gsax)}
              <span className={`confirmation-badge ${goalie_status_home}`}>
                {goalie_status_home === 'confirmed' ? ' ✓' : ' ?'}
              </span>
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
    </div>
  );
}

export default GameCard;
