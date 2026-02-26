import { useState, useEffect } from 'react';
import { fetchPredictions } from '../api';
import GameCard from '../components/GameCard';
import ProgressBar from '../components/ProgressBar';
import './Predictions.css';

// Module-level cache for predictions
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

  function getYesterday() {
    const d = new Date(date);
    d.setDate(d.getDate() - 1);
    return d.toISOString().split('T')[0];
  }

  function getTomorrow() {
    const d = new Date(date);
    d.setDate(d.getDate() + 1);
    return d.toISOString().split('T')[0];
  }

  function formatDateDisplay(dateStr) {
    const d = new Date(dateStr + 'T12:00:00');
    return d.toLocaleDateString('en-US', {
      weekday: 'long',
      month: 'long',
      day: 'numeric',
      year: 'numeric'
    });
  }

  function isToday(dateStr) {
    return dateStr === getTodayDate();
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
      if (data.status) {
        setModelStatus(data.status);
      }
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
  }, [date]);

  function handleDateNav(newDate) {
    setDate(newDate);
  }

  // Calculate summary stats
  const totalGames = predictions.length;
  const highConfidence = predictions.filter(p => p.confidence === 'STRONG').length;
  const avgWinProb = predictions.length > 0
    ? Math.round(predictions.reduce((sum, p) => {
        const winnerScore = p.pick === p.home.team ? p.home.final_score : p.away.final_score;
        const loserScore = p.pick === p.home.team ? p.away.final_score : p.home.final_score;
        const total = winnerScore + loserScore;
        return sum + (total > 0 ? (winnerScore / total) * 100 : 50);
      }, 0) / predictions.length)
    : 0;
  const now = Date.now();
  const liveGames = predictions.filter(p => {
    if (!p.game_time) return false;
    const start = new Date(p.game_time).getTime();
    const end = start + 3.5 * 60 * 60 * 1000; // ~3.5 hour game window
    return now >= start && now <= end;
  }).length;

  return (
    <div className="predictions-page">
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

      {/* Date Navigation */}
      <div className="date-nav-container">
        <button className="date-nav-arrow" onClick={() => handleDateNav(getYesterday())}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <polyline points="15 18 9 12 15 6"></polyline>
          </svg>
        </button>

        <div className="date-nav-center">
          <div className="date-display">
            <svg className="calendar-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
              <line x1="16" y1="2" x2="16" y2="6"></line>
              <line x1="8" y1="2" x2="8" y2="6"></line>
              <line x1="3" y1="10" x2="21" y2="10"></line>
            </svg>
            {formatDateDisplay(date)}
          </div>
          <div className="date-quick-nav">
            <button
              className={`quick-nav-btn ${date === getYesterday() ? '' : ''}`}
              onClick={() => handleDateNav(getYesterday())}
            >
              Yesterday
            </button>
            <button
              className={`quick-nav-btn ${isToday(date) ? 'active' : ''}`}
              onClick={() => handleDateNav(getTodayDate())}
            >
              Today
            </button>
            <button
              className={`quick-nav-btn ${date === getTomorrow() ? '' : ''}`}
              onClick={() => handleDateNav(getTomorrow())}
            >
              Tomorrow
            </button>
          </div>
        </div>

        <button className="date-nav-arrow" onClick={() => handleDateNav(getTomorrow())}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <polyline points="9 18 15 12 9 6"></polyline>
          </svg>
        </button>
      </div>

      {/* Summary Stats */}
      {!loading && !error && predictions.length > 0 && (
        <div className="summary-stats">
          <div className="stat-card">
            <span className="stat-label">Total Games</span>
            <span className="stat-value">{totalGames}</span>
          </div>
          <div className="stat-card">
            <span className="stat-label">High Confidence</span>
            <span className="stat-value">{highConfidence}</span>
          </div>
          <div className="stat-card">
            <span className="stat-label">Avg Win Prob</span>
            <span className="stat-value">{avgWinProb}%</span>
          </div>
          <div className="stat-card">
            <span className="stat-label">Live Games</span>
            <span className="stat-value">{liveGames}</span>
          </div>
        </div>
      )}

      {/* Content */}
      <div className="predictions-content">
        {loading && <ProgressBar />}

        {error && (
          <div className="error-message">
            <p>Error: {error}</p>
            <button onClick={() => loadPredictions(date, true)}>Try Again</button>
          </div>
        )}

        {!loading && !error && predictions.length === 0 && (
          <div className="no-games">
            <div className="no-games-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
                <line x1="16" y1="2" x2="16" y2="6"></line>
                <line x1="8" y1="2" x2="8" y2="6"></line>
                <line x1="3" y1="10" x2="21" y2="10"></line>
              </svg>
            </div>
            <h3>No Games Scheduled</h3>
            <p>There are no NHL games scheduled for {formatDateDisplay(date)}</p>
          </div>
        )}

        {!loading && !error && predictions.length > 0 && (
          <div className="games-grid">
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
        )}
      </div>
    </div>
  );
}

export default Predictions;
