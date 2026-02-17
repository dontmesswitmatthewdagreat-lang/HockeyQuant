import { Link } from 'react-router-dom';
import './Home.css';

function Home() {
  return (
    <div className="home-page">
      {/* Hero Section */}
      <section className="hero">
        <img src="/logo.png" alt="HockeyQuant" className="hero-logo" />
        <h1 className="hero-title">AI-Powered NHL Predictions</h1>
        <p className="hero-subtitle">
          Data-driven game predictions using real-time stats, goalie tracking, injury reports, and advanced analytics.
        </p>
        <div className="hero-actions">
          <Link to="/games" className="hero-btn primary">View Today's Games</Link>
          <Link to="/teams" className="hero-btn secondary">Explore Teams</Link>
        </div>
      </section>

      {/* Feature Cards */}
      <section className="features">
        <h2 className="section-heading">What You Can Do</h2>
        <div className="features-grid">
          <Link to="/games" className="feature-card">
            <div className="feature-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
                <line x1="16" y1="2" x2="16" y2="6"></line>
                <line x1="8" y1="2" x2="8" y2="6"></line>
                <line x1="3" y1="10" x2="21" y2="10"></line>
              </svg>
            </div>
            <h3 className="feature-title">Games</h3>
            <p className="feature-desc">Daily game predictions with confidence ratings and win probabilities.</p>
          </Link>

          <Link to="/teams" className="feature-card">
            <div className="feature-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
                <circle cx="9" cy="7" r="4"></circle>
                <path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>
                <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
              </svg>
            </div>
            <h3 className="feature-title">Teams</h3>
            <p className="feature-desc">Browse all 32 NHL teams, goalie stats, and injury reports.</p>
          </Link>

          <Link to="/accuracy" className="feature-card">
            <div className="feature-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="12" cy="12" r="10"></circle>
                <circle cx="12" cy="12" r="6"></circle>
                <circle cx="12" cy="12" r="2"></circle>
              </svg>
            </div>
            <h3 className="feature-title">Accuracy</h3>
            <p className="feature-desc">Track prediction accuracy over time with detailed trend charts.</p>
          </Link>

          <Link to="/models" className="feature-card">
            <div className="feature-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <line x1="18" y1="20" x2="18" y2="10"></line>
                <line x1="12" y1="20" x2="12" y2="4"></line>
                <line x1="6" y1="20" x2="6" y2="14"></line>
              </svg>
            </div>
            <h3 className="feature-title">Models</h3>
            <p className="feature-desc">Build custom prediction models with your own weight configurations.</p>
          </Link>
        </div>
      </section>

      {/* How It Works */}
      <section className="how-it-works">
        <h2 className="section-heading">How It Works</h2>
        <div className="steps">
          <div className="step">
            <div className="step-number">1</div>
            <h3 className="step-title">Analyze</h3>
            <p className="step-desc">We pull live data from the NHL API, MoneyPuck, ESPN, and Daily Faceoff every day.</p>
          </div>
          <div className="step">
            <div className="step-number">2</div>
            <h3 className="step-title">Predict</h3>
            <p className="step-desc">Our model weighs fatigue, goalie performance, injuries, streaks, and head-to-head history.</p>
          </div>
          <div className="step">
            <div className="step-number">3</div>
            <h3 className="step-title">Track</h3>
            <p className="step-desc">Every prediction is locked before game time and tracked for full transparency.</p>
          </div>
        </div>
      </section>
    </div>
  );
}

export default Home;
