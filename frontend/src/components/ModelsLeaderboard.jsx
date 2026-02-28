import { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { fetchPublicModelsLeaderboard } from '../api';
import './ModelsLeaderboard.css';

function ModelsLeaderboard({ selectedEntry, onSelectEntry }) {
  const { user } = useAuth();
  const [leaderboard, setLeaderboard] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    async function load() {
      setLoading(true);
      setError(null);
      try {
        const data = await fetchPublicModelsLeaderboard();
        setLeaderboard(data);
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    load();
  }, []);

  function handleRowClick(entry) {
    onSelectEntry(selectedEntry?.model_id === entry.model_id ? null : entry);
  }

  // Color coding: top third = green, bottom third = red
  function getPctClass(pct, allPcts) {
    if (pct == null || allPcts.length < 3) return '';
    const sorted = [...allPcts].sort((a, b) => a - b);
    const low = sorted[Math.floor(sorted.length / 3)];
    const high = sorted[Math.floor((sorted.length * 2) / 3)];
    if (pct >= high) return 'best';
    if (pct <= low) return 'worst';
    return '';
  }

  const allPcts = leaderboard
    .map((e) => e.accuracy_pct)
    .filter((p) => p != null);

  function formatDate(iso) {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  }

  if (loading) {
    return <p className="models-lb-loading">Loading leaderboard...</p>;
  }

  if (error) {
    return <p className="models-lb-error">Error loading leaderboard: {error}</p>;
  }

  if (leaderboard.length === 0) {
    return (
      <div className="models-lb-empty">
        No models have been created yet. Create one to appear on the leaderboard!
      </div>
    );
  }

  return (
    <div className="models-lb-table-container">
      <table className="models-lb-table">
        <thead>
          <tr>
            <th className="models-lb-rank-th">#</th>
            <th>Creator</th>
            <th>Model Name</th>
            <th className="models-lb-num-th">Accuracy</th>
            <th className="models-lb-num-th">Correct / Total</th>
            <th className="models-lb-num-th">Strong %</th>
            <th className="models-lb-num-th">Created</th>
          </tr>
        </thead>
        <tbody>
          {leaderboard.map((entry, idx) => {
            const isOwn = user && entry.user_id === user.id;
            const isSelected = selectedEntry?.model_id === entry.model_id;
            const pctClass = getPctClass(entry.accuracy_pct, allPcts);
            let rowClass = 'models-lb-row';
            if (isOwn) rowClass += ' own-row';
            if (isSelected) rowClass += ' selected';

            return (
              <tr
                key={entry.model_id}
                className={rowClass}
                onClick={() => handleRowClick(entry)}
              >
                <td className="models-lb-rank">{idx + 1}</td>
                <td className="models-lb-creator">
                  {entry.username || 'Anonymous'}
                  {isOwn && <span className="models-lb-you-badge">You</span>}
                </td>
                <td className="models-lb-name">{entry.model_name}</td>
                <td className="models-lb-num-cell">
                  {entry.accuracy_pct != null ? (
                    <span className={`models-lb-pct ${pctClass}`}>
                      {entry.accuracy_pct.toFixed(1)}%
                    </span>
                  ) : (
                    <span className="models-lb-dash">—</span>
                  )}
                </td>
                <td className="models-lb-num-cell">
                  {entry.total_predictions > 0 ? (
                    <span className="models-lb-sub" style={{ fontSize: '0.875rem', color: 'var(--text-primary)' }}>
                      {entry.correct_predictions} / {entry.total_predictions}
                    </span>
                  ) : (
                    <span className="models-lb-dash">—</span>
                  )}
                </td>
                <td className="models-lb-num-cell">
                  {entry.strong_pct != null ? (
                    <>
                      <span className="models-lb-pct">{entry.strong_pct.toFixed(1)}%</span>
                      <span className="models-lb-sub">{entry.strong_correct}/{entry.strong_total}</span>
                    </>
                  ) : (
                    <span className="models-lb-dash">—</span>
                  )}
                </td>
                <td className="models-lb-num-cell" style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>
                  {formatDate(entry.created_at)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export default ModelsLeaderboard;
