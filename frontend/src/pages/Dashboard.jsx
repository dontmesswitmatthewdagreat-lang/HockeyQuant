import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { fetchLatestDigests, fetchLeaguePulses, fetchTeams, fetchGames } from '../api';
import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import DigestCard from '../components/DigestCard';
import WireFeed from '../components/WireFeed';
import PulseDial from '../components/PulseDial';
import '../components/Dashboard.css';

/**
 * The front door: a news and statistics dashboard.
 *
 * Every section loads independently and renders nothing until its own fetch
 * lands. The backend is on a free tier that cold-starts, and one slow or
 * failed call should cost its own card rather than hold the whole page on a
 * spinner — the digest is usually the first thing to arrive and is the only
 * thing most visits are here for.
 */

function today() {
  return new Date().toLocaleDateString('en-CA'); // YYYY-MM-DD, local
}

function Dashboard() {
  const [digests, setDigests] = useState(null);
  const [pulses, setPulses] = useState([]);
  const [teams, setTeams] = useState([]);
  const [games, setGames] = useState([]);

  useEffect(() => {
    fetchLatestDigests().then((d) => setDigests(d.digests || [])).catch(() => setDigests([]));
    fetchLeaguePulses().then((d) => setPulses(d.pulses || [])).catch(() => {});
    fetchTeams().then(setTeams).catch(() => {});
    fetchGames(today()).then((d) => setGames(d.games || [])).catch(() => {});
  }, []);

  const lead = digests?.[0] || null;
  const luck = pulses.find((p) => p.id === 'luck') || null;
  const others = pulses.filter((p) => p.id !== 'luck');

  // Standings leaders, by points then points-percentage so a team with games
  // in hand isn't buried by one that's simply played more.
  const leaders = [...teams]
    .sort((a, b) => (b.points || 0) - (a.points || 0)
      || (b.points_pct || 0) - (a.points_pct || 0))
    .slice(0, 8);

  return (
    <div className="dash-page">
      <header className="dash-masthead">
        <div>
          <h1 className="dash-title">The Rink Report</h1>
          <p className="dash-sub">NHL news, numbers and what they actually mean</p>
        </div>
        <span className="dash-today">
          {new Date().toLocaleDateString(undefined, {
            weekday: 'long', month: 'long', day: 'numeric',
          })}
        </span>
      </header>

      <div className="dash-grid">
        <main className="dash-main">
          {digests === null && <p className="dash-note">Loading the latest edition…</p>}
          {digests !== null && !lead && (
            <p className="dash-note">No edition published yet today.</p>
          )}
          <DigestCard digest={lead} />
          <WireFeed />
        </main>

        <aside className="dash-side">
          {games.length > 0 && (
            <section className="dash-panel">
              <header className="dash-section-head">
                <h2 className="dash-section-title">Tonight</h2>
                <Link className="dash-link" to="/games">All games →</Link>
              </header>
              <ul className="dash-slate">
                {/* /api/games returns bare abbreviations as `away`/`home` —
                    not the `away_team`/`home_team` shape the prediction
                    endpoints use. */}
                {games.slice(0, 8).map((g) => (
                  <li key={`${g.away}-${g.home}`}>
                    <span className="dash-slate-team">
                      <img src={getTeamLogo(g.away)} alt="" />
                      {g.away}
                    </span>
                    <span className="dash-slate-at">@</span>
                    <span className="dash-slate-team">
                      <img src={getTeamLogo(g.home)} alt="" />
                      {g.home}
                    </span>
                  </li>
                ))}
              </ul>
            </section>
          )}

          {luck && <PulseDial pulse={luck} />}

          {leaders.length > 0 && (
            <section className="dash-panel">
              <header className="dash-section-head">
                <h2 className="dash-section-title">League leaders</h2>
                <Link className="dash-link" to="/teams">Standings →</Link>
              </header>
              <ol className="dash-leaders">
                {leaders.map((t, i) => (
                  <li key={t.abbrev}>
                    <span className="dash-leader-rank">{i + 1}</span>
                    <img src={getTeamLogo(t.abbrev)} alt="" />
                    <span className="dash-leader-name">{getTeamName(t.abbrev) || t.abbrev}</span>
                    <span className="dash-leader-pts">{t.points}</span>
                  </li>
                ))}
              </ol>
            </section>
          )}

          {others.map((p) => <PulseDial key={p.id} pulse={p} />)}
        </aside>
      </div>
    </div>
  );
}

export default Dashboard;
