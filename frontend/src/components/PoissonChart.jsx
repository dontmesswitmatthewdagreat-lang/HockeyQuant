import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';

function poissonPMF(k, lambda) {
  let factorial = 1;
  for (let i = 2; i <= k; i++) factorial *= i;
  return Math.exp(-lambda) * Math.pow(lambda, k) / factorial;
}

function PoissonChart({ awayTeam, homeTeam, awayXG, homeXG }) {
  const data = [0, 1, 2, 3, 4, 5, 6].map((k) => ({
    goals: String(k),
    [awayTeam]: +(poissonPMF(k, awayXG) * 100).toFixed(1),
    [homeTeam]: +(poissonPMF(k, homeXG) * 100).toFixed(1),
  }));

  const CustomTooltip = ({ active, payload, label }) => {
    if (active && payload && payload.length) {
      return (
        <div style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--border-color)',
          borderRadius: '6px',
          padding: '0.375rem 0.625rem',
          fontSize: '0.75rem',
        }}>
          <p style={{ margin: 0, color: 'var(--text-secondary)', marginBottom: '0.25rem' }}>
            {label} goals
          </p>
          {payload.map((entry) => (
            <p key={entry.name} style={{ margin: 0, color: entry.fill, fontWeight: 600 }}>
              {entry.name}: {entry.value}%
            </p>
          ))}
        </div>
      );
    }
    return null;
  };

  return (
    <div className="poisson-chart-wrapper">
      <div className="poisson-header">
        <span className="poisson-title">Goal Distribution</span>
        <div className="poisson-legend">
          <span className="poisson-legend-away">{awayTeam}</span>
          <span className="poisson-legend-home">{homeTeam}</span>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={80}>
        <BarChart
          data={data}
          barGap={1}
          barCategoryGap="18%"
          margin={{ top: 2, right: 4, bottom: 0, left: -28 }}
        >
          <XAxis
            dataKey="goals"
            tick={{ fill: 'var(--text-muted)', fontSize: 10 }}
            tickLine={false}
            axisLine={false}
          />
          <YAxis hide />
          <Tooltip content={<CustomTooltip />} />
          <Bar dataKey={awayTeam} fill="#60a5fa" radius={[2, 2, 0, 0]} />
          <Bar dataKey={homeTeam} fill="#f87171" radius={[2, 2, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

export default PoissonChart;
