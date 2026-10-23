import { useEffect, useState } from 'react';
import { fetchAdvancedPlayer, fetchAdvancedGoalie } from '../api';
import './Advanced.css';

/**
 * A skater's or goalie's impact card (web port of the iOS PlayerImpactSheet /
 * GoalieImpactSheet).
 *
 * Percentiles are ranked within position group and only attach above the
 * ice-time floor — 300 minutes for skaters, 500 for goalies — which ranks
 * about 73% of the league and keeps a player with two good nights off the
 * top of the charts. Below the floor the raw numbers still show; the bars
 * just don't, because a percentile there would be a lie.
 */

// `higherBetter: false` inverts nothing in the bar itself — the server already
// ranked it — it only picks the wording.
const SKATER_METRICS = [
  { key: 'game_score_per60', label: 'Game Score / 60', digits: 2 },
  { key: 'xgf_per60', label: 'xGF / 60', digits: 2 },
  { key: 'xga_per60', label: 'xGA / 60', digits: 2, higherBetter: false },
  { key: 'xgf_pct_rel', label: 'xGF% rel', digits: 1, suffix: '%', signed: true },
  { key: 'finishing', label: 'Finishing', digits: 1, signed: true, unit: 'goals' },
  { key: 'penalty_differential', label: 'Penalty differential', digits: 0, signed: true },
];

const GOALIE_METRICS = [
  { key: 'gsax', label: 'GSAx', digits: 2, signed: true, unit: 'goals' },
  { key: 'gsax_per60', label: 'GSAx / 60', digits: 3, signed: true },
  { key: 'save_pct', label: 'Save%', digits: 2, suffix: '%' },
  { key: 'hd_save_pct', label: 'High-danger save%', digits: 2, suffix: '%' },
  { key: 'hd_gsax', label: 'High-danger GSAx', digits: 2, signed: true, unit: 'goals' },
  // MoneyPuck's xRebounds is not calibrated against actual rebounds the way
  // xGoals is against goals — it runs negative for 71 of 72 qualified goalies.
  // The ordering is meaningful, the number is not, so only the rank is shown.
  { key: 'rebound_control', label: 'Rebound control', rankOnly: true },
];

function formatValue(value, metric) {
  if (value === null || value === undefined) return '—';
  const s = Number(value).toFixed(metric.digits ?? 1);
  const signed = metric.signed && value > 0 ? `+${s}` : s;
  return `${signed}${metric.suffix || ''}`;
}

function ordinal(n) {
  const rem100 = n % 100;
  if (rem100 >= 11 && rem100 <= 13) return `${n}th`;
  switch (n % 10) {
    case 1: return `${n}st`;
    case 2: return `${n}nd`;
    case 3: return `${n}rd`;
    default: return `${n}th`;
  }
}

function PercentileRow({ metric, value, percentile }) {
  const ranked = percentile !== null && percentile !== undefined;
  const tone = !ranked ? '' : percentile >= 75 ? 'adv-pct-high' : percentile <= 25 ? 'adv-pct-low' : '';
  return (
    <div className="adv-pct-row">
      <div className="adv-pct-head">
        <span className="adv-pct-label">{metric.label}</span>
        <span className="adv-pct-value">
          {metric.rankOnly ? (ranked ? '' : 'unranked') : formatValue(value, metric)}
          {metric.unit && !metric.rankOnly && value !== null && value !== undefined && (
            <span className="adv-pct-unit"> {metric.unit}</span>
          )}
        </span>
      </div>
      {ranked ? (
        <>
          <div className="adv-pct-track">
            <span className="adv-pct-mid" />
            <span className={`adv-pct-fill ${tone}`} style={{ width: `${percentile}%` }} />
          </div>
          <span className="adv-pct-rank">{ordinal(percentile)} percentile</span>
        </>
      ) : (
        <span className="adv-pct-rank adv-pct-unranked">below the ice-time floor — not ranked</span>
      )}
    </div>
  );
}

function PlayerImpactModal({ playerId, isGoalie, onClose }) {
  const [card, setCard] = useState(null);
  const [error, setError] = useState(null);

  // No reset here on purpose: the parent keys this component by player id, so
  // picking a different player remounts it with fresh state. Clearing state
  // synchronously inside the effect instead would cascade an extra render.
  useEffect(() => {
    let cancelled = false;
    const load = isGoalie ? fetchAdvancedGoalie : fetchAdvancedPlayer;
    load(playerId)
      .then((d) => { if (!cancelled) setCard(d); })
      .catch(() => { if (!cancelled) setError('Could not load this card.'); });
    return () => { cancelled = true; };
  }, [playerId, isGoalie]);

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const metrics = isGoalie ? GOALIE_METRICS : SKATER_METRICS;
  const percentiles = card?.percentiles || {};
  const ranked = Object.keys(percentiles).length > 0;

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content adv-player-modal" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="adv-close" onClick={onClose} aria-label="Close">×</button>

        {error && <p className="adv-note">{error}</p>}
        {!card && !error && <p className="adv-note">Loading…</p>}

        {card && (
          <>
            <div className="adv-player-head">
              <h3>{card.name}</h3>
              <span className="adv-player-meta">
                {card.team} · {card.position} · {card.games_played} GP ·{' '}
                {card.toi_per_game ? `${card.toi_per_game.toFixed(1)} min/gm` : '—'}
              </span>
            </div>

            {!isGoalie && (
              <div className="adv-player-line">
                <span><strong>{card.points ?? '—'}</strong> P</span>
                <span><strong>{card.goals ?? '—'}</strong> G</span>
                <span>
                  <strong>{(card.primary_assists ?? 0) + (card.secondary_assists ?? 0)}</strong> A
                </span>
                <span><strong>{card.game_score?.toFixed(1) ?? '—'}</strong> GS</span>
              </div>
            )}
            {isGoalie && (
              <div className="adv-player-line">
                <span><strong>{card.shots_against ?? '—'}</strong> SA</span>
                <span><strong>{card.goals_against ?? '—'}</strong> GA</span>
                <span><strong>{card.workload_per60?.toFixed(1) ?? '—'}</strong> shots/60</span>
              </div>
            )}

            <div className="adv-pct-legend">
              <span>0</span><span>50 avg</span><span>100</span>
            </div>

            {metrics.map((m) => (
              <PercentileRow
                key={m.key}
                metric={m}
                value={card[m.key]}
                percentile={percentiles[m.key]}
              />
            ))}

            <p className="adv-footnote">
              {ranked
                ? `Percentiles rank ${card.name.split(' ').slice(-1)[0]} against the rest of the league in the same position group.`
                : `Percentiles appear once a player clears ${isGoalie ? '500' : '300'} minutes — early in a season the rate stats are still noise.`}
              {isGoalie && ' Rebound control is shown as a rank only: the underlying xRebounds figure is not calibrated the way xGoals is.'}
            </p>
          </>
        )}
      </div>
    </div>
  );
}

export default PlayerImpactModal;
