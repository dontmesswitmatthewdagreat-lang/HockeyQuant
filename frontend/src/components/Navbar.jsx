import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import UserMenu from './Auth/UserMenu';
import './Navbar.css';
import './Auth/Auth.css';

function Navbar() {
  const location = useLocation();
  const { user, loading } = useAuth();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const toggleMobileMenu = () => setMobileMenuOpen(!mobileMenuOpen);
  const closeMobileMenu = () => setMobileMenuOpen(false);

  return (
    <nav className="navbar">
      <Link to="/" className="navbar-brand" onClick={closeMobileMenu}>
        <img src="/logo.png" alt="HockeyQuant" className="brand-logo" />
        <span className="brand-version">v1</span>
      </Link>

      <button className="hamburger" onClick={toggleMobileMenu} aria-label="Toggle menu">
        <span className={mobileMenuOpen ? 'open' : ''}></span>
        <span className={mobileMenuOpen ? 'open' : ''}></span>
        <span className={mobileMenuOpen ? 'open' : ''}></span>
      </button>

      <div className={`navbar-links ${mobileMenuOpen ? 'open' : ''}`}>
        <Link
          to="/"
          className={`nav-link ${location.pathname === '/' ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          Home
        </Link>
        <Link
          to="/predictions"
          className={`nav-link ${location.pathname === '/predictions' ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          Predictions
        </Link>
        <Link
          to="/teams"
          className={`nav-link ${location.pathname === '/teams' ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          Teams
        </Link>
        <Link
          to="/accuracy"
          className={`nav-link ${location.pathname === '/accuracy' ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          Accuracy
        </Link>
        <Link
          to="/about"
          className={`nav-link ${location.pathname === '/about' ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          About
        </Link>

        {/* Auth links inside mobile menu */}
        <div className="mobile-auth">
          {loading ? (
            <span className="auth-loading">...</span>
          ) : user ? (
            <UserMenu onAction={closeMobileMenu} />
          ) : (
            <>
              <Link to="/login" className="nav-link" onClick={closeMobileMenu}>Log In</Link>
              <Link to="/signup" className="nav-link signup-link" onClick={closeMobileMenu}>Sign Up</Link>
            </>
          )}
        </div>
      </div>

      <div className="navbar-auth desktop-only">
        {loading ? (
          <span className="auth-loading">...</span>
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
