import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { fetchDailyParlay } from '../api';
import { getTeamLogo } from '../utils/teamLogos';
import { getGameDayDate } from '../utils/dateUtils';
import './Home.css';

function formatParlayDate(dateStr) {
  const d = new Date(dateStr + 'T12:00:00');
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

function formatLegTime(isoStr) {
  if (!isoStr) return '';
  try {
    return new Date(isoStr).toLocaleTimeString('en-US', {
      hour: 'numeric', minute: '2-digit', timeZone: 'America/New_York', timeZoneName: 'short'
    });
  } catch { return ''; }
}

function Home() {
  const [parlay, setParlay] = useState(null);
  const [parlayLoading, setParlayLoading] = useState(true);

  useEffect(() => {
    fetchDailyParlay(getGameDayDate())
      .then(data => setParlay(data))
      .catch(() => setParlay(null))
      .finally(() => setParlayLoading(false));
  }, []);

  return (
    <div className="home-page">
      {/* Hero Section */}
      <section className="hero">
        <img src="/logo.png" alt="HockeyQuant" className="hero-logo" />
        <h1 className="hero-title">Unorthodox Predictions and Statistics</h1>
        <p className="hero-subtitle">
          Data-driven game predictions using real-time stats, goalie tracking, injury reports, and advanced analytics.
        </p>
        <div className="hero-actions">
          <Link to="/games" className="hero-btn primary">View Today's Games</Link>
          <Link to="/teams" className="hero-btn secondary">Explore Teams</Link>
        </div>
      </section>

      {/* Daily Parlay Card */}
      <section className="daily-parlay-section">
        <h2 className="section-heading">Today's Parlay</h2>
        <div className="parlay-card">
          {/* Red header bar */}
          <div className="parlay-card-header">
            <span className="parlay-card-title">Optimal Parlay</span>
            {!parlayLoading && parlay && parlay.num_legs > 0 && (
              <div className="parlay-card-badges">
                <span className="parlay-badge">{parlay.num_legs} {parlay.num_legs === 1 ? 'leg' : 'legs'}</span>
                <span className="parlay-badge">~{parlay.combined_prob}% to hit</span>
                <span className="parlay-badge">{formatParlayDate(getGameDayDate())}</span>
              </div>
            )}
          </div>

          {/* Loading skeleton */}
          {parlayLoading && (
            <div className="parlay-card-legs">
              {[1, 2, 3].map(i => (
                <div key={i} className="parlay-skeleton-leg">
                  <div className="skeleton-circle" />
                  <div className="skeleton-logo" />
                  <div className="skeleton-lines">
                    <div className="skeleton-line wide" />
                    <div className="skeleton-line narrow" />
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Empty / error state */}
          {!parlayLoading && (!parlay || parlay.num_legs === 0) && (
            <div className="parlay-card-empty">
              No games scheduled today — check back tomorrow.
            </div>
          )}

          {/* Legs */}
          {!parlayLoading && parlay && parlay.num_legs > 0 && (
            <>
              <div className="parlay-card-legs">
                {parlay.legs.map((leg, idx) => {
                  const isOU = leg.type === 'OU';
                  const barCls = leg.prob >= 65 ? 'bar-high' : leg.prob >= 58 ? 'bar-mid' : 'bar-low';
                  const typePill = leg.type === 'ML' ? 'type-ml' : leg.type === 'PL' ? 'type-pl' : 'type-ou';
                  const typeLabel = leg.type === 'ML' ? 'Moneyline' : leg.type === 'PL' ? 'Puck Line' : 'Over/Under';
                  const logoTeam = !isOU ? leg.pick : null;
                  return (
                    <div key={idx} className="parlay-home-leg">
                      <div className="leg-num">{idx + 1}</div>
                      {!isOU ? (
                        <img
                          src={getTeamLogo(logoTeam)}
                          alt={logoTeam}
                          className="leg-logo"
                          onError={e => { e.target.style.display = 'none'; }}
                        />
                      ) : (
                        <div className="leg-logos-ou">
                          <img src={getTeamLogo(leg.away_team)} alt={leg.away_team} onError={e => { e.target.style.display = 'none'; }} />
                          <img src={getTeamLogo(leg.home_team)} alt={leg.home_team} onError={e => { e.target.style.display = 'none'; }} />
                        </div>
                      )}
                      <div className="leg-body">
                        <div className="leg-top-row">
                          <span className="leg-pick-label">{leg.label}</span>
                          <span className={`leg-type-pill ${typePill}`}>{typeLabel}</span>
                          <span className="leg-prob-right">{leg.prob?.toFixed(1)}%</span>
                        </div>
                        <div className="leg-sub-row">
                          <span className="leg-matchup-text">
                            {leg.away_team} @ {leg.home_team}
                            {leg.game_time && <> &middot; {formatLegTime(leg.game_time)}</>}
                          </span>
                          <div className="leg-home-bar">
                            <div
                              className={`leg-home-bar-fill ${barCls}`}
                              style={{ width: `${Math.min(leg.prob || 0, 100)}%` }}
                            />
                          </div>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Combined probability */}
              <div className="parlay-combined-row">
                <div className="combined-row-label">
                  <span>Combined probability</span>
                  <span className="combined-row-pct">{parlay.combined_prob}%</span>
                </div>
                <div className="combined-row-bar">
                  <div
                    className="combined-row-bar-fill"
                    style={{ width: `${Math.min(parlay.combined_prob * 3, 100)}%` }}
                  />
                </div>
              </div>
            </>
          )}

          {/* Footer CTA */}
          <div className="parlay-card-footer">
            <Link to="/games" className="parlay-cta-btn">
              View All Games
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <polyline points="9 18 15 12 9 6"></polyline>
              </svg>
            </Link>
          </div>
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
