import { useState, useEffect } from 'react';
import './ProgressBar.css';

const MESSAGES = [
  'Connecting to server...',
  'Fetching game schedule...',
  'Loading team statistics...',
  'Analyzing matchups...',
  'Calculating predictions...',
];

function ProgressBar({ message }) {
  const [stage, setStage] = useState(0);

  useEffect(() => {
    // Cycle through messages every 3 seconds
    const interval = setInterval(() => {
      setStage((prev) => (prev + 1) % MESSAGES.length);
    }, 3000);

    return () => clearInterval(interval);
  }, []);

  // Use custom message if provided, otherwise use cycling messages
  const displayMessage = message || MESSAGES[stage];

  return (
    <div className="progress-container">
      <div className="progress-track">
        <div className="progress-slider" />
      </div>
      <p className="progress-message">{displayMessage}</p>
    </div>
  );
}

export default ProgressBar;
