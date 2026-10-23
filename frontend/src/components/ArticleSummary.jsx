import { useEffect, useState } from 'react';
import { summarizeArticle } from '../api';
import useTypewriter from './useTypewriter';
import './Dashboard.css';

/**
 * What the sheet shows while the model reads: a breathing spark and four
 * shimmer bars, the same shape as the summary that replaces them so the
 * layout doesn't jump when it lands. Ported from the iOS sheet's pulsing
 * `sparkles` symbol over `LoadingShimmer` rows.
 */
function SummarySkeleton() {
  return (
    <div className="dash-reading">
      <div className="dash-reading-head">
        <span className="dash-reading-spark">✦</span>
        <span>Reading the article…</span>
      </div>
      {/* The short last bar is what makes it read as a paragraph. */}
      {['100%', '100%', '100%', '62%'].map((w, i) => (
        <span
          key={w + i}
          className="dash-shimmer"
          style={{ width: w, animationDelay: `${i * 0.12}s` }}
        />
      ))}
    </div>
  );
}

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
  // A cached summary returns almost instantly, so the typing is what gives the
  // answer a sense of being produced rather than simply appearing.
  const { shown: typed, done } = useTypewriter(summary?.summary || '');

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

        {!summary && !error && <SummarySkeleton />}
        {error && <p className="dash-note">{error}</p>}
        {summary && (
          <p className="dash-summary-body">
            {typed}
            {!done && <span className="dash-caret" aria-hidden="true" />}
          </p>
        )}

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
