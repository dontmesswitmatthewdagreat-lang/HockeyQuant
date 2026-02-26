import { useState } from 'react';
import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import { fetchGameSummary } from '../api';
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
    betting_lines,
  } = prediction;

  const [showSummary, setShowSummary] = useState(false);
  const [summary, setSummary] = useState(null);
  const [summaryLoading, setSummaryLoading] = useState(false);

  const handleWhyClick = async () => {
    if (!showSummary && summary === null) {
      setSummaryLoading(true);
      try {
        const data = await fetchGameSummary(prediction);
        setSummary(data.summary);
      } catch {
        setSummary('Unable to generate summary at this time.');
      } finally {
        setSummaryLoading(false);
      }
    }
    setShowSummary(prev => !prev);
  };

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
  const confidenceLevel = (confidence || 'CLOSE').toLowerCase();

  // Once a game has started, goalies are definitionally confirmed (they're playing).
  // Daily Faceoff removes "Confirmed" text after puck drop, so the scraper always
  // returns "expected" for in-progress or finished games.
  const gameStarted = game_time ? Date.now() >= new Date(game_time).getTime() : false;
  const awayGoalieStatus = gameStarted ? 'confirmed' : (goalie_status_away === 'confirmed' ? 'confirmed' : 'expected');
  const homeGoalieStatus = gameStarted ? 'confirmed' : (goalie_status_home === 'confirmed' ? 'confirmed' : 'expected');

  // Determine if a team is the predicted winner
  const awayIsWinner = pick === away.team;
  const homeIsWinner = pick === home.team;

  // Check if team is hot (streak multiplier > 1.02)
  const awayIsHot = away.streak_mult > 1.02;
  const homeIsHot = home.streak_mult > 1.02;

  // Format team record from stats if available
  const formatRecord = (team) => {
    if (team.streak && team.streak.includes('L10')) {
      return team.streak.split(' ')[0];
    }
    return '';
  };

  return (
    <div className={`game-card ${is_official ? 'official' : ''}`}>
      {/* Confidence Banner */}
      <div className={`confidence-banner ${confidenceLevel}`}>
        <span className="confidence-label">{confidence || 'CLOSE'}</span>
        <span className="confidence-diff">
          {diff ? `${diff.toFixed(1)} pt spread` : ''}
        </span>
      </div>

      {/* Game Time Header */}
      <div className="game-time-header">
        <span className="game-time">{formatGameTime(game_time)}</span>
        <div className="game-badges">
          {is_official && (
            <span className="live-badge">OFFICIAL</span>
          )}
        </div>
      </div>

      {/* Teams Section */}
      <div className="teams-section">
        {/* Away Team */}
        <div className={`team-row ${awayIsWinner ? 'winner' : 'loser'}`}>
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
              <span className={`goalie-status-badge ${awayGoalieStatus}`}>
                {awayGoalieStatus === 'confirmed' ? '✓ Goalie Confirmed' : '? Goalie Expected'}
              </span>
            </div>
          </div>
          <span className="winner-label">{awayIsWinner ? 'Predicted Winner' : ''}</span>
          <div className="team-score-section">
            {awayIsWinner && (
              <span className="win-prob-badge">{winProb}%</span>
            )}
            <span className="team-score">{Math.round(away.final_score)}</span>
          </div>
        </div>

        {/* Home Team */}
        <div className={`team-row ${homeIsWinner ? 'winner' : 'loser'}`}>
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
              <span className={`goalie-status-badge ${homeGoalieStatus}`}>
                {homeGoalieStatus === 'confirmed' ? '✓ Goalie Confirmed' : '? Goalie Expected'}
              </span>
            </div>
          </div>
          <span className="winner-label">{homeIsWinner ? 'Predicted Winner' : ''}</span>
          <div className="team-score-section">
            {homeIsWinner && (
              <span className="win-prob-badge">{winProb}%</span>
            )}
            <span className="team-score">{Math.round(home.final_score)}</span>
          </div>
        </div>
      </div>

      {/* Betting Lines */}
      {betting_lines && (
        <div className="betting-lines-section">
          <div className="betting-lines-header">
            <span>Betting Lines</span>
            <span className="betting-source">
              {betting_lines.puck_line_source !== 'Standard' && betting_lines.puck_line_source !== 'Model'
                ? `via ${betting_lines.puck_line_source}`
                : 'Model Estimated'}
            </span>
          </div>

          <div className="betting-lines-grid">
            {/* Expected Goals */}
            <div className="betting-line-row expected-goals-row">
              <span className="betting-label">Expected Goals</span>
              <div className="expected-goals-display">
                <span className="xg-team">{away.team} {betting_lines.away_expected_goals.toFixed(1)}</span>
                <span className="xg-separator">|</span>
                <span className="xg-team">{home.team} {betting_lines.home_expected_goals.toFixed(1)}</span>
              </div>
            </div>

            {/* Puck Line */}
            <div className="betting-line-row">
              <div className="betting-line-main">
                <span className="betting-label">Puck Line</span>
                <span className="betting-value">
                  {home.team} {betting_lines.puck_line > 0 ? '+' : ''}{betting_lines.puck_line}
                </span>
              </div>
              <div className="betting-probs">
                <span className={`prob-badge ${betting_lines.puck_line_home_cover_prob > 50 ? 'favorable' : ''}`}>
                  {home.team} {betting_lines.puck_line_home_cover_prob}%
                </span>
                <span className={`prob-badge ${betting_lines.puck_line_away_cover_prob > 50 ? 'favorable' : ''}`}>
                  {away.team} {betting_lines.puck_line_away_cover_prob}%
                </span>
              </div>
              {betting_lines.optimal_spread !== betting_lines.puck_line && (
                <div className="optimal-line">
                  <span className="optimal-label">Optimal</span>
                  <span className="optimal-value">
                    {betting_lines.optimal_spread_side === 'home' ? home.team : away.team}{' '}
                    {betting_lines.optimal_spread > 0 ? '+' : ''}{betting_lines.optimal_spread}
                    {' '}({betting_lines.optimal_spread_prob}%)
                  </span>
                </div>
              )}
            </div>

            {/* Over/Under */}
            <div className="betting-line-row">
              <div className="betting-line-main">
                <span className="betting-label">Over/Under</span>
                <span className="betting-value">{betting_lines.over_under}</span>
              </div>
              <div className="betting-probs">
                <span className={`prob-badge ${betting_lines.over_prob > 50 ? 'favorable' : ''}`}>
                  OVER {betting_lines.over_prob}%
                </span>
                <span className={`prob-badge ${betting_lines.under_prob > 50 ? 'favorable' : ''}`}>
                  UNDER {betting_lines.under_prob}%
                </span>
              </div>
              {betting_lines.optimal_total !== betting_lines.over_under && (
                <div className="optimal-line">
                  <span className="optimal-label">Optimal</span>
                  <span className="optimal-value">
                    {betting_lines.optimal_total_rec} {betting_lines.optimal_total}
                    {' '}({betting_lines.optimal_total_prob}%)
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Key Factors */}
      <div className="key-factors-section">
        <div className="factors-header">
          <span>Key Factors</span>
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
            </>
          )}
        </div>
      </div>

      {/* Why? AI Explanation */}
      <div className="summary-section-wrapper">
        <button className="summary-btn" onClick={handleWhyClick}>
          <span>Why {pick}?</span>
          <svg
            className={`summary-chevron ${showSummary ? 'open' : ''}`}
            viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"
          >
            <polyline points="6 9 12 15 18 9"></polyline>
          </svg>
        </button>
        {showSummary && (
          <div className="summary-content">
            {summaryLoading ? (
              <p className="summary-loading">Generating explanation...</p>
            ) : (
              <p className="summary-text">{summary}</p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

export default GameCard;
