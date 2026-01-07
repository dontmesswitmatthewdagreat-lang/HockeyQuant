import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { fetchTeams } from '../api';
import './Account.css';

function Account() {
  const { user, profile, loading, updateProfile } = useAuth();
  const navigate = useNavigate();

  const [username, setUsername] = useState('');
  const [favoriteTeam, setFavoriteTeam] = useState('');
  const [teams, setTeams] = useState([]);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  // Redirect if not logged in
  useEffect(() => {
    if (!loading && !user) {
      navigate('/login');
    }
  }, [user, loading, navigate]);

  // Load profile data
  useEffect(() => {
    if (profile) {
      setUsername(profile.username || '');
      setFavoriteTeam(profile.favorite_team || '');
    }
  }, [profile]);

  // Load teams list
  useEffect(() => {
    async function loadTeams() {
      try {
        const data = await fetchTeams();
        setTeams(data.teams || []);
      } catch (err) {
        console.error('Failed to load teams:', err);
      }
    }
    loadTeams();
  }, []);

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setMessage('');
    setSaving(true);

    try {
      await updateProfile({
        username,
        favorite_team: favoriteTeam || null,
      });
      setMessage('Profile updated successfully!');
    } catch (err) {
      setError(err.message || 'Failed to update profile');
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return (
      <div className="account-page">
        <div className="account-loading">Loading...</div>
      </div>
    );
  }

  return (
    <div className="account-page">
      <div className="account-card">
        <h1 className="account-title">Account Settings</h1>

        {message && <div className="account-success">{message}</div>}
        {error && <div className="account-error">{error}</div>}

        <form onSubmit={handleSubmit} className="account-form">
          <div className="form-group">
            <label htmlFor="email">Email</label>
            <input
              type="email"
              id="email"
              value={user?.email || ''}
              disabled
              className="disabled"
            />
            <span className="form-hint">Email cannot be changed</span>
          </div>

          <div className="form-group">
            <label htmlFor="username">Username</label>
            <input
              type="text"
              id="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="Your display name"
            />
          </div>

          <div className="form-group">
            <label htmlFor="favoriteTeam">Favorite Team</label>
            <select
              id="favoriteTeam"
              value={favoriteTeam}
              onChange={(e) => setFavoriteTeam(e.target.value)}
            >
              <option value="">No favorite team</option>
              {teams.map((team) => (
                <option key={team.abbrev} value={team.abbrev}>
                  {team.name}
                </option>
              ))}
            </select>
          </div>

          <button type="submit" className="save-button" disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
        </form>

        <div className="account-section">
          <h2 className="section-title">Account Info</h2>
          <div className="info-row">
            <span className="info-label">Member since</span>
            <span className="info-value">
              {profile?.created_at
                ? new Date(profile.created_at).toLocaleDateString()
                : 'N/A'}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

export default Account;
