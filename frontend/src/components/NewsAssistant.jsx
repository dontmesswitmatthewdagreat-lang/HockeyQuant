import { useRef, useState } from 'react';
import { searchNews } from '../api';
import './Dashboard.css';

/**
 * Ask-the-archive: a question goes to /api/news/search, which runs the model
 * over live news for that query and separately full-text searches every stored
 * article and blurb.
 *
 * The model is instructed to answer only from the supplied items and to cite
 * them by index, and the links are reconstructed from the real items rather
 * than from anything the model wrote — so a cited source is always a story
 * that exists. Answers are grounded in reporting, not the model's own memory
 * of hockey, which also means "I couldn't find recent news on that" is a
 * correct answer rather than a failure.
 *
 * Each turn is independent server-side; the thread here is for the reader.
 */

const SUGGESTIONS = [
  'Who got traded this week?',
  'Which goalies are injured?',
  'What is PDO?',
];

function NewsAssistant() {
  const [thread, setThread] = useState([]);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const idRef = useRef(0);

  async function ask(question) {
    const q = question.trim();
    if (q.length < 2 || busy) return;
    idRef.current += 1;
    const id = idRef.current;
    setThread((t) => [...t, { id, q, pending: true }]);
    setDraft('');
    setBusy(true);
    try {
      const data = await searchNews(q);
      setThread((t) => t.map((turn) => (turn.id === id
        ? {
          ...turn,
          pending: false,
          answer: data.answer,
          // `sources` are the live items the answer actually cited; the
          // archive matches are extra reading, so only the cited ones are
          // shown under the answer.
          sources: (data.sources || []).slice(0, 4),
        }
        : turn)));
    } catch {
      setThread((t) => t.map((turn) => (turn.id === id
        ? { ...turn, pending: false, error: 'Could not reach the news desk.' }
        : turn)));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="dash-panel dash-assistant">
      <header className="dash-section-head">
        <h2 className="dash-section-title">Ask the archive</h2>
      </header>
      <p className="dash-note dash-assistant-blurb">
        Answers come from stored and live reporting, not the model&rsquo;s own
        recall — so it will say when it doesn&rsquo;t know.
      </p>

      {thread.length === 0 && (
        <div className="dash-suggestions">
          {SUGGESTIONS.map((s) => (
            <button key={s} type="button" className="dash-suggestion" onClick={() => ask(s)}>
              {s}
            </button>
          ))}
        </div>
      )}

      <div className="dash-thread">
        {thread.map((turn) => (
          <div key={turn.id} className="dash-turn">
            <p className="dash-turn-q">{turn.q}</p>
            {turn.pending && <p className="dash-turn-a dash-summary-loading">Reading the wire…</p>}
            {turn.error && <p className="dash-turn-a dash-turn-error">{turn.error}</p>}
            {turn.answer && (
              <>
                <p className="dash-turn-a">{turn.answer}</p>
                {turn.sources?.length > 0 && (
                  <ul className="dash-turn-sources">
                    {turn.sources.map((s) => (
                      <li key={s.url || s.title}>
                        <a href={s.url} target="_blank" rel="noopener noreferrer">
                          {s.title || s.headline}
                        </a>
                        {s.source && <span className="dash-turn-src">{s.source}</span>}
                      </li>
                    ))}
                  </ul>
                )}
              </>
            )}
          </div>
        ))}
      </div>

      <form
        className="dash-ask"
        onSubmit={(e) => { e.preventDefault(); ask(draft); }}
      >
        <input
          type="text"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Ask about any player, team or stat…"
          aria-label="Ask the news archive"
        />
        <button type="submit" disabled={busy || draft.trim().length < 2}>
          {busy ? '…' : 'Ask'}
        </button>
      </form>
    </section>
  );
}

export default NewsAssistant;
