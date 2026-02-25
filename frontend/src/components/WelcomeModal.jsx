import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import './WelcomeModal.css';

const VISITED_KEY = 'hockeyquant_visited';

function WelcomeModal({ onClose }) {
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (loading) return;
    if (user) return;
    if (localStorage.getItem(VISITED_KEY)) return;
    setVisible(true);
  }, [user, loading]);

  const dismiss = () => {
    localStorage.setItem(VISITED_KEY, 'true');
    setVisible(false);
    onClose();
  };

  const handleSignUp = () => {
    localStorage.setItem(VISITED_KEY, 'true');
    setVisible(false);
    navigate('/signup');
  };

  const handleLogIn = () => {
    localStorage.setItem(VISITED_KEY, 'true');
    setVisible(false);
    navigate('/login');
  };

  if (!visible) return null;

  return (
    <div className="modal-overlay" onClick={dismiss}>
      <div className="welcome-modal" onClick={(e) => e.stopPropagation()}>
        <img src="/logo.png" alt="HockeyQuant" className="welcome-logo" />
        <h2>Welcome to HockeyQuant</h2>
        <p className="welcome-subtitle">
          Data-driven NHL predictions powered by advanced analytics.
        </p>

        <div className="welcome-features">
          <div className="welcome-feature">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <polyline points="20 6 9 17 4 12"></polyline>
            </svg>
            <span>Save custom prediction models with your own weights</span>
          </div>
          <div className="welcome-feature">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <polyline points="20 6 9 17 4 12"></polyline>
            </svg>
            <span>Track your model accuracy over time</span>
          </div>
          <div className="welcome-feature">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <polyline points="20 6 9 17 4 12"></polyline>
            </svg>
            <span>Set a favorite team and personalize your experience</span>
          </div>
        </div>

        <div className="welcome-actions">
          <button className="btn-welcome-signup" onClick={handleSignUp}>
            Sign Up
          </button>
          <button className="btn-welcome-login" onClick={handleLogIn}>
            Log In
          </button>
        </div>
        <button className="btn-welcome-guest" onClick={dismiss}>
          Continue as Guest
        </button>
      </div>
    </div>
  );
}

export default WelcomeModal;
