import { useState, useEffect } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  ReferenceLine,
} from 'recharts';
import { fetchAccuracyTrend } from '../api';
import './AccuracyChart.css';

function AccuracyChart() {
  const [trendData, setTrendData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [windowSize, setWindowSize] = useState(30);

  useEffect(() => {
    loadTrendData();
  }, [windowSize]);

  async function loadTrendData() {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchAccuracyTrend(windowSize);
      setTrendData(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  if (loading) {
    return (
      <div className="chart-container">
        <div className="chart-loading">Loading trend data...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="chart-container">
        <div className="chart-error">Error loading trend: {error}</div>
      </div>
    );
  }

  if (!trendData || trendData.total_games === 0) {
    return (
      <div className="chart-container">
        <div className="chart-no-data">
          <p>No completed predictions yet.</p>
          <p>Check back after games have been played and results updated.</p>
        </div>
      </div>
    );
  }

  // Format data for the chart - show every Nth point if too many
  const dataPoints = trendData.data_points;
  const step = dataPoints.length > 100 ? Math.floor(dataPoints.length / 100) : 1;
  const chartData = dataPoints
    .filter((_, i) => i % step === 0 || i === dataPoints.length - 1)
    .map((point) => ({
      ...point,
      date: point.date.slice(5), // Show MM-DD format
    }));

  // Custom tooltip
  const CustomTooltip = ({ active, payload, label }) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="chart-tooltip">
          <p className="tooltip-date">{data.date}</p>
          <p className="tooltip-rolling">
            Rolling {windowSize}: <strong>{data.rolling_accuracy}%</strong>
            <span className="tooltip-games">({data.games_in_window} games)</span>
          </p>
          <p className="tooltip-cumulative">
            Cumulative: <strong>{data.cumulative_accuracy}%</strong>
            <span className="tooltip-games">({data.cumulative_games} games)</span>
          </p>
        </div>
      );
    }
    return null;
  };

  return (
    <div className="chart-container">
      <div className="chart-header">
        <h2 className="chart-title">Accuracy Trend</h2>
        <div className="window-selector">
          <label>Window:</label>
          <select value={windowSize} onChange={(e) => setWindowSize(Number(e.target.value))}>
            <option value={10}>10 games</option>
            <option value={20}>20 games</option>
            <option value={30}>30 games</option>
            <option value={50}>50 games</option>
          </select>
        </div>
      </div>

      <div className="chart-wrapper">
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={chartData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
            <XAxis
              dataKey="date"
              stroke="#7eb8da"
              tick={{ fill: '#7eb8da', fontSize: 11 }}
              tickLine={{ stroke: '#7eb8da' }}
            />
            <YAxis
              domain={[0, 100]}
              stroke="#7eb8da"
              tick={{ fill: '#7eb8da', fontSize: 11 }}
              tickLine={{ stroke: '#7eb8da' }}
              tickFormatter={(value) => `${value}%`}
            />
            <Tooltip content={<CustomTooltip />} />
            <Legend />
            <ReferenceLine y={50} stroke="#6b7280" strokeDasharray="5 5" label="" />
            <Line
              type="monotone"
              dataKey="rolling_accuracy"
              name={`Rolling ${windowSize}`}
              stroke="#60a5fa"
              strokeWidth={2}
              dot={false}
              activeDot={{ r: 6, fill: '#60a5fa' }}
            />
            <Line
              type="monotone"
              dataKey="cumulative_accuracy"
              name="Cumulative"
              stroke="#4ade80"
              strokeWidth={2}
              dot={false}
              activeDot={{ r: 6, fill: '#4ade80' }}
              strokeDasharray="5 5"
            />
          </LineChart>
        </ResponsiveContainer>
      </div>

      <div className="chart-footer">
        <span className="chart-info">
          Total: {trendData.total_games} games tracked
        </span>
      </div>
    </div>
  );
}

export default AccuracyChart;
