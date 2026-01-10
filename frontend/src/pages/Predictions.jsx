import { useState, useEffect, useRef } from 'react';
import { fetchPredictions, fetchPredictionsWithGoalies } from '../api';
import GameCard from '../components/GameCard';
import LoadingSpinner from '../components/LoadingSpinner';
import './Predictions.css';

// Module-level cache for predictions - persists across tab switches
// Key: date string, Value: { predictions, timestamp }
const predictionsCache = {};
const CACHE_DURATION_MS = 5 * 60 * 1000; // 5 minutes

function Predictions() {
  const [date, setDate] = useState(getTodayDate());
  const [predictions, setPredictions] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [goalieOverrides, setGoalieOverrides] = useState({});
  const [recalculatingGames, setRecalculatingGames] = useState(new Set());
  const [fromCache, setFromCache] = useState(false);

  // Debounce timer ref
  const debounceTimer = useRef(null);

  function getTodayDate() {
    const today = new Date();
    return today.toISOString().split('T')[0];
  }

  // Check if cached data is still valid
  function getCachedPredictions(selectedDate) {
    const cached = predictionsCache[selectedDate];
    if (cached && Date.now() - cached.timestamp < CACHE_DURATION_MS) {
      return cached.predictions;
    }
    return null;
  }

  // Store predictions in cache
  function setCachedPredictions(selectedDate, predictions) {
    predictionsCache[selectedDate] = {
      predictions,
      timestamp: Date.now(),
    };
  }

  async function loadPredictions(selectedDate, overrides = {}, forceRefresh = false) {
    setError(null);
    setFromCache(false);

    // Check cache first (only for default goalie predictions)
    if (!forceRefresh && Object.keys(overrides).length === 0) {
      const cached = getCachedPredictions(selectedDate);
      if (cached) {
        setPredictions(cached);
        setFromCache(true);
        return;
      }
    }

    setLoading(true);
    try {
      let data;
      if (Object.keys(overrides).length > 0) {
        data = await fetchPredictionsWithGoalies(selectedDate, overrides);
      } else {
        data = await fetchPredictions(selectedDate);
      }
      const preds = data.predictions || [];
      setPredictions(preds);

      // Cache the default predictions (no overrides)
      if (Object.keys(overrides).length === 0) {
        setCachedPredictions(selectedDate, preds);
      }
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
    // Clear goalie overrides when changing date
    setGoalieOverrides({});
  }

  function handleSubmit(e) {
    e.preventDefault();
    setGoalieOverrides({});
    // Force refresh when user clicks the button
    loadPredictions(date, {}, true);
  }

  // Handle goalie toggle - goalieName is null to use starter, or backup name to use backup
  async function handleGoalieToggle(team, goalieName) {
    // Update overrides - if goalieName is null, remove the override
    const newOverrides = { ...goalieOverrides };
    if (goalieName === null) {
      delete newOverrides[team];
    } else {
      newOverrides[team] = goalieName;
    }
    setGoalieOverrides(newOverrides);

    // Mark games involving this team as recalculating
    const affectedGames = predictions.filter(
      (p) => p.away.team === team || p.home.team === team
    );
    const affectedKeys = new Set(affectedGames.map((p) => `${p.away.team}-${p.home.team}`));
    setRecalculatingGames(affectedKeys);

    // Debounce the API call
    if (debounceTimer.current) {
      clearTimeout(debounceTimer.current);
    }

    debounceTimer.current = setTimeout(async () => {
      try {
        let data;
        if (Object.keys(newOverrides).length > 0) {
          data = await fetchPredictionsWithGoalies(date, newOverrides);
        } else {
          data = await fetchPredictions(date);
        }
        // Merge updated data while preserving original order
        setPredictions((currentPredictions) => {
          const updatedMap = {};
          for (const pred of data.predictions || []) {
            const key = `${pred.away.team}-${pred.home.team}`;
            updatedMap[key] = pred;
          }
          return currentPredictions.map((pred) => {
            const key = `${pred.away.team}-${pred.home.team}`;
            return updatedMap[key] || pred;
          });
        });
      } catch (err) {
        console.error('Failed to recalculate:', err);
      } finally {
        setRecalculatingGames(new Set());
      }
    }, 300);
  }

  return (
    <div className="predictions-page">
      <div className="predictions-header">
        <h1 className="page-title">Game Predictions</h1>
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

      <div className="predictions-content">
        {loading && (
          <LoadingSpinner message="Fetching predictions..." />
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
              {Object.keys(goalieOverrides).length > 0 && (
                <span className="override-indicator"> (custom goalies)</span>
              )}
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
                    onGoalieToggle={handleGoalieToggle}
                    isRecalculating={recalculatingGames.has(gameKey)}
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
