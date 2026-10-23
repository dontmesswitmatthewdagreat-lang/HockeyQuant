import { useCallback, useRef, useState } from 'react';

/**
 * Press-and-hold on a news card to summarize it, ported from the iOS gesture
 * (`HoldToSummarize`): the card shrinks slightly, a gradient ring lights up,
 * and after the delay it fires.
 *
 * The awkward part on the web is that the thing being held is a link. A hold
 * has to open the summary *without* also following the href when the finger
 * or button comes up, and on touch it has to pre-empt the browser's own
 * long-press menu. So the hook tracks whether the hold actually fired and
 * swallows exactly one subsequent click.
 *
 * Returns `{ holding, handlers }` — `holding` drives the press animation,
 * `handlers` spread onto the element.
 *
 * HOLD_MS matches iOS's 0.6s minimumDuration so the two feel the same.
 */
export const HOLD_MS = 600;

export default function useLongPress(onLongPress, { delay = HOLD_MS } = {}) {
  const timer = useRef(null);
  const fired = useRef(false);
  const origin = useRef({ x: 0, y: 0 });
  const [holding, setHolding] = useState(false);

  const clear = useCallback(() => {
    if (timer.current) {
      clearTimeout(timer.current);
      timer.current = null;
    }
    setHolding(false);
  }, []);

  const start = useCallback((e) => {
    // Primary button / touch only: a right-click should still open the menu.
    if (e.button !== undefined && e.button !== 0) return;
    origin.current = { x: e.clientX, y: e.clientY };
    fired.current = false;
    if (timer.current) clearTimeout(timer.current);
    setHolding(true);
    timer.current = setTimeout(() => {
      fired.current = true;
      timer.current = null;
      setHolding(false);
      onLongPress();
    }, delay);
  }, [onLongPress, delay]);

  // A drag is a scroll, not a hold — bail once the pointer has really moved.
  const move = useCallback((e) => {
    if (!timer.current) return;
    const dx = Math.abs(e.clientX - origin.current.x);
    const dy = Math.abs(e.clientY - origin.current.y);
    if (dx > 10 || dy > 10) clear();
  }, [clear]);

  const click = useCallback((e) => {
    if (fired.current) {
      // The hold already did something; don't also navigate away.
      e.preventDefault();
      e.stopPropagation();
      fired.current = false;
    }
  }, []);

  const contextMenu = useCallback((e) => {
    // Touch long-press raises contextmenu mid-hold, which would cover the
    // summary with the browser's own sheet.
    if (timer.current || fired.current) e.preventDefault();
  }, []);

  return {
    holding,
    handlers: {
      onPointerDown: start,
      onPointerUp: clear,
      onPointerLeave: clear,
      onPointerCancel: clear,
      onPointerMove: move,
      onClick: click,
      onContextMenu: contextMenu,
    },
  };
}
