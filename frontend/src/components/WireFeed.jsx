import { useCallback, useEffect, useState } from 'react';
import { fetchNewsFeed } from '../api';
import './Dashboard.css';

/**
 * The Wire — the flat chronological archive of everything ingested, mixing
 * full articles and short blurbs.
 *
 * Keyset-paginated rather than offset-paginated: the ingest cron writes new
 * rows continuously, and an offset would silently repeat or skip items as the
 * list shifts underneath you. The cursor is an opaque
 * `published_at|id` string the server hands back.
 */

function timeAgo(iso) {
  if (!iso) return null;
  const then = new Date(iso);
  if (Number.isNaN(then.getTime())) return null;
  const mins = Math.round((Date.now() - then.getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  return `${Math.round(hrs / 24)}d`;
}

const FILTERS = [
  { id: null, label: 'Everything' },
  { id: 'article', label: 'Articles' },
  { id: 'blurb', label: 'Blurbs' },
];

function WireFeed() {
  const [items, setItems] = useState([]);
  const [cursor, setCursor] = useState(null);
  const [kind, setKind] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState(null);

  const load = useCallback(async (nextKind) => {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchNewsFeed({ kind: nextKind, limit: 24 });
      setItems(data.items || []);
      setCursor(data.next_cursor || null);
    } catch {
      setError('The wire is unreachable right now.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load(kind);
  }, [kind, load]);

  async function loadMore() {
    if (!cursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const data = await fetchNewsFeed({ kind, cursor, limit: 24 });
      // Append rather than replace, and de-dupe by id: a row ingested between
      // the two requests can legitimately appear in both pages.
      setItems((prev) => {
        const seen = new Set(prev.map((i) => i.id));
        return [...prev, ...(data.items || []).filter((i) => !seen.has(i.id))];
      });
      setCursor(data.next_cursor || null);
    } catch {
      setError('Could not load more.');
    } finally {
      setLoadingMore(false);
    }
  }

  return (
    <section className="dash-wire">
      <header className="dash-section-head">
        <h2 className="dash-section-title">The Wire</h2>
        <div className="dash-filters">
          {FILTERS.map((f) => (
            <button
              key={f.label}
              type="button"
              className={kind === f.id ? 'dash-filter active' : 'dash-filter'}
              onClick={() => setKind(f.id)}
            >
              {f.label}
            </button>
          ))}
        </div>
      </header>

      {error && <p className="dash-note">{error}</p>}
      {loading && <p className="dash-note">Loading the wire…</p>}

      {!loading && items.length === 0 && !error && (
        <p className="dash-note">Nothing on the wire yet.</p>
      )}

      <ul className="dash-wire-list">
        {items.map((item) => (
          <li key={item.id}>
            <a
              className="dash-wire-item"
              href={item.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              <div className="dash-wire-main">
                <div className="dash-story-meta">
                  {item.tag && <span className="dash-tag">{item.tag}</span>}
                  <span className="dash-story-source">{item.source}</span>
                  {item.team && item.team !== 'None' && (
                    <span className="dash-wire-team">{item.team}</span>
                  )}
                </div>
                <h4 className="dash-wire-headline">{item.headline}</h4>
                {item.blurb && <p className="dash-wire-blurb">{item.blurb}</p>}
              </div>
              <span className="dash-wire-time">{timeAgo(item.published_at)}</span>
            </a>
          </li>
        ))}
      </ul>

      {cursor && !loading && (
        <button
          type="button"
          className="dash-more"
          onClick={loadMore}
          disabled={loadingMore}
        >
          {loadingMore ? 'Loading…' : 'Load more'}
        </button>
      )}
    </section>
  );
}

export default WireFeed;
