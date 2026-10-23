import './Advanced.css';

/**
 * One team's place on the league's luck curve (web port of the iOS card).
 *
 * PDO is shooting% + save%. It gravitates to 100 over a season, so distance
 * from 100 is the part of a team's results the bounces are likely to take back.
 * The figure shown is sample-adjusted server-side: each team is shrunk toward
 * 100 by how little of them we have seen, so October reads on the same scale
 * as March instead of pegging the dial on three hot weeks.
 *
 * Takes the `luck` pulse from /api/pulse/league, whose rows arrive already
 * ranked luckiest-first — rank and the ends of the scale come straight off
 * that rather than being recomputed here.
 */

function verdict(pdo) {
  if (pdo >= 101.5) return 'Riding hot bounces';
  if (pdo >= 100.75) return 'Running warm';
  if (pdo >= 99.25) return 'Earning its results';
  if (pdo >= 98.5) return 'Running cold';
  return 'Snakebit — due to cash in';
}

function tone(pdo) {
  if (pdo >= 100.75) return 'adv-luck-hot';
  if (pdo <= 99.25) return 'adv-luck-cold';
  return 'adv-luck-even';
}

function LuckMeter({ pulse, abbrev }) {
  if (!pulse || !pulse.active || !Array.isArray(pulse.rows)) return null;

  const values = pulse.rows.map((r) => Number(r.value));
  if (values.some((v) => !Number.isFinite(v))) return null;

  const index = pulse.rows.findIndex(
    (r) => (r.team || '').toUpperCase() === (abbrev || '').toUpperCase(),
  );
  if (index === -1) return null;

  const low = Math.min(...values);
  const high = Math.max(...values);
  // A league collapsed onto one number has no curve to place anybody on.
  if (!(high - low > 0.01)) return null;

  const pdo = values[index];
  const row = pulse.rows[index];
  const pct = ((pdo - low) / (high - low)) * 100;
  const avgPct = 100 >= low && 100 <= high ? ((100 - low) / (high - low)) * 100 : null;

  return (
    <div className="adv-card">
      <div className="adv-card-head">
        <h4>Luck · PDO</h4>
        <span className="adv-rank-pill">#{index + 1} of {pulse.rows.length}</span>
      </div>

      <div className="adv-luck-headline">
        <span className="adv-luck-value">{pdo.toFixed(1)}</span>
        <span className={`adv-luck-verdict ${tone(pdo)}`}>{verdict(pdo)}</span>
      </div>

      <div
        className="adv-luck-track"
        role="img"
        aria-label={`PDO ${pdo.toFixed(1)}, rank ${index + 1} of ${pulse.rows.length}, league average 100`}
      >
        {avgPct !== null && (
          <span className="adv-luck-avg" style={{ left: `${avgPct.toFixed(2)}%` }} />
        )}
        <span
          className={`adv-luck-marker ${tone(pdo)}`}
          style={{ left: `${pct.toFixed(2)}%` }}
        />
      </div>
      <div className="adv-luck-scale">
        <span>{low.toFixed(1)}</span>
        <span>100 · league avg</span>
        <span>{high.toFixed(1)}</span>
      </div>

      {row.detail && <p className="adv-luck-detail">{row.detail}</p>}

      <p className="adv-footnote">
        PDO is shooting% plus save%, and over a season it drifts back toward 100.
        Above it the bounces have been going in; below it, they&rsquo;re owed back.
      </p>
    </div>
  );
}

export default LuckMeter;
