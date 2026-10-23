/**
 * What a card shows while it's being held: the rotating gradient ring and the
 * "Hold for AI summary" chip from the iOS `HoldToSummarize` modifier.
 *
 * Rendered as a sibling overlay rather than a border so it can't shift the
 * card's layout mid-press, and marked aria-hidden because it is pure feedback
 * for a gesture the keyboard never performs.
 */
function HoldAffordance() {
  return (
    <>
      <span className="dash-hold-ring" aria-hidden="true" />
      <span className="dash-hold-chip" aria-hidden="true">
        <span className="dash-hold-spark">✦</span>
        Hold for AI summary
      </span>
    </>
  );
}

export default HoldAffordance;
