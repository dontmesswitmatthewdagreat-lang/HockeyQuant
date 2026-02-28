import { useEffect } from 'react';
import './CreateModelModal.css';
import './ModelDetailModal.css';

const WEIGHT_CATEGORIES = [
  { key: 'offense', label: 'Offensive Quality' },
  { key: 'defense', label: 'Defensive Quality' },
  { key: 'goaltending', label: 'Goaltending' },
  { key: 'points_pct', label: 'Points Percentage' },
  { key: 'win_rate', label: 'Win Rate' },
];

function ModelDetailModal({ entry, onClose, isOwnModel }) {
  useEffect(() => {
    const handleEscape = (e) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [onClose]);

  const weights = entry.weights || {};
  const hasAccuracy = entry.total_predictions > 0;

  function fmtPct(pct, correct, total) {
    if (pct == null) return null;
    return { pct: pct.toFixed(1) + '%', fraction: `${correct} / ${total}` };
  }

  const accuracyRows = [
    {
      label: 'Overall',
      data: fmtPct(entry.accuracy_pct, entry.correct_predictions, entry.total_predictions),
    },
    {
      label: 'Strong',
      data: fmtPct(entry.strong_pct, entry.strong_correct, entry.strong_total),
    },
    {
      label: 'Moderate',
      data: fmtPct(entry.moderate_pct, entry.moderate_correct, entry.moderate_total),
    },
    {
      label: 'Close',
      data: fmtPct(entry.close_pct, entry.close_correct, entry.close_total),
    },
  ];

  const createdDate = entry.created_at
    ? new Date(entry.created_at).toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      })
    : null;

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content mdm-content" onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div className="mdm-header">
          <div className="mdm-title-row">
            <h2>{entry.model_name}</h2>
            {isOwnModel && <span className="mdm-own-badge">Your Model</span>}
          </div>
          <p className="mdm-creator">
            by {entry.username || 'Anonymous'}
            {createdDate && <span className="mdm-date"> · Created {createdDate}</span>}
          </p>
          {entry.description && (
            <p className="modal-subtitle">{entry.description}</p>
          )}
        </div>

        {/* Weight Distribution */}
        <div className="mdm-section">
          <div className="mdm-section-title">Weight Distribution</div>
          <div className="mdm-weights">
            {WEIGHT_CATEGORIES.map(({ key, label }) => {
              const value = weights[key] ?? 0;
              return (
                <div className="mdm-weight-row" key={key}>
                  <span className="mdm-weight-label">{label}</span>
                  <div className="mdm-weight-bar-container">
                    <div
                      className="mdm-weight-bar-fill"
                      style={{ width: `${value}%` }}
                    />
                  </div>
                  <span className="mdm-weight-value">{value}%</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Accuracy */}
        <div className="mdm-section">
          <div className="mdm-section-title">Accuracy</div>
          {hasAccuracy ? (
            <table className="mdm-accuracy-table">
              <tbody>
                {accuracyRows.map(({ label, data }) => (
                  data ? (
                    <tr key={label}>
                      <td className="mdm-acc-label">{label}</td>
                      <td className="mdm-acc-pct">{data.pct}</td>
                      <td className="mdm-acc-fraction">{data.fraction}</td>
                    </tr>
                  ) : null
                ))}
              </tbody>
            </table>
          ) : (
            <p className="mdm-no-accuracy">No predictions tracked yet.</p>
          )}
        </div>

        {/* Actions */}
        <div className="modal-actions">
          <button className="btn-cancel" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
}

export default ModelDetailModal;
