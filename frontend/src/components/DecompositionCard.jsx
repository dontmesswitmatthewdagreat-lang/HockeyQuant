import { useState } from 'react';
import './Advanced.css';

/**
 * Goal-differential decomposition — the web port of the iOS card.
 *
 * Every goal of a team's differential is attributed to one of three causes:
 *   process     (xGF - xGA)      — the chances they created and allowed
 *   finishing   (GF - xGF)       — shooters beating their chances
 *   goaltending -(GA - xGA)      — goalies beating theirs
 * Those three sum to GF - GA exactly; it is an algebraic identity, not a fit,
 * which is why `residual` is 0.0000 on every team and strength state.
 *
 * Figures are GOALS and unbounded, not a 0-100 index. The league runs roughly
 * -104..+101 on total differential.
 */

const CAUSES = [
  { key: 'process', label: 'Process', hint: 'chances created vs allowed' },
  { key: 'finishing', label: 'Finishing', hint: 'shooters vs their chances' },
  { key: 'goaltending', label: 'Goaltending', hint: 'goalies vs their chances' },
];

function fmt(value) {
  if (value === null || value === undefined) return '—';
  return `${value > 0 ? '+' : ''}${value.toFixed(1)}`;
}

/** A bar growing left or right from a shared centre line. */
function DivergingBar({ value, scale }) {
  const magnitude = scale > 0 ? Math.min(Math.abs(value) / scale, 1) : 0;
  const positive = value >= 0;
  return (
    <div className="adv-diverge">
      <div className="adv-diverge-track">
        <div
          className={positive ? 'adv-diverge-fill adv-pos' : 'adv-diverge-fill adv-neg'}
          style={{
            width: `${(magnitude * 50).toFixed(2)}%`,
            [positive ? 'left' : 'right']: '50%',
          }}
        />
        <div className="adv-diverge-centre" />
      </div>
    </div>
  );
}

function DecompositionCard({ data }) {
  const [showSplits, setShowSplits] = useState(false);
  if (!data) return null;

  const { differential, goals_for: gf, goals_against: ga, games_played: gp, splits = [] } = data;

  // One scale across all three bars so their lengths are comparable to each
  // other, not just to themselves.
  const scale = Math.max(
    ...CAUSES.map((c) => Math.abs(data[c.key] ?? 0)),
    Math.abs(differential ?? 0),
    1,
  );

  return (
    <div className="adv-card">
      <div className="adv-card-head">
        <h4>Goal differential, broken down</h4>
        <span className="adv-total">{fmt(differential)}</span>
      </div>
      <p className="adv-note">
        {gf?.toFixed(0)} for, {ga?.toFixed(0)} against over {gp} game{gp === 1 ? '' : 's'}.
        The three causes below add up to the differential exactly.
      </p>

      <div className="adv-rows">
        {CAUSES.map((cause) => (
          <div className="adv-row" key={cause.key}>
            <div className="adv-row-label">
              <span className="adv-row-name">{cause.label}</span>
              <span className="adv-row-hint">{cause.hint}</span>
            </div>
            <DivergingBar value={data[cause.key] ?? 0} scale={scale} />
            <span className={`adv-row-value ${(data[cause.key] ?? 0) >= 0 ? 'adv-pos-text' : 'adv-neg-text'}`}>
              {fmt(data[cause.key])}
            </span>
          </div>
        ))}
      </div>

      {splits.length > 0 && (
        <>
          <button
            type="button"
            className="adv-toggle"
            onClick={() => setShowSplits((s) => !s)}
            aria-expanded={showSplits}
          >
            {showSplits ? 'Hide strength states' : 'By strength state'}
          </button>
          {showSplits && (
            <table className="adv-split-table">
              <thead>
                <tr>
                  <th>State</th>
                  <th>Diff</th>
                  <th>Process</th>
                  <th>Finish</th>
                  <th>Goalie</th>
                </tr>
              </thead>
              <tbody>
                {splits.map((s) => (
                  <tr key={s.state}>
                    <td className="adv-split-state">{s.label || s.state}</td>
                    <td className={s.differential >= 0 ? 'adv-pos-text' : 'adv-neg-text'}>
                      {fmt(s.differential)}
                    </td>
                    <td>{fmt(s.process)}</td>
                    <td>{fmt(s.finishing)}</td>
                    <td>{fmt(s.goaltending)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}

      <p className="adv-footnote">
        Figures are goals, not an index. MoneyPuck doesn&rsquo;t credit the
        shootout-winner goal that the NHL standings do, so a team&rsquo;s total
        here can sit a goal or two off its official differential.
      </p>
    </div>
  );
}

export default DecompositionCard;
