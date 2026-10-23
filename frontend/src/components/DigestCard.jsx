import useLongPress from './useLongPress';
import './Dashboard.css';

/**
 * The league digest — the dashboard's lead story.
 *
 * Editions are written through the day (morning, midday, afternoon, evening)
 * and each one excludes anything featured in the last 72 hours, so a later
 * edition is genuinely new rather than the same stories reshuffled. The kind
 * is surfaced because "Evening" after the games are final means something
 * different from "Morning".
 */

const KIND_LABEL = {
  morning: 'Morning edition',
  midday: 'Midday edition',
  afternoon: 'Afternoon edition',
  evening: 'Nightcap',
  pregame: 'Pre-game',
  postgame: 'Post-game',
};

const TAG_TONE = {
  Injury: 'tag-injury',
  Trade: 'tag-trade',
  Rumor: 'tag-rumor',
  Recap: 'tag-recap',
  Signing: 'tag-signing',
};

function timeAgo(iso) {
  if (!iso) return null;
  const then = new Date(iso);
  if (Number.isNaN(then.getTime())) return null;
  const mins = Math.round((Date.now() - then.getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.round(hrs / 24)}d ago`;
}

/** Own component per story so each can hold its own press-and-hold timer. */
function StoryCard({ item, onSummarize }) {
  const press = useLongPress(() => onSummarize(item));
  return (
    <a
      className="dash-story"
      href={item.url}
      target="_blank"
      rel="noopener noreferrer"
      title="Hold to summarize"
      {...press}
    >
      {item.image_url && item.image_url !== 'None' && (
        <div className="dash-story-media">
          <img src={item.image_url} alt="" loading="lazy" draggable="false" />
        </div>
      )}
      <div className="dash-story-body">
        <div className="dash-story-meta">
          {item.tag && (
            <span className={`dash-tag ${TAG_TONE[item.tag] || ''}`}>{item.tag}</span>
          )}
          <span className="dash-story-source">{item.source}</span>
          {timeAgo(item.published_at) && (
            <span className="dash-story-time">· {timeAgo(item.published_at)}</span>
          )}
        </div>
        <h3 className="dash-story-headline">{item.headline}</h3>
        {item.blurb && <p className="dash-story-blurb">{item.blurb}</p>}
      </div>
    </a>
  );
}

function DigestCard({ digest, onSummarize }) {
  if (!digest) return null;
  const items = digest.items || [];
  const keyPoints = digest.key_points || [];

  return (
    <section className="dash-digest">
      <header className="dash-digest-head">
        <div>
          <span className="dash-kicker">
            {KIND_LABEL[digest.kind] || 'Latest edition'}
          </span>
          <h2 className="dash-digest-title">{digest.title}</h2>
        </div>
        <div className="dash-digest-stamp">
          <span className="dash-digest-date">{digest.digest_date}</span>
          {/* Editions are rewritten through the day, so "which edition" isn't
              enough — when it last ran is what tells you if it's stale. */}
          {digest.created_at && (
            <span className="dash-digest-updated" title={new Date(digest.created_at).toLocaleString()}>
              Updated {timeAgo(digest.created_at)} ·{' '}
              {new Date(digest.created_at).toLocaleTimeString([], {
                hour: 'numeric', minute: '2-digit',
              })}
            </span>
          )}
        </div>
      </header>

      {digest.intro && <p className="dash-digest-intro">{digest.intro}</p>}

      {keyPoints.length > 0 && (
        <div className="dash-rapid">
          <span className="dash-kicker">Rapid digest</span>
          <ul className="dash-rapid-list">
            {/* Key points are plain strings with no id of their own, and the
                whole list is replaced when a new edition lands, so position
                is a stable enough key here. */}
            {keyPoints.map((point, i) => (
              <li key={`${digest.id}-${i}`}>{point}</li>
            ))}
          </ul>
        </div>
      )}

      {items.length > 0 && (
        <div className="dash-stories">
          {items.map((item) => (
            <StoryCard key={item.url} item={item} onSummarize={onSummarize} />
          ))}
        </div>
      )}
    </section>
  );
}

export default DigestCard;
