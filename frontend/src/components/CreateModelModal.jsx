import { useState, useEffect } from 'react';
import { createModel, updateModel } from '../api';
import './CreateModelModal.css';

const DEFAULT_WEIGHTS = {
  offense: 40,
  defense: 15,
  goaltending: 30,
  points_pct: 10,
  win_rate: 5,
};

const WEIGHT_CATEGORIES = [
  {
    key: 'offense',
    label: 'Offensive Quality',
    description: 'Expected goals, shots, scoring chances',
  },
  {
    key: 'defense',
    label: 'Defensive Quality',
    description: 'Goals against, shot suppression',
  },
  {
    key: 'goaltending',
    label: 'Goaltending',
    description: 'GSAX, save %, GAA',
  },
  {
    key: 'points_pct',
    label: 'Points Percentage',
    description: 'Season record and standings',
  },
  {
    key: 'win_rate',
    label: 'Win Rate',
    description: 'Recent win percentage',
  },
];

function CreateModelModal({ model, token, onClose, onSaved }) {
  const isEditing = !!model;

  const [name, setName] = useState(model?.name || '');
  const [description, setDescription] = useState(model?.description || '');
  const [weights, setWeights] = useState(model?.weights || { ...DEFAULT_WEIGHTS });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  // Calculate total weight
  const totalWeight = Object.values(weights).reduce((sum, val) => sum + val, 0);
  const isValid = Math.abs(totalWeight - 100) < 0.01 && name.trim().length > 0;

  const handleWeightChange = (key, value) => {
    const numValue = Math.max(0, Math.min(100, parseInt(value) || 0));
    setWeights(prev => ({ ...prev, [key]: numValue }));
  };

  const handleSliderChange = (key, value) => {
    setWeights(prev => ({ ...prev, [key]: parseInt(value) }));
  };

  const handleReset = () => {
    setWeights({ ...DEFAULT_WEIGHTS });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!isValid) {
      setError('Weights must sum to exactly 100%');
      return;
    }

    try {
      setSaving(true);
      setError(null);

      const modelData = {
        name: name.trim(),
        description: description.trim() || null,
        weights,
      };

      if (isEditing) {
        await updateModel(token, model.id, modelData);
      } else {
        await createModel(token, modelData);
      }

      onSaved();
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  // Close on escape key
  useEffect(() => {
    const handleEscape = (e) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [onClose]);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <h2>{isEditing ? 'Edit Model' : 'Create New Model'}</h2>
        <p className="modal-subtitle">
          Adjust the weight distribution for prediction factors (must total 100%)
        </p>

        <form onSubmit={handleSubmit}>
          {/* Name Input */}
          <div className="form-group">
            <label htmlFor="model-name">Model Name</label>
            <input
              id="model-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="My Custom Model"
              maxLength={100}
              required
            />
          </div>

          {/* Description Input */}
          <div className="form-group">
            <label htmlFor="model-description">Description</label>
            <textarea
              id="model-description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describe your model's strategy..."
              rows={3}
            />
          </div>

          {/* Weight Distribution */}
          <div className="weights-section">
            <div className="weights-header">
              <span>Weight Distribution</span>
              <span className={`weights-total ${isValid ? 'valid' : totalWeight !== 100 ? 'invalid' : ''}`}>
                {totalWeight}%
              </span>
            </div>

            {WEIGHT_CATEGORIES.map(({ key, label, description }) => (
              <div className="weight-slider-row" key={key}>
                <div className="weight-info">
                  <span className="weight-label">{label}</span>
                  <span className="weight-description">{description}</span>
                </div>
                <div className="weight-controls">
                  <input
                    type="range"
                    min="0"
                    max="100"
                    value={weights[key]}
                    onChange={(e) => handleSliderChange(key, e.target.value)}
                    className="weight-slider"
                  />
                  <input
                    type="number"
                    min="0"
                    max="100"
                    value={weights[key]}
                    onChange={(e) => handleWeightChange(key, e.target.value)}
                    className="weight-input"
                  />
                  <span className="weight-percent">%</span>
                </div>
              </div>
            ))}

            <button type="button" className="reset-btn" onClick={handleReset}>
              Reset to Defaults
            </button>
          </div>

          {/* Error Message */}
          {error && (
            <div className="form-error">
              {error}
            </div>
          )}

          {/* Actions */}
          <div className="modal-actions">
            <button type="button" className="btn-cancel" onClick={onClose} disabled={saving}>
              Cancel
            </button>
            <button type="submit" className="btn-submit" disabled={!isValid || saving}>
              {saving ? 'Saving...' : isEditing ? 'Save Changes' : 'Create Model'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default CreateModelModal;
