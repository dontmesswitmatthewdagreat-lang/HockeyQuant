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
