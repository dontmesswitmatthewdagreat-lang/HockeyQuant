import { Link, useLocation } from 'react-router-dom';
import './Navbar.css';

function Navbar() {
  const location = useLocation();

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
      </div>
    </nav>
  );
}

export default Navbar;
