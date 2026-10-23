import './Dashboard.css';

/**
 * League pulse dial — the web port of the iOS PulseGauge.
 *
 * A single 0-100 read on a league-wide story (luck, playoff race, deadline cap
 * liquidity, playoff upsets) with a five-band arc and a needle. Dormant pulses
 * keep their slot with a note about when they light up rather than vanishing,
 * so the deck doesn't reshuffle itself between visits.
 *
 * The bands are deliberately uneven — 20 / 22 / 16 / 22 / 20 — because the
 * middle band is "normal" and should be narrow enough that sitting in it means
 * something.
 */

const BANDS = [
  { to: 20, color: '#3D8BDD' },
  { to: 42, color: '#2FA6A0' },
  { to: 58, color: '#8E9AA9' },
  { to: 80, color: '#E8842A' },
  { to: 100, color: '#D64545' },
];

const ICON = { luck: '🎲', race: '🏁', deadline: '⇄', playoffs: '🏆' };

const CX = 110;
const CY = 104;
const R = 86;
const STROKE = 16;

/** Score 0-100 → a point on the semicircle, 0 at the left, 100 at the right. */
function pointAt(score) {
  const angle = Math.PI * (1 - score / 100);
  return [CX + R * Math.cos(angle), CY - R * Math.sin(angle)];
}

function arcPath(from, to) {
  const [x1, y1] = pointAt(from);
  const [x2, y2] = pointAt(to);
  // Always the short way round: no band spans more than half the arc.
  return `M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${R} ${R} 0 0 1 ${x2.toFixed(2)} ${y2.toFixed(2)}`;
}

function needleColor(score) {
  return (BANDS.find((b) => score <= b.to) || BANDS[BANDS.length - 1]).color;
}

function PulseDial({ pulse }) {
  if (!pulse) return null;

  if (!pulse.active) {
    return (
      <div className="dash-pulse dash-pulse-dormant">
        <span className="dash-kicker">{pulse.kicker}</span>
        <div className="dash-pulse-icon">{ICON[pulse.id] || '⏳'}</div>
        <p className="dash-pulse-note">{pulse.note || 'Back soon.'}</p>
      </div>
    );
  }

  const score = Math.max(0, Math.min(100, pulse.score ?? 0));
  const [nx, ny] = pointAt(score);
  const tint = needleColor(score);

  return (
    <div className="dash-pulse">
      <span className="dash-kicker">{pulse.kicker}</span>

      <svg className="dash-dial" viewBox="0 0 220 124" role="img"
           aria-label={`${pulse.kicker}: ${score} out of 100, ${pulse.label}`}>
        {BANDS.map((band, i) => (
          <path
            key={band.to}
            d={arcPath(i === 0 ? 0 : BANDS[i - 1].to, band.to)}
            stroke={band.color}
            strokeWidth={STROKE}
            strokeLinecap="butt"
            fill="none"
            opacity={0.85}
          />
        ))}
        {/* Needle drawn as a line to the arc plus a hub, so it reads at any
            angle without needing a rotation transform. */}
        <line x1={CX} y1={CY} x2={nx} y2={ny} stroke={tint} strokeWidth="3" strokeLinecap="round" />
        <circle cx={CX} cy={CY} r="6" fill={tint} />
        <circle cx={CX} cy={CY} r="2.5" fill="var(--bg-card)" />
      </svg>

      <div className="dash-pulse-score" style={{ color: tint }}>{score}</div>
      <div className="dash-pulse-label">{pulse.label}</div>

      {(pulse.sublines || []).length > 0 && (
        <dl className="dash-pulse-sublines">
          {pulse.sublines.map((sub) => (
            <div key={sub.label}>
              <dt>{sub.label}</dt>
              <dd>{sub.value}</dd>
            </div>
          ))}
        </dl>
      )}

      {pulse.note && <p className="dash-pulse-note">{pulse.note}</p>}
    </div>
  );
}

export default PulseDial;
