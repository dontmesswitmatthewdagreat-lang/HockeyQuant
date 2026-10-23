import { useMemo } from 'react';
import './PoissonGrid.css';

/**
 * Scoreline probability grid (away goals x home goals) — the web port of the
 * iOS PoissonHeatmapView.
 *
 * This is an independent-Poisson *visualization* of the scoreline distribution.
 * The backend predicts with Dixon-Coles, which applies low-score corrections,
 * so this is a faithful approximation of the model's shape rather than the
 * exact server matrix. The marginal bars in PoissonChart answer "how many will
 * each side score?"; this answers "what will the score be?", which is a
 * different question — the joint grid is where a 3-2 separates from a 2-3.
 */

/** Probability of exactly k goals given Poisson mean lambda. */
function pmf(k, lambda) {
  if (!(lambda > 0) || k < 0) return k === 0 ? 1 : 0;
  let result = Math.exp(-lambda);
  for (let i = 1; i <= k; i++) result *= lambda / i;
  return result;
}

function PoissonGrid({
  awayTeam,
  homeTeam,
  awayXG,
  homeXG,
  actualAway = null,
  actualHome = null,
  isFinal = false,
}) {
  const hasActual = actualAway !== null && actualHome !== null;

  // Normally 0-6. A blowout that lands outside that window would otherwise have
  // no cell to mark, so the grid grows just far enough to contain the result.
  const maxGoals = useMemo(() => {
    const m = Math.max(actualAway ?? 0, actualHome ?? 0);
    return Math.min(9, Math.max(6, m + 1));
  }, [actualAway, actualHome]);

  const { matrix, maxProb, peak } = useMemo(() => {
    const m = [];
    let mp = 0;
    let best = { a: 0, h: 0, p: 0 };
    for (let a = 0; a <= maxGoals; a++) {
      const row = [];
      for (let h = 0; h <= maxGoals; h++) {
        const p = pmf(a, awayXG) * pmf(h, homeXG);
        row.push(p);
        if (p > mp) mp = p;
        // The diagonal is a regulation tie. It carries real probability and
        // heats the grid, but it can never be a *final* score, so it is not
        // allowed to be the headline prediction.
        if (a !== h && p > best.p) best = { a, h, p };
      }
      m.push(row);
    }
    return { matrix: m, maxProb: mp, peak: best };
  }, [awayXG, homeXG, maxGoals]);

  if (!(awayXG > 0) || !(homeXG > 0)) return null;

  const counts = Array.from({ length: maxGoals + 1 }, (_, i) => i);

  return (
    <div className="poisson-grid-wrapper">
      <div className="poisson-grid-header">
        {hasActual ? (
          <>
            <div className="poisson-grid-actual">
              <span className={isFinal ? 'pg-chip pg-chip-final' : 'pg-chip pg-chip-live'}>
                {isFinal ? 'Final' : 'Live'}
              </span>
              <strong>
                {awayTeam} {actualAway}–{actualHome} {homeTeam}
              </strong>
            </div>
            <div className="poisson-grid-sub">
              Model&rsquo;s most likely was {awayTeam} {peak.a}–{peak.h} {homeTeam}
            </div>
          </>
        ) : (
          <div className="poisson-grid-sub">
            Most likely{' '}
            <strong>
              {awayTeam} {peak.a}–{peak.h} {homeTeam}
            </strong>{' '}
            · {Math.round(peak.p * 100)}%
          </div>
        )}
      </div>

      <div className="poisson-grid-axes">
        <span>↓ {homeTeam} goals</span>
        <span>{awayTeam} goals →</span>
      </div>

      <table className="poisson-grid" role="presentation">
        <tbody>
          <tr>
            <td className="pg-corner" />
            {counts.map((a) => (
              <td key={`top-${a}`} className="pg-axis">{a}</td>
            ))}
          </tr>
          {counts.map((h) => (
            <tr key={`row-${h}`}>
              <td className="pg-axis">{h}</td>
              {counts.map((a) => {
                const prob = matrix[a][h];
                const intensity = maxProb > 0 ? prob / maxProb : 0;
                const isPeak = a === peak.a && h === peak.h;
                const isActual = hasActual && a === actualAway && h === actualHome;
                const cls = [
                  'pg-cell',
                  isPeak ? 'pg-peak' : '',
                  isActual ? 'pg-actual' : '',
                ].filter(Boolean).join(' ');
                return (
                  <td
                    key={`${a}-${h}`}
                    className={cls}
                    // Every cell is tinted, so the peak reads as the darkest
                    // square rather than the only coloured one.
                    style={{ '--pg-intensity': (0.08 + 0.85 * intensity).toFixed(3) }}
                    title={`${awayTeam} ${a}–${h} ${homeTeam}: ${(prob * 100).toFixed(1)}%`}
                    aria-label={`${awayTeam} ${a}, ${homeTeam} ${h}: ${Math.round(prob * 100)} percent`}
                  >
                    <span className="pg-cell-inner" />
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>

      <div className="poisson-grid-legend">
        <span className="pg-legend-item">
          <span className="pg-swatch pg-swatch-peak" /> model&rsquo;s most likely
        </span>
        {hasActual && (
          <span className="pg-legend-item">
            <span className="pg-swatch pg-swatch-actual" /> {isFinal ? 'actual final' : 'live score'}
          </span>
        )}
      </div>
    </div>
  );
}

export default PoissonGrid;
