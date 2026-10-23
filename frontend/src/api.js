/**
 * HockeyQuant API Client
 * Uses VITE_API_URL env var for local dev, falls back to production
 */

const isLocal = typeof window !== 'undefined' && window.location.hostname === 'localhost';
const API_BASE = import.meta.env.VITE_API_URL
  || (isLocal ? 'http://localhost:8000' : 'https://hockeyquant.onrender.com');

export async function fetchPredictions(date) {
  const response = await fetch(`${API_BASE}/api/predictions/${date}`);
  if (!response.ok) {
    if (response.status === 404) {
      return { predictions: [], games_count: 0, date };
    }
    throw new Error('Failed to fetch predictions');
  }
  return response.json();
}

export async function fetchTeams() {
  const response = await fetch(`${API_BASE}/api/teams`);
  if (!response.ok) {
    throw new Error('Failed to fetch teams');
  }
  return response.json();
}

export async function fetchTeam(abbrev) {
  const response = await fetch(`${API_BASE}/api/teams/${abbrev}`);
  if (!response.ok) {
    throw new Error('Failed to fetch team');
  }
  return response.json();
}

export async function fetchGames(date) {
  const response = await fetch(`${API_BASE}/api/games/${date}`);
  if (!response.ok) {
    throw new Error('Failed to fetch games');
  }
  return response.json();
}

export async function fetchTeamGoalies(abbrev) {
  const response = await fetch(`${API_BASE}/api/teams/${abbrev}/goalies`);
  if (!response.ok) {
    throw new Error('Failed to fetch goalies');
  }
  return response.json();
}

// Accuracy tracking endpoints
export async function fetchAccuracyStats(params = {}) {
  const searchParams = new URLSearchParams();
  if (params.startDate) searchParams.append('start_date', params.startDate);
  if (params.endDate) searchParams.append('end_date', params.endDate);
  if (params.team) searchParams.append('team', params.team);
  if (params.confidence) searchParams.append('confidence', params.confidence);

  const url = `${API_BASE}/api/accuracy/stats${searchParams.toString() ? '?' + searchParams.toString() : ''}`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error('Failed to fetch accuracy stats');
  }
  return response.json();
}

export async function storePredictions(date) {
  const response = await fetch(`${API_BASE}/api/accuracy/store-predictions/${date}`, {
    method: 'POST',
  });
  if (!response.ok) {
    throw new Error('Failed to store predictions');
  }
  return response.json();
}

export async function updateResults(date) {
  const response = await fetch(`${API_BASE}/api/accuracy/update-results/${date}`, {
    method: 'POST',
  });
  if (!response.ok) {
    throw new Error('Failed to update results');
  }
  return response.json();
}

export async function updateAllPendingResults() {
  const response = await fetch(`${API_BASE}/api/accuracy/update-all-pending`, {
    method: 'POST',
  });
  if (!response.ok) {
    throw new Error('Failed to update pending results');
  }
  return response.json();
}

export async function fetchAccuracyTrend(window = 30, predictionType = 'moneyline', team = '') {
  const params = new URLSearchParams({ window, prediction_type: predictionType });
  if (team) params.append('team', team);
  const response = await fetch(`${API_BASE}/api/accuracy/trend?${params}`);
  if (!response.ok) {
    throw new Error('Failed to fetch accuracy trend');
  }
  return response.json();
}

export async function fetchAccuracyLeaderboard() {
  const response = await fetch(`${API_BASE}/api/accuracy/leaderboard`);
  if (!response.ok) {
    throw new Error('Failed to fetch leaderboard');
  }
  return response.json();
}

export async function fetchPredictionStatus(date) {
  const response = await fetch(`${API_BASE}/api/predictions/status/${date}`);
  if (!response.ok) {
    throw new Error('Failed to fetch prediction status');
  }
  return response.json();
}

// User Models API

/**
 * Fetch all models for the authenticated user
 * @param {string} token - Supabase access token
 */
export async function fetchUserModels(token) {
  const response = await fetch(`${API_BASE}/api/models`, {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    if (response.status === 401) {
      throw new Error('Please log in to view your models');
    }
    throw new Error('Failed to fetch models');
  }
  return response.json();
}

/**
 * Create a new custom model
 * @param {string} token - Supabase access token
 * @param {object} modelData - { name, description, weights }
 */
export async function createModel(token, modelData) {
  const response = await fetch(`${API_BASE}/api/models`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(modelData),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.detail || 'Failed to create model');
  }
  return response.json();
}

/**
 * Get a specific model by ID
 * @param {string} token - Supabase access token
 * @param {string} modelId - Model UUID
 */
export async function fetchModel(token, modelId) {
  const response = await fetch(`${API_BASE}/api/models/${modelId}`, {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    throw new Error('Failed to fetch model');
  }
  return response.json();
}

/**
 * Update an existing model
 * @param {string} token - Supabase access token
 * @param {string} modelId - Model UUID
 * @param {object} updates - { name?, description?, weights? }
 */
export async function updateModel(token, modelId, updates) {
  const response = await fetch(`${API_BASE}/api/models/${modelId}`, {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(updates),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.detail || 'Failed to update model');
  }
  return response.json();
}

/**
 * Delete a model
 * @param {string} token - Supabase access token
 * @param {string} modelId - Model UUID
 */
export async function deleteModel(token, modelId) {
  const response = await fetch(`${API_BASE}/api/models/${modelId}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    throw new Error('Failed to delete model');
  }
  return response.json();
}

/**
 * Generate an AI summary explaining the prediction pick
 * @param {object} prediction - Full prediction object from the predictions API
 */
export async function fetchGameSummary(prediction) {
  const response = await fetch(`${API_BASE}/api/summary`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      away: {
        team: prediction.away.team,
        final_score: prediction.away.final_score,
        goalie: prediction.away.goalie,
        goalie_gsax: prediction.away.goalie_gsax,
        goalie_sv_pct: prediction.away.goalie_sv_pct,
        fatigue: prediction.away.fatigue,
        streak: prediction.away.streak,
        injuries: prediction.away.injuries,
        h2h: prediction.away.h2h,
      },
      home: {
        team: prediction.home.team,
        final_score: prediction.home.final_score,
        goalie: prediction.home.goalie,
        goalie_gsax: prediction.home.goalie_gsax,
        goalie_sv_pct: prediction.home.goalie_sv_pct,
        fatigue: prediction.home.fatigue,
        streak: prediction.home.streak,
        injuries: prediction.home.injuries,
        h2h: prediction.home.h2h,
      },
      pick: prediction.pick,
      diff: prediction.diff,
      confidence: prediction.confidence,
      factors: prediction.factors || [],
      game_time: prediction.game_time,
    }),
  });
  if (!response.ok) {
    throw new Error('Failed to generate summary');
  }
  return response.json();
}

/**
 * Fetch the public leaderboard of all user models ranked by accuracy.
 * No token required.
 */
export async function fetchPublicModelsLeaderboard() {
  const response = await fetch(`${API_BASE}/api/models/leaderboard`);
  if (!response.ok) {
    throw new Error('Failed to fetch models leaderboard');
  }
  return response.json();
}

/**
 * Fetch the daily optimal parlay for a given date (on-the-fly, no auth required)
 * @param {string} date - Date in YYYY-MM-DD format
 */
export async function fetchDailyParlay(date) {
  const response = await fetch(`${API_BASE}/api/accuracy/parlay/${date}`);
  if (!response.ok) throw new Error('Failed to fetch daily parlay');
  return response.json();
}

/**
 * Fetch historical parlay accuracy stats
 */
export async function fetchParlayStats() {
  const response = await fetch(`${API_BASE}/api/accuracy/parlay-stats`);
  if (!response.ok) throw new Error('Failed to fetch parlay stats');
  return response.json();
}

/**
 * Live and final scores for all games on a date.
 * Returns { games: [{ away_team, home_team, away_score, home_score, game_state, period, period_type, time_remaining, in_intermission }] }
 * @param {string} date - Date in YYYY-MM-DD format
 */
export async function fetchGameScores(date) {
  try {
    const response = await fetch(`${API_BASE}/api/games/${date}/scores`);
    if (!response.ok) return { games: [] };
    return response.json();
  } catch {
    return { games: [] };
  }
}

/**
 * Get predictions using a custom model
 * @param {string} token - Supabase access token
 * @param {string} modelId - Model UUID
 * @param {string} date - Date in YYYY-MM-DD format
 */
export async function fetchModelPredictions(token, modelId, date) {
  const response = await fetch(`${API_BASE}/api/models/${modelId}/predictions/${date}`, {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    throw new Error('Failed to fetch model predictions');
  }
  return response.json();
}

// ---------------------------------------------------------------------------
// Advanced metrics (/api/advanced/*)
//
// Every one of these is decoration on a page that already works, so callers
// treat a failure as "no card" rather than an error state. Percentiles only
// come back for players over the ice-time floor (300 min skaters, 500 goalies),
// so early in a season these payloads carry raw numbers and no ranks.
// ---------------------------------------------------------------------------

export async function fetchAdvancedTeam(abbrev) {
  const response = await fetch(`${API_BASE}/api/advanced/team/${abbrev}`);
  if (!response.ok) {
    throw new Error('Failed to fetch advanced team metrics');
  }
  return response.json();
}

export async function fetchAdvancedSkaters(abbrev) {
  const response = await fetch(`${API_BASE}/api/advanced/skaters/${abbrev}`);
  if (!response.ok) {
    throw new Error('Failed to fetch skater impact');
  }
  return response.json();
}

export async function fetchAdvancedPlayer(playerId) {
  const response = await fetch(`${API_BASE}/api/advanced/player/${playerId}`);
  if (!response.ok) {
    throw new Error('Failed to fetch player card');
  }
  return response.json();
}

export async function fetchAdvancedGoalies(abbrev) {
  const response = await fetch(`${API_BASE}/api/advanced/goalies/${abbrev}`);
  if (!response.ok) {
    throw new Error('Failed to fetch goalie impact');
  }
  return response.json();
}

export async function fetchAdvancedGoalie(playerId) {
  const response = await fetch(`${API_BASE}/api/advanced/goalie/${playerId}`);
  if (!response.ok) {
    throw new Error('Failed to fetch goalie card');
  }
  return response.json();
}

export async function fetchTeamLines(abbrev) {
  const response = await fetch(`${API_BASE}/api/advanced/lines/${abbrev}`);
  if (!response.ok) {
    throw new Error('Failed to fetch line chemistry');
  }
  return response.json();
}

/** `GET /api/pulse/league` — the dial reads, including the per-team luck rows. */
export async function fetchLeaguePulses() {
  const response = await fetch(`${API_BASE}/api/pulse/league`);
  if (!response.ok) {
    throw new Error('Failed to fetch league pulses');
  }
  return response.json();
}

export async function fetchCalibration() {
  const response = await fetch(`${API_BASE}/api/accuracy/calibration`);
  if (!response.ok) {
    throw new Error('Failed to fetch calibration');
  }
  return response.json();
}

// ---------------------------------------------------------------------------
// News (/api/news/*)
// ---------------------------------------------------------------------------

/** `GET /api/news/latest` — the current league digest edition (+ team ones). */
export async function fetchLatestDigests(team) {
  const url = new URL(`${API_BASE}/api/news/latest`);
  if (team) url.searchParams.set('team', team);
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error('Failed to fetch digests');
  }
  return response.json();
}

/**
 * `GET /api/news/feed` — The Wire, the flat chronological archive.
 * Keyset-paginated: pass the previous response's `next_cursor` to continue.
 */
export async function fetchNewsFeed({ team, kind, cursor, limit = 30 } = {}) {
  const url = new URL(`${API_BASE}/api/news/feed`);
  if (team) url.searchParams.set('team', team);
  if (kind) url.searchParams.set('kind', kind);
  if (cursor) url.searchParams.set('cursor', cursor);
  url.searchParams.set('limit', String(limit));
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error('Failed to fetch the wire');
  }
  return response.json();
}

/** `GET /api/news/search` — AI answer over live news plus archive matches. */
export async function searchNews(q) {
  const url = new URL(`${API_BASE}/api/news/search`);
  url.searchParams.set('q', q);
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error('Search failed');
  }
  return response.json();
}
