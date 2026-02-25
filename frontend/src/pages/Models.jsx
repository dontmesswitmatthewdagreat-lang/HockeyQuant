import { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { fetchUserModels, deleteModel } from '../api';
import ModelCard from '../components/ModelCard';
import CreateModelModal from '../components/CreateModelModal';
import './Models.css';

function Models() {
  const { user, session } = useAuth();
  const [models, setModels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editingModel, setEditingModel] = useState(null);

  // Load models when user is authenticated
  useEffect(() => {
    if (user && session?.access_token) {
      loadModels();
    } else {
      setLoading(false);
    }
  }, [user, session]);

  const loadModels = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await fetchUserModels(session.access_token);
      setModels(data.models || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteModel = async (modelId) => {
    if (!confirm('Are you sure you want to delete this model? This cannot be undone.')) {
      return;
    }
    try {
      await deleteModel(session.access_token, modelId);
      setModels(models.filter(m => m.id !== modelId));
    } catch (err) {
      alert('Failed to delete model: ' + err.message);
    }
  };

  const handleEditModel = (model) => {
    setEditingModel(model);
    setShowCreateModal(true);
  };

  const handleModalClose = () => {
    setShowCreateModal(false);
    setEditingModel(null);
  };

  const handleModelSaved = () => {
    handleModalClose();
    loadModels();
  };

  // Calculate summary stats
  const totalModels = models.length;
  const totalPredictions = models.reduce((sum, m) => sum + (m.accuracy?.total_predictions || 0), 0);
  const bestAccuracy = models.length > 0
    ? Math.max(...models.map(m => m.accuracy?.accuracy_pct || 0))
    : 0;

  return (
    <div className="models-page">
      <div className="models-header">
        <div className="models-title-section">
          <h1>Prediction Models</h1>
          <p className="models-subtitle">Build and track custom prediction models with different weight configurations</p>
        </div>
        <button className="btn-create-model" onClick={() => setShowCreateModal(true)}>
          <span>+</span> New Model
        </button>
      </div>

      {/* Summary Stats */}
      <div className="models-stats">
        <div className="stat-card">
          <span className="stat-label">Total Models</span>
          <span className="stat-value">{totalModels}</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Best Accuracy</span>
          <span className="stat-value">{bestAccuracy.toFixed(1)}%</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Total Predictions</span>
          <span className="stat-value">{totalPredictions}</span>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="models-error">
          <p>{error}</p>
          <button onClick={loadModels}>Try Again</button>
        </div>
      )}

      {/* Loading */}
      {loading && (
        <div className="models-loading">
          <div className="spinner"></div>
          <p>Loading your models...</p>
        </div>
      )}

      {/* Models Grid */}
      {!loading && !error && (
        <>
          {models.length === 0 ? (
            <div className="models-empty">
              <div className="empty-icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <line x1="18" y1="20" x2="18" y2="10"></line>
                  <line x1="12" y1="20" x2="12" y2="4"></line>
                  <line x1="6" y1="20" x2="6" y2="14"></line>
                </svg>
              </div>
              <h3>No Models Yet</h3>
              <p>Create your first custom prediction model to get started.</p>
              <button className="btn-primary" onClick={() => setShowCreateModal(true)}>
                Create Model
              </button>
            </div>
          ) : (
            <div className="models-grid">
              {models.map(model => (
                <ModelCard
                  key={model.id}
                  model={model}
                  onEdit={() => handleEditModel(model)}
                  onDelete={() => handleDeleteModel(model.id)}
                />
              ))}
            </div>
          )}
        </>
      )}

      {/* Create/Edit Modal */}
      {showCreateModal && (
        <CreateModelModal
          model={editingModel}
          token={session?.access_token || null}
          onClose={handleModalClose}
          onSaved={handleModelSaved}
        />
      )}
    </div>
  );
}

export default Models;
