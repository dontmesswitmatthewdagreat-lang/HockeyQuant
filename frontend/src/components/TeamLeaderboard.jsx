import { useState, useEffect } from 'react';
import { fetchAccuracyLeaderboard } from '../api';
import { getTeamLogo, getTeamName } from '../utils/teamLogos';
import './TeamLeaderboard.css';

function TeamLeaderboard({ selectedTeam, onSelectTeam }) {
  const [leaderboard, setLeaderboard] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    async function load() {
      setLoading(true);
      setError(null);
      try {
        const data = await fetchAccuracyLeaderboard();
        setLeaderboard(data);
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    load();
  }, []);

  function handleRowClick(abbrev) {
    onSelectTeam(selectedTeam === abbrev ? '' : abbrev);
  }

  // Determine color thresholds: top third = green, bottom third = red
  function getPctClass(pct, allPcts) {
    if (pct == null || allPcts.length < 3) return '';
    const sorted = [...allPcts].sort((a, b) => a - b);
    const low = sorted[Math.floor(sorted.length / 3)];
    const high = sorted[Math.floor((sorted.length * 2) / 3)];
    if (pct >= high) return 'best';
    if (pct <= low) return 'worst';
    return '';
  }

  const allMlPcts = leaderboard.map((t) => t.ml_pct);

  return (
    <div className="leaderboard-section">
      <h2 className="section-title">Team Prediction Leaderboard</h2>
      <p className="leaderboard-hint">
        <strong>Correct Outcome</strong>: model accuracy in all games involving this team (win or lose). <strong>As Win Prediction</strong>: accuracy when this team was the model's predicted winner. Click any row to filter stats above.
        {selectedTeam && (
          <> Click the highlighted row again to clear.</>
        )}
      </p>

      {loading && <p className="leaderboard-loading">Loading leaderboard...</p>}
      {!loading && error && <p className="leaderboard-error">Error loading leaderboard: {error}</p>}

      {!loading && !error && leaderboard.length > 0 && (
        <div className="leaderboard-table-container">
          <table className="leaderboard-table">
            <thead>
              <tr>
                <th className="rank-th">#</th>
                <th>Team</th>
                <th className="num-th">Games</th>
                <th className="num-th" title="How often the model was correct in games involving this team">Correct Outcome</th>
                <th className="num-th" title="How often the model was correct when it picked this team to win">As Win Prediction</th>
                <th className="num-th">Puck Line</th>
                <th className="num-th">O/U</th>
              </tr>
            </thead>
            <tbody>
              {leaderboard.map((entry, idx) => {
                const isSelected = selectedTeam === entry.team;
                const mlClass = getPctClass(entry.ml_pct, allMlPcts);
                return (
                  <tr
                    key={entry.team}
                    className={`leaderboard-row${isSelected ? ' selected' : ''}`}
                    onClick={() => handleRowClick(entry.team)}
                  >
                    <td className="rank-num">{idx + 1}</td>
                    <td>
                      <div className="lb-team-cell">
                        <img
                          src={getTeamLogo(entry.team)}
                          alt={entry.team}
                          className="lb-logo"
                          onError={(e) => { e.target.style.display = 'none'; }}
                        />
                        <span className="lb-team-name">{getTeamName(entry.team)}</span>
                      </div>
                    </td>
                    <td className="num-cell">
                      <span className="lb-count">{entry.ml_total}</span>
                    </td>
                    <td className="num-cell">
                      <span className={`lb-pct ${mlClass}`}>
                        {entry.ml_pct.toFixed(1)}%
                      </span>
                      <span className="lb-sub">{entry.ml_correct}/{entry.ml_total}</span>
                    </td>
                    <td className="num-cell">
                      {entry.pick_pct != null ? (
                        <>
                          <span className="lb-pct">{entry.pick_pct.toFixed(1)}%</span>
                          <span className="lb-sub">{entry.pick_correct}/{entry.pick_total}</span>
                        </>
                      ) : (
                        <span className="lb-dash">—</span>
                      )}
                    </td>
                    <td className="num-cell">
                      {entry.pl_pct != null ? (
                        <>
                          <span className="lb-pct">{entry.pl_pct.toFixed(1)}%</span>
                          <span className="lb-sub">{entry.pl_correct}/{entry.pl_total}</span>
                        </>
                      ) : (
                        <span className="lb-dash">—</span>
                      )}
                    </td>
                    <td className="num-cell">
                      {entry.ou_pct != null ? (
                        <>
                          <span className="lb-pct">{entry.ou_pct.toFixed(1)}%</span>
                          <span className="lb-sub">{entry.ou_correct}/{entry.ou_total}</span>
                        </>
                      ) : (
                        <span className="lb-dash">—</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

export default TeamLeaderboard;
