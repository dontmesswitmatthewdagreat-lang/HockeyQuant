import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { fetchLatestDigests, fetchLeaguePulses, fetchTeams, fetchGames } from '../api';
import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import DigestCard from '../components/DigestCard';
import WireFeed from '../components/WireFeed';
import PulseDial from '../components/PulseDial';
import NewsAssistant from '../components/NewsAssistant';
import ArticleSummary from '../components/ArticleSummary';
import Reveal from '../components/Reveal';
import '../components/Dashboard.css';

/**
 * The front door: a news and statistics dashboard.
 *
 * Two reading columns — the day's edition on the left, the live wire on the
 * right — so the thing rewritten hourly and the thing written once a day are
 * legible at the same time rather than stacked a screen apart. League vitals
 * sit in a row beneath, where they don't compete with either.
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
  const [summaryArticle, setSummaryArticle] = useState(null);

  useEffect(() => {
    fetchLatestDigests().then((d) => setDigests(d.digests || [])).catch(() => setDigests([]));
    fetchLeaguePulses().then((d) => setPulses(d.pulses || [])).catch(() => {});
    fetchTeams().then(setTeams).catch(() => {});
    fetchGames(today()).then((d) => setGames(d.games || [])).catch(() => {});
  }, []);

  const lead = digests?.[0] || null;

  // The league-wide luck dial is deliberately not here: a single number for
  // how bouncy the whole league is doesn't tell a reader anything they can
  // act on. Per-team PDO, which does, lives on the team page instead. The
  // seasonal pulses still appear, but only once they're actually live —
  // a row of "back soon" placeholders is worse than an empty rail.
  const livePulses = pulses.filter((p) => p.id !== 'luck' && p.active);

  // Standings leaders, by points then points-percentage so a team with games
  // in hand isn't buried by one that's simply played more.
  const leaders = [...teams]
    .sort((a, b) => (b.points || 0) - (a.points || 0)
      || (b.points_pct || 0) - (a.points_pct || 0))
    .slice(0, 8);

  return (
    <div className="dash-page">
      <Reveal className="dash-masthead-wrap">
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
      </Reveal>

      <div className="dash-grid">
        {/* Left: the day's edition. */}
        <section className="dash-col dash-col-lead">
          {digests === null && <p className="dash-note">Loading the latest edition…</p>}
          {digests !== null && !lead && (
            <p className="dash-note">No edition published yet today.</p>
          )}
          <Reveal delay={80}>
            <DigestCard digest={lead} onSummarize={setSummaryArticle} />
          </Reveal>
        </section>

        {/* Middle: the live wire, scrolling alongside the edition. */}
        <section className="dash-col dash-col-wire">
          <Reveal delay={160}>
            <WireFeed onSummarize={setSummaryArticle} />
          </Reveal>
        </section>

      </div>

      {/* Beneath: league vitals, as a row. */}
      <aside className="dash-rail">
          {games.length > 0 && (
            <Reveal delay={240}>
              {/* The whole card is the link — a card that opens the games page
                  shouldn't need you to find the one phrase inside it that does. */}
              <Link className="dash-panel dash-slate-card" to="/games">
                <header className="dash-section-head">
                  <h2 className="dash-section-title">Tonight</h2>
                  <span className="dash-link">{games.length} games →</span>
                </header>
                <ul className="dash-slate">
                  {games.slice(0, 8).map((g) => (
                    <li key={`${g.away}-${g.home}`}>
                      {/* The away block is mirrored — abbreviation then crest —
                          so both crests sit against the @ and it reads as
                          centred between them rather than between the columns. */}
                      <span className="dash-slate-team dash-slate-away">
                        <img src={getTeamLogo(g.away)} alt="" />
                        {g.away}
                      </span>
                      <span className="dash-slate-at">@</span>
                      <span className="dash-slate-team dash-slate-home">
                        <img src={getTeamLogo(g.home)} alt="" />
                        {g.home}
                      </span>
                    </li>
                  ))}
                </ul>
              </Link>
            </Reveal>
          )}

          <Reveal delay={320}>
            <NewsAssistant />
          </Reveal>

          {leaders.length > 0 && (
            <Reveal delay={400}>
              <Link className="dash-panel dash-leaders-card" to="/teams">
                <header className="dash-section-head">
                  <h2 className="dash-section-title">League leaders</h2>
                  <span className="dash-link">Standings →</span>
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
              </Link>
            </Reveal>
          )}

        {livePulses.map((p, i) => (
          <Reveal key={p.id} delay={480 + i * 80}>
            <PulseDial pulse={p} />
          </Reveal>
        ))}
      </aside>

      {summaryArticle && (
        <ArticleSummary
          article={summaryArticle}
          onClose={() => setSummaryArticle(null)}
        />
      )}
    </div>
  );
}

export default Dashboard;
