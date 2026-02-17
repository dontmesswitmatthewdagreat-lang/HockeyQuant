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

  // Check if a path is active
  const isActive = (path) => location.pathname === path;

  return (
    <nav className="navbar">
      <Link to="/" className="navbar-brand" onClick={closeMobileMenu}>
        <img src="/logo.png" alt="HockeyQuant" className="brand-logo" />
        <span className="brand-name">HockeyQuant</span>
      </Link>

      <button className="hamburger" onClick={toggleMobileMenu} aria-label="Toggle menu">
        <span className={mobileMenuOpen ? 'open' : ''}></span>
        <span className={mobileMenuOpen ? 'open' : ''}></span>
        <span className={mobileMenuOpen ? 'open' : ''}></span>
      </button>

      <div className={`navbar-links ${mobileMenuOpen ? 'open' : ''}`}>
        <Link
          to="/"
          className={`nav-link ${isActive('/') ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          <svg className="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path>
            <polyline points="9 22 9 12 15 12 15 22"></polyline>
          </svg>
          Home
        </Link>
        <Link
          to="/games"
          className={`nav-link ${isActive('/games') ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          <svg className="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
            <line x1="16" y1="2" x2="16" y2="6"></line>
            <line x1="8" y1="2" x2="8" y2="6"></line>
            <line x1="3" y1="10" x2="21" y2="10"></line>
          </svg>
          Games
        </Link>
        <Link
          to="/teams"
          className={`nav-link ${isActive('/teams') ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          <svg className="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
            <circle cx="9" cy="7" r="4"></circle>
            <path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>
            <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
          </svg>
          Teams
        </Link>
        <Link
          to="/accuracy"
          className={`nav-link ${isActive('/accuracy') ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          <svg className="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <circle cx="12" cy="12" r="10"></circle>
            <circle cx="12" cy="12" r="6"></circle>
            <circle cx="12" cy="12" r="2"></circle>
          </svg>
          Accuracy
        </Link>
        <Link
          to="/models"
          className={`nav-link ${isActive('/models') ? 'active' : ''}`}
          onClick={closeMobileMenu}
        >
          <svg className="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <line x1="18" y1="20" x2="18" y2="10"></line>
            <line x1="12" y1="20" x2="12" y2="4"></line>
            <line x1="6" y1="20" x2="6" y2="14"></line>
          </svg>
          Models
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
