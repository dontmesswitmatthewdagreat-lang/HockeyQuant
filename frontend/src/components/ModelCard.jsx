import './ModelCard.css';

function ModelCard({ model, onEdit, onDelete }) {
  const { name, description, weights, accuracy, created_at } = model;

  // Format date
  const createdDate = new Date(created_at).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  });

  // Weight categories with labels
  const weightCategories = [
    { key: 'offense', label: 'Offense', value: weights?.offense || 0 },
    { key: 'defense', label: 'Defense', value: weights?.defense || 0 },
    { key: 'goaltending', label: 'Goaltending', value: weights?.goaltending || 0 },
    { key: 'points_pct', label: 'Points %', value: weights?.points_pct || 0 },
    { key: 'win_rate', label: 'Win Rate', value: weights?.win_rate || 0 },
  ];

  return (
    <div className="model-card">
      <div className="model-card-header">
        <h3 className="model-name">{name}</h3>
        <div className="model-actions">
          <button className="action-btn edit-btn" onClick={onEdit} title="Edit model">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
              <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
            </svg>
          </button>
          <button className="action-btn delete-btn" onClick={onDelete} title="Delete model">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <polyline points="3 6 5 6 21 6"></polyline>
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
            </svg>
          </button>
        </div>
      </div>

      {description && (
        <p className="model-description">{description}</p>
      )}

      {/* Accuracy Stats */}
      <div className="model-stats">
        <div className="stat-item">
          <span className="stat-number">{accuracy?.accuracy_pct?.toFixed(1) || '0.0'}%</span>
          <span className="stat-name">Accuracy</span>
        </div>
        <div className="stat-item">
          <span className="stat-number">{accuracy?.correct_predictions || 0}</span>
          <span className="stat-name">Correct</span>
        </div>
        <div className="stat-item">
          <span className="stat-number">{accuracy?.total_predictions || 0}</span>
          <span className="stat-name">Total</span>
        </div>
      </div>

      {/* Weight Distribution */}
      <div className="model-weights">
        <div className="weights-header">
          <span>Weight Distribution</span>
          <span>100%</span>
        </div>
        {weightCategories.map(({ key, label, value }) => (
          <div className="weight-row" key={key}>
            <span className="weight-label">{label}</span>
            <div className="weight-bar-container">
              <div
                className="weight-bar-fill"
                style={{ width: `${value}%` }}
              ></div>
            </div>
            <span className="weight-value">{value}%</span>
          </div>
        ))}
      </div>

      <div className="model-footer">
        <span className="created-date">Created {createdDate}</span>
      </div>
    </div>
  );
}

export default ModelCard;
