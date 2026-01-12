import { Link } from 'react-router-dom';
import './Home.css';

function Home() {
  return (
    <div className="home">
      <div className="hero">
        <img src="/logo.png" alt="HockeyQuant" className="hero-logo" />
        <h1 className="hero-title">HOCKEY<span className="highlight">QUANT</span></h1>
        <p className="hero-subtitle">NHL Game Prediction Engine</p>
      </div>

      <div className="nav-cards">
        <Link to="/predictions" className="nav-card">
          <span className="card-icon">📊</span>
          <h3 className="card-title">Run Model</h3>
          <p className="card-desc">Analyze today's NHL matchups</p>
        </Link>

        <div className="nav-card disabled">
          <span className="card-icon">🔧</span>
          <h3 className="card-title">Custom Models</h3>
          <p className="card-desc">Build & explore prediction models</p>
          <span className="coming-soon">Coming Soon</span>
        </div>

        <Link to="/teams" className="nav-card">
          <span className="card-icon">📈</span>
          <h3 className="card-title">Stats</h3>
          <p className="card-desc">Team & player statistics</p>
        </Link>

        <div className="nav-card disabled">
          <span className="card-icon">🏆</span>
          <h3 className="card-title">Leaderboard</h3>
          <p className="card-desc">Compare model accuracy</p>
          <span className="coming-soon">Coming Soon</span>
        </div>
      </div>

      <footer className="home-footer">
        <p>Data: MoneyPuck.com | Injuries: ESPN.com | Schedule: NHL API</p>
      </footer>
    </div>
  );
}

export default Home;
