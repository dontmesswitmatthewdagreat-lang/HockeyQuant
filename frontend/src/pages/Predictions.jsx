import { useState, useEffect } from 'react';
import { fetchPredictions } from '../api';
import GameCard from '../components/GameCard';
import ProgressBar from '../components/ProgressBar';
import './Predictions.css';

// Module-level cache for predictions - persists across tab switches
// Key: date string, Value: { predictions, status, timestamp }
const predictionsCache = {};
const CACHE_DURATION_MS = 5 * 60 * 1000; // 5 minutes

// Track if disclaimer has been dismissed this session
let disclaimerDismissedThisSession = false;

function Predictions() {
  const [date, setDate] = useState(getTodayDate());
  const [predictions, setPredictions] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [fromCache, setFromCache] = useState(false);
  const [modelStatus, setModelStatus] = useState(null);
  const [showDisclaimer, setShowDisclaimer] = useState(false);

  // Show disclaimer when loading starts (only if not dismissed)
  useEffect(() => {
    if (loading && !disclaimerDismissedThisSession && !fromCache) {
      setShowDisclaimer(true);
    }
  }, [loading, fromCache]);

  function dismissDisclaimer() {
    setShowDisclaimer(false);
    disclaimerDismissedThisSession = true;
  }

  function getTodayDate() {
    const today = new Date();
    return today.toISOString().split('T')[0];
  }

  // Format UTC timestamp to local time string
  function formatTime(isoString) {
    if (!isoString) return null;
    try {
      const date = new Date(isoString);
      return date.toLocaleTimeString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
        timeZoneName: 'short',
      });
    } catch {
      return null;
    }
  }

  // Check if cached data is still valid
  function getCachedData(selectedDate) {
    const cached = predictionsCache[selectedDate];
    if (cached && Date.now() - cached.timestamp < CACHE_DURATION_MS) {
      return { predictions: cached.predictions, status: cached.status };
    }
    return null;
  }

  // Store predictions and status in cache
  function setCachedData(selectedDate, predictions, status) {
    predictionsCache[selectedDate] = {
      predictions,
      status,
      timestamp: Date.now(),
    };
  }

  async function loadPredictions(selectedDate, forceRefresh = false) {
    setError(null);
    setFromCache(false);

    // Check cache first
    if (!forceRefresh) {
      const cached = getCachedData(selectedDate);
      if (cached) {
        setPredictions(cached.predictions);
        if (cached.status) {
          setModelStatus(cached.status);
        }
        setFromCache(true);
        return;
      }
    }

    setLoading(true);
    try {
      const data = await fetchPredictions(selectedDate);
      const preds = data.predictions || [];
      setPredictions(preds);

      // Update model status from response
      if (data.status) {
        setModelStatus(data.status);
      }

      // Cache the predictions and status
      setCachedData(selectedDate, preds, data.status);
    } catch (err) {
      setError(err.message);
      setPredictions([]);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadPredictions(date);
  }, []);

  function handleDateChange(e) {
    setDate(e.target.value);
  }

  function handleSubmit(e) {
    e.preventDefault();
    // Force refresh when user clicks the button
    loadPredictions(date, true);
  }

  return (
    <div className="predictions-page">
      <div className="predictions-header">
        <h1 className="page-title">Game Predictions</h1>

        {/* Model Status Display */}
        {modelStatus && modelStatus.is_cached && (
          <div className="model-status">
            {formatTime(modelStatus.last_updated) && (
              <div className="status-item">
                <span className="status-label">Last updated:</span>
                <span className="status-value">{formatTime(modelStatus.last_updated)}</span>
              </div>
            )}
            {formatTime(modelStatus.next_update) && (
              <div className="status-item">
                <span className="status-label">Next update:</span>
                <span className="status-value">{formatTime(modelStatus.next_update)}</span>
              </div>
            )}
          </div>
        )}

        <form className="date-form" onSubmit={handleSubmit}>
          <label htmlFor="date">Game Date:</label>
          <input
            type="date"
            id="date"
            value={date}
            onChange={handleDateChange}
          />
          <button type="submit" disabled={loading}>
            {loading ? 'Loading...' : 'Get Predictions'}
          </button>
        </form>
      </div>

      {/* Server spin-up disclaimer */}
      {showDisclaimer && (
        <div className="disclaimer-overlay">
          <div className="disclaimer-modal">
            <div className="disclaimer-icon">&#9432;</div>
            <h3 className="disclaimer-title">Heads Up!</h3>
            <p className="disclaimer-text">
              Predictions may take up to a minute to load if the server has been inactive.
              This is because our free-tier server automatically spins down during periods of inactivity.
            </p>
            <button className="disclaimer-button" onClick={dismissDisclaimer}>
              Got it
            </button>
          </div>
        </div>
      )}

      <div className="predictions-content">
        {loading && (
          <ProgressBar />
        )}

        {error && (
          <div className="error-message">
            <p>Error: {error}</p>
            <button onClick={() => loadPredictions(date)}>Try Again</button>
          </div>
        )}

        {!loading && !error && predictions.length === 0 && (
          <div className="no-games">
            <p>No games found for {date}</p>
          </div>
        )}

        {!loading && !error && predictions.length > 0 && (
          <>
            <p className="results-count">
              {predictions.length} game{predictions.length !== 1 ? 's' : ''} found
              {fromCache && (
                <span className="cache-indicator" title="Data loaded from cache">
                  {' '} (cached)
                </span>
              )}
            </p>
            <div className="predictions-list">
              {predictions.map((prediction) => {
                const gameKey = `${prediction.away.team}-${prediction.home.team}`;
                return (
                  <GameCard
                    key={gameKey}
                    prediction={prediction}
                  />
                );
              })}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

export default Predictions;
