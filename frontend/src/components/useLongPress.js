import { useCallback, useRef } from 'react';

/**
 * Press-and-hold on a news card to summarize it, ported from the iOS gesture.
 *
 * The awkward part on the web is that the thing being held is a link. A hold
 * has to open the summary *without* also following the href when the finger
 * or button comes up, and on touch it has to pre-empt the browser's own
 * long-press menu. So the hook tracks whether the hold actually fired and
 * swallows exactly one subsequent click.
 *
 * Returns props to spread onto the element. `delay` is 450ms: long enough not
 * to fire on a normal click, short enough not to feel broken.
 */
export default function useLongPress(onLongPress, { delay = 450 } = {}) {
  const timer = useRef(null);
  const fired = useRef(false);
  const origin = useRef({ x: 0, y: 0 });

  const clear = useCallback(() => {
    if (timer.current) {
      clearTimeout(timer.current);
      timer.current = null;
    }
  }, []);

  const start = useCallback((e) => {
    // Primary button / touch only: a right-click should still open the menu.
    if (e.button !== undefined && e.button !== 0) return;
    origin.current = { x: e.clientX, y: e.clientY };
    fired.current = false;
    clear();
    timer.current = setTimeout(() => {
      fired.current = true;
      onLongPress();
    }, delay);
  }, [onLongPress, delay, clear]);

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
    onPointerDown: start,
    onPointerUp: clear,
    onPointerLeave: clear,
    onPointerCancel: clear,
    onPointerMove: move,
    onClick: click,
    onContextMenu: contextMenu,
  };
}
