import { useState, useEffect, useRef } from 'react';
import { fetchPredictions, fetchPredictionsWithGoalies } from '../api';
import GameCard from '../components/GameCard';
import LoadingSpinner from '../components/LoadingSpinner';
import './Predictions.css';

function Predictions() {
  const [date, setDate] = useState(getTodayDate());
  const [predictions, setPredictions] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [goalieOverrides, setGoalieOverrides] = useState({});
  const [recalculatingGames, setRecalculatingGames] = useState(new Set());

  // Debounce timer ref
  const debounceTimer = useRef(null);

  function getTodayDate() {
    const today = new Date();
    return today.toISOString().split('T')[0];
  }

  async function loadPredictions(selectedDate, overrides = {}) {
    setLoading(true);
    setError(null);
    try {
      let data;
      if (Object.keys(overrides).length > 0) {
        data = await fetchPredictionsWithGoalies(selectedDate, overrides);
      } else {
        data = await fetchPredictions(selectedDate);
      }
      setPredictions(data.predictions || []);
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
    loadPredictions(date);
  }

  async function handleGoalieChange(team, goalieName) {
    // Update local state immediately
    const newOverrides = { ...goalieOverrides, [team]: goalieName };
    setGoalieOverrides(newOverrides);

    // Mark games involving this team as recalculating
    const affectedGames = predictions.filter(
      (p) => p.away.team === team || p.home.team === team
    );
    const affectedKeys = new Set(affectedGames.map((p) => `${p.away.team}-${p.home.team}`));
    setRecalculatingGames(affectedKeys);

    // Debounce the API call (wait 500ms for user to finish selecting)
    if (debounceTimer.current) {
      clearTimeout(debounceTimer.current);
    }

    debounceTimer.current = setTimeout(async () => {
      try {
        const data = await fetchPredictionsWithGoalies(date, newOverrides);
        setPredictions(data.predictions || []);
      } catch (err) {
        console.error('Failed to recalculate:', err);
      } finally {
        setRecalculatingGames(new Set());
      }
    }, 500);
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
            </p>
            <div className="predictions-list">
              {predictions.map((prediction) => {
                const gameKey = `${prediction.away.team}-${prediction.home.team}`;
                return (
                  <GameCard
                    key={gameKey}
                    prediction={prediction}
                    onGoalieChange={handleGoalieChange}
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
