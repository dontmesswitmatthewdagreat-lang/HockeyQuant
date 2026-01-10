/**
 * HockeyQuant API Client
 * Connects to the backend at hockeyquant.onrender.com
 */

const API_BASE = 'https://hockeyquant.onrender.com';

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

export async function fetchPredictionsWithGoalies(date, goalieOverrides) {
  const response = await fetch(`${API_BASE}/api/predictions/${date}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ goalie_overrides: goalieOverrides }),
  });
  if (!response.ok) {
    if (response.status === 404) {
      return { predictions: [], games_count: 0, date };
    }
    throw new Error('Failed to fetch predictions');
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

export async function fetchAccuracyTrend(window = 30) {
  const response = await fetch(`${API_BASE}/api/accuracy/trend?window=${window}`);
  if (!response.ok) {
    throw new Error('Failed to fetch accuracy trend');
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
