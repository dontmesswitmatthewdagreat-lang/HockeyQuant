import { useEffect, useRef, useState } from 'react';

/**
 * Reveals text as if it were being written.
 *
 * Driven by requestAnimationFrame against elapsed time rather than a
 * setInterval per character: an interval drifts under load and ties the pace
 * to the frame budget, which on a slow render reads as stuttering rather than
 * typing. Characters-per-second stays honest here however long a frame takes.
 *
 * Returns `{ shown, done }`. When the reader prefers reduced motion the whole
 * string is returned immediately — a typing effect is decorative, and the one
 * thing it must never do is withhold the content.
 */
export default function useTypewriter(text, { cps = 180 } = {}) {
  // Read once, lazily. Checking inside the effect would mean setting state
  // synchronously during it, which cascades an extra render on every mount.
  const [reduced] = useState(() => (
    typeof window !== 'undefined'
    && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  ));
  const [shown, setShown] = useState('');
  const frame = useRef(0);

  useEffect(() => {
    if (!text || reduced) return undefined;
    const started = performance.now();
    const tick = (now) => {
      const chars = Math.floor(((now - started) / 1000) * cps);
      if (chars >= text.length) {
        setShown(text);
        return;
      }
      setShown(text.slice(0, chars));
      frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame.current);
  }, [text, cps, reduced]);

  if (!text) return { shown: '', done: true };
  if (reduced) return { shown: text, done: true };
  // Between a new `text` arriving and the first frame, `shown` still holds the
  // previous string. Deriving rather than storing the reset keeps that stale
  // frame from flashing the old summary under the new headline.
  const safe = text.startsWith(shown) ? shown : '';
  return { shown: safe, done: safe === text };
}
