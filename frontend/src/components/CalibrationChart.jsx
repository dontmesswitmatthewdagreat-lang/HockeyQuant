import {
  ComposedChart, Line, Scatter, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, ZAxis,
} from 'recharts';
import './Advanced.css';

/**
 * Reliability diagram (web port of the iOS CalibrationCard).
 *
 * Accuracy says how often the model is right. Calibration asks something
 * stricter: when it says 70%, does that happen 70% of the time? Each point is
 * a probability bucket — predicted on the x axis, what actually happened on
 * the y. The dashed diagonal is perfect calibration; points above it mean the
 * model was too cautious, below means it was overconfident.
 */

/* Declared at module scope: a component created inside render is a new type on
   every pass, so React would remount it and reset its state each time. */
function CalibrationTooltip({ active, payload }) {
  if (!active || !payload || !payload.length) return null;
  const p = payload[0].payload;
  // The ideal-line series has no bucket behind it, so it gets no tooltip.
  if (p.n === undefined) return null;
  return (
    <div className="adv-tooltip">
      <div className="adv-tooltip-head">{p.range} bucket</div>
      <div>Predicted {p.predicted.toFixed(1)}%</div>
      <div>Actual {p.actual.toFixed(1)}%</div>
      <div className="adv-tooltip-sub">{p.n} pick{p.n === 1 ? '' : 's'}</div>
    </div>
  );
}

function CalibrationChart({ data }) {
  if (!data || !Array.isArray(data.buckets) || data.buckets.length === 0) return null;

  const points = data.buckets.map((b) => ({
    predicted: b.mid,
    actual: b.actual_pct,
    n: b.n,
    range: `${b.lo}–${b.hi}%`,
  }));

  const ideal = [{ predicted: 0, actual: 0 }, { predicted: 100, actual: 100 }];

  return (
    <div className="adv-card">
      <div className="adv-card-head">
        <h4>Calibration</h4>
        <span className={`adv-rank-pill ${data.verdict === 'well-calibrated' ? 'adv-pill-good' : ''}`}>
          ±{data.calibration_error}%
        </span>
      </div>
      <p className="adv-note">
        When it says X%, does X% happen? {data.games} graded games, {data.points} probability points.
        Average miss is {data.calibration_error} percentage points — {data.verdict.replace('-', ' ')}.
      </p>

      <ResponsiveContainer width="100%" height={240}>
        <ComposedChart margin={{ top: 8, right: 12, bottom: 20, left: 0 }}>
          <CartesianGrid stroke="var(--border-color)" strokeDasharray="3 3" />
          <XAxis
            type="number"
            dataKey="predicted"
            domain={[0, 100]}
            ticks={[0, 25, 50, 75, 100]}
            tick={{ fill: 'var(--text-muted)', fontSize: 11 }}
            label={{
              value: 'Model said', position: 'insideBottom', offset: -12,
              fill: 'var(--text-muted)', fontSize: 11,
            }}
          />
          <YAxis
            type="number"
            dataKey="actual"
            domain={[0, 100]}
            ticks={[0, 25, 50, 75, 100]}
            tick={{ fill: 'var(--text-muted)', fontSize: 11 }}
            label={{
              value: 'Actually happened', angle: -90, position: 'insideLeft',
              fill: 'var(--text-muted)', fontSize: 11,
            }}
          />
          <ZAxis range={[60, 60]} />
          <Tooltip content={<CalibrationTooltip />} />
          <Line
            data={ideal}
            dataKey="actual"
            stroke="var(--text-muted)"
            strokeDasharray="5 4"
            dot={false}
            activeDot={false}
            isAnimationActive={false}
          />
          <Scatter data={points} fill="var(--accent-red)" />
        </ComposedChart>
      </ResponsiveContainer>

      <p className="adv-footnote">
        Dashed line is perfect calibration. Above it the model was too cautious;
        below it, overconfident.
      </p>
    </div>
  );
}

export default CalibrationChart;
