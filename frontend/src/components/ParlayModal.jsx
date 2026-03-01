import { useState, useEffect } from 'react';
import { fetchDailyParlay } from '../api';
import './ParlayModal.css';

function formatDateDisplay(dateStr) {
  const d = new Date(dateStr + 'T12:00:00');
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

function formatGameTime(isoStr) {
  if (!isoStr) return '';
  try {
    const d = new Date(isoStr);
    return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZoneName: 'short', timeZone: 'America/New_York' });
  } catch {
    return '';
  }
}

function ProbBar({ prob }) {
  const cls = prob >= 65 ? 'prob-high' : prob >= 58 ? 'prob-mid' : 'prob-low';
  return (
    <div className="parlay-prob-bar-wrapper">
      <div className={`parlay-prob-bar ${cls}`} style={{ width: `${Math.min(prob, 100)}%` }} />
    </div>
  );
}

function ParlayModal({ date, onClose }) {
  const [parlay, setParlay] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setLoading(true);
      setError(null);
      try {
        const data = await fetchDailyParlay(date);
        if (!cancelled) setParlay(data);
      } catch (err) {
        if (!cancelled) setError(err.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    load();
    return () => { cancelled = true; };
  }, [date]);

  useEffect(() => {
    function handleKey(e) {
      if (e.key === 'Escape') onClose();
    }
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [onClose]);

  const legs = parlay?.legs || [];
  const numLegs = parlay?.num_legs || 0;
  const combinedProb = parlay?.combined_prob || 0;

  const typeLabel = { ML: 'Moneyline', PL: 'Puck Line', OU: 'Over/Under' };

  return (
    <div className="parlay-overlay" onClick={onClose}>
      <div className="parlay-modal" onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div className="parlay-header">
          <div className="parlay-header-info">
            <h2 className="parlay-title">Daily Optimal Parlay</h2>
            {!loading && !error && parlay && (
              <p className="parlay-subtitle">
                {formatDateDisplay(date)}
                {numLegs > 0 && (
                  <> &middot; {numLegs} {numLegs === 1 ? 'leg' : 'legs'} &middot; ~{combinedProb}% to hit</>
                )}
              </p>
            )}
          </div>
          <button className="parlay-close-btn" onClick={onClose} aria-label="Close">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>

        {/* Body */}
        <div className="parlay-body">
          {loading && (
            <div className="parlay-loading">
              <div className="parlay-spinner" />
              <p>Building optimal parlay...</p>
            </div>
          )}

          {error && (
            <div className="parlay-error">
              <p>Failed to load parlay: {error}</p>
            </div>
          )}

          {!loading && !error && legs.length === 0 && (
            <div className="parlay-empty">
              <p>No games scheduled today — check back tomorrow.</p>
            </div>
          )}

          {!loading && !error && legs.length > 0 && (
            <>
              <div className="parlay-legs">
                {legs.map((leg, idx) => (
                  <div key={idx} className="parlay-leg">
                    <div className="leg-number">{idx + 1}</div>
                    <div className="leg-content">
                      <div className="leg-top">
                        <span className="leg-label">{leg.label}</span>
                        <span className={`leg-type-badge type-${leg.type?.toLowerCase()}`}>
                          {typeLabel[leg.type] || leg.type}
                        </span>
                        <span className="leg-prob">{leg.prob?.toFixed(1)}%</span>
                      </div>
                      <ProbBar prob={leg.prob || 0} />
                      <div className="leg-matchup">
                        {leg.away_team} @ {leg.home_team}
                        {leg.game_time && (
                          <span className="leg-time"> &middot; {formatGameTime(leg.game_time)}</span>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>

              {/* Combined probability */}
              <div className="parlay-combined">
                <div className="combined-label">Combined probability</div>
                <div className="combined-bar-row">
                  <div className="combined-bar-wrapper">
                    <div
                      className="combined-bar"
                      style={{ width: `${Math.min(combinedProb * 3, 100)}%` }}
                    />
                  </div>
                  <span className="combined-pct">{combinedProb}%</span>
                </div>
              </div>
            </>
          )}

          {/* Info note */}
          {!loading && !error && (
            <div className="parlay-info">
              <span className="info-icon">&#9432;</span>
              Optimizer selects the highest-probability bet per game (ML / Puck Line / O&amp;U)
              and includes all qualifying legs sorted by confidence — up to 8 legs.
              Min. per-leg threshold: 52%.
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="parlay-footer">
          <button className="parlay-close-footer-btn" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
}

export default ParlayModal;
