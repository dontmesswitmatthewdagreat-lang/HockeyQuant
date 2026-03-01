import { useState } from 'react';
import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import { fetchGameSummary } from '../api';
import PoissonChart from './PoissonChart';
import './GameCard.css';

function GameCard({ prediction, liveScore }) {
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

  // Live / final score helpers
  const isLive = liveScore && (liveScore.game_state === 'LIVE' || liveScore.game_state === 'CRIT');
  const isFinal = liveScore && (liveScore.game_state === 'FINAL' || liveScore.game_state === 'OFF');
  const hasScore = isLive || isFinal;

  // ML pick correctness (null until final, null if tied)
  let pickCorrect = null;
  if (isFinal && liveScore.away_score !== liveScore.home_score) {
    const actualWinner = liveScore.home_score > liveScore.away_score ? home.team : away.team;
    pickCorrect = pick === actualWinner;
  }

  // Period label for live games
  function getPeriodLabel() {
    if (!liveScore) return '';
    if (liveScore.in_intermission) return 'INT';
    const n = liveScore.period;
    if (!n) return '';
    if (liveScore.period_type === 'OT') return 'OT';
    if (liveScore.period_type === 'SO') return 'SO';
    return n === 1 ? '1st' : n === 2 ? '2nd' : n === 3 ? '3rd' : `${n}th`;
  }

  // Puck line and O/U results (computed from actual score when final)
  let plCorrect = null;
  let ouCorrect = null;
  if (isFinal && betting_lines) {
    const margin = liveScore.home_score - liveScore.away_score;
    plCorrect = (margin + betting_lines.puck_line) > 0;
    const total = liveScore.home_score + liveScore.away_score;
    if (total !== betting_lines.over_under) {
      ouCorrect = total > betting_lines.over_under;
    }
  }

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

      {/* Score Bar — shown during live play and after games finish */}
      {hasScore && (
        <div className={`score-bar ${isFinal ? 'score-bar--final' : 'score-bar--live'}`}>
          <div className="score-bar-left">
            {isLive ? (
              <span className="score-live-badge">
                <span className="live-pulse" />
                LIVE{getPeriodLabel() ? ` · ${getPeriodLabel()}` : ''}
                {liveScore.time_remaining && !liveScore.in_intermission
                  ? ` · ${liveScore.time_remaining}` : ''}
              </span>
            ) : (
              <span className="score-final-label">FINAL</span>
            )}
          </div>
          <div className="score-bar-center">
            <span className={liveScore.away_score > liveScore.home_score ? 'score-num score-leading' : 'score-num'}>
              {liveScore.away_score}
            </span>
            <span className="score-separator">–</span>
            <span className={liveScore.home_score > liveScore.away_score ? 'score-num score-leading' : 'score-num'}>
              {liveScore.home_score}
            </span>
          </div>
          <div className="score-bar-right">
            {isFinal && pickCorrect !== null && (
              <span className={`pick-result-badge ${pickCorrect ? 'pick-correct' : 'pick-wrong'}`}>
                {pickCorrect ? '✓ Correct' : '✗ Wrong'}
              </span>
            )}
          </div>
        </div>
      )}

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
                {awayGoalieStatus === 'confirmed'
                  ? `✓ ${away.goalie || 'Goalie Confirmed'}`
                  : `? ${away.goalie || 'Goalie Expected'}`}
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
                {homeGoalieStatus === 'confirmed'
                  ? `✓ ${home.goalie || 'Goalie Confirmed'}`
                  : `? ${home.goalie || 'Goalie Expected'}`}
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
              {isFinal && plCorrect !== null && (
                <span className={`bet-result-inline ${plCorrect ? 'bet-correct' : 'bet-wrong'}`}>
                  {plCorrect ? '✓ Covered' : '✗ No cover'}
                </span>
              )}
              <div className="optimal-line">
                <span className="optimal-label">Optimal</span>
                <span className="optimal-value">
                  {betting_lines.optimal_spread_side === 'home' ? home.team : away.team}{' '}
                  {betting_lines.optimal_spread > 0 ? '+' : ''}{betting_lines.optimal_spread}
                  {' '}({betting_lines.optimal_spread_prob}%)
                </span>
              </div>
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
              {isFinal && ouCorrect !== null && (
                <span className={`bet-result-inline ${ouCorrect ? 'bet-correct' : 'bet-wrong'}`}>
                  {(() => {
                    const total = liveScore.home_score + liveScore.away_score;
                    const hit = total > betting_lines.over_under ? 'Over' : 'Under';
                    return `${ouCorrect ? '✓' : '✗'} ${total} total · ${hit} hit`;
                  })()}
                </span>
              )}
              <div className="optimal-line">
                <span className="optimal-label">Optimal</span>
                <span className="optimal-value">
                  {betting_lines.optimal_total_rec} {betting_lines.optimal_total}
                  {' '}({betting_lines.optimal_total_prob}%)
                </span>
              </div>
            </div>
          </div>
          {betting_lines.away_expected_goals != null && betting_lines.home_expected_goals != null && (
            <PoissonChart
              awayTeam={away.team}
              homeTeam={home.team}
              awayXG={betting_lines.away_expected_goals}
              homeXG={betting_lines.home_expected_goals}
            />
          )}
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
