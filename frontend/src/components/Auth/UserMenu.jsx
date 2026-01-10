import { useState, useRef, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import './Auth.css';

function UserMenu() {
  const [isOpen, setIsOpen] = useState(false);
  const menuRef = useRef(null);
  const { user, profile, signOut } = useAuth();
  const navigate = useNavigate();

  // Close menu when clicking outside
  useEffect(() => {
    function handleClickOutside(event) {
      if (menuRef.current && !menuRef.current.contains(event.target)) {
        setIsOpen(false);
      }
    }

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  async function handleLogout() {
    try {
      await signOut();
      setIsOpen(false);
      navigate('/');
    } catch (err) {
      console.error('Logout error:', err);
    }
  }

  const displayName = profile?.username || user?.email?.split('@')[0] || 'User';
  const initial = displayName.charAt(0).toUpperCase();

  return (
    <div className="user-menu" ref={menuRef}>
      <button
        className="user-menu-button"
        onClick={() => setIsOpen(!isOpen)}
      >
        <span className="avatar">{initial}</span>
        <span>{displayName}</span>
      </button>

      {isOpen && (
        <div className="user-menu-dropdown">
          <Link
            to="/account"
            className="user-menu-item"
            onClick={() => setIsOpen(false)}
          >
            Account Settings
          </Link>
          <Link
            to="/predictions"
            className="user-menu-item"
            onClick={() => setIsOpen(false)}
          >
            My Predictions
          </Link>
          <button
            className="user-menu-item logout"
            onClick={handleLogout}
          >
            Log Out
          </button>
        </div>
      )}
    </div>
  );
}

export default UserMenu;
