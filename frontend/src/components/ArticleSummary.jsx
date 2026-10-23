import { useEffect, useState } from 'react';
import { summarizeArticle } from '../api';
import './Dashboard.css';

/**
 * The sheet a press-and-hold opens: an AI summary of one article, so you can
 * decide whether it's worth leaving the page for.
 *
 * Summaries are cached per URL on the server, so holding the same story twice
 * is free. When a site blocks the scraper the backend falls back to the
 * headline and blurb rather than erroring, which is why those get sent too.
 */
function ArticleSummary({ article, onClose }) {
  const [summary, setSummary] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    summarizeArticle({
      url: article.url,
      headline: article.headline || '',
      blurb: article.blurb || '',
    })
      .then((d) => { if (!cancelled) setSummary(d); })
      .catch((e) => { if (!cancelled) setError(e.message); });
    return () => { cancelled = true; };
  }, [article]);

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content dash-summary" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="dash-close" onClick={onClose} aria-label="Close">×</button>

        <span className="dash-kicker">AI summary</span>
        <h3 className="dash-summary-headline">{article.headline}</h3>
        <div className="dash-story-meta">
          <span className="dash-story-source">{article.source}</span>
          {summary?.cached && <span className="dash-tag">cached</span>}
        </div>

        {!summary && !error && (
          <p className="dash-summary-body dash-summary-loading">Reading the article…</p>
        )}
        {error && <p className="dash-note">{error}</p>}
        {summary && <p className="dash-summary-body">{summary.summary}</p>}

        <a
          className="dash-summary-link"
          href={article.url}
          target="_blank"
          rel="noopener noreferrer"
        >
          Read the full article →
        </a>
      </div>
    </div>
  );
}

export default ArticleSummary;
