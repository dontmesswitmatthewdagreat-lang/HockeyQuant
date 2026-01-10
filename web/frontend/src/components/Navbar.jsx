import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import UserMenu from './Auth/UserMenu';
import './Navbar.css';
import './Auth/Auth.css';

function Navbar() {
  const location = useLocation();
  const { user, loading } = useAuth();

  return (
    <nav className="navbar">
      <Link to="/" className="navbar-brand">
        <span className="brand-icon">🏒</span>
        <span className="brand-text">HockeyQuant</span>
      </Link>
      <div className="navbar-links">
        <Link
          to="/"
          className={`nav-link ${location.pathname === '/' ? 'active' : ''}`}
        >
          Home
        </Link>
        <Link
          to="/predictions"
          className={`nav-link ${location.pathname === '/predictions' ? 'active' : ''}`}
        >
          Predictions
        </Link>
        <Link
          to="/teams"
          className={`nav-link ${location.pathname === '/teams' ? 'active' : ''}`}
        >
          Teams
        </Link>
        <Link
          to="/accuracy"
          className={`nav-link ${location.pathname === '/accuracy' ? 'active' : ''}`}
        >
          Accuracy
        </Link>
      </div>
      <div className="navbar-auth">
        {loading ? (
          <span style={{color: '#7eb8da', fontSize: '0.85rem'}}>...</span>
        ) : user ? (
          <UserMenu />
        ) : (
          <div className="auth-links">
            <Link to="/login" className="auth-link">Log In</Link>
            <Link to="/signup" className="auth-link primary">Sign Up</Link>
          </div>
        )}
      </div>
    </nav>
  );
}

export default Navbar;
