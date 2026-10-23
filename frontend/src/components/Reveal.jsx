import { useEffect, useRef, useState } from 'react';
import './Dashboard.css';

/**
 * Fade-and-rise as a block enters the viewport — the Apple-style page entrance.
 *
 * One IntersectionObserver per block, disconnected the moment it fires: this
 * is an entrance, not a scroll-linked effect, so nothing should still be
 * observing after the page has settled. Blocks already in view on load fire
 * immediately and use `delay` to stagger down the page.
 *
 * `rootMargin` has a negative bottom so a block starts animating slightly
 * before it reaches the fold, rather than visibly popping once it's already
 * been read.
 */
function Reveal({ children, delay = 0, className = '' }) {
  const ref = useRef(null);
  // No observer means no way to detect entry, so show the content rather than
  // leaving it invisible forever.
  const [shown, setShown] = useState(() => typeof IntersectionObserver === 'undefined');

  useEffect(() => {
    if (shown) return undefined;
    const el = ref.current;
    if (!el) return undefined;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setShown(true);
          io.disconnect();
        }
      },
      { threshold: 0.08, rootMargin: '0px 0px -40px 0px' },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [shown]);

  return (
    <div
      ref={ref}
      className={`reveal ${shown ? 'is-revealed' : ''} ${className}`.trim()}
      style={{ '--reveal-delay': `${delay}ms` }}
    >
      {children}
    </div>
  );
}

export default Reveal;
