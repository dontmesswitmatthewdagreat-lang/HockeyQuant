/**
 * Returns the current "game day" date as a YYYY-MM-DD string.
 *
 * Uses Eastern Time (America/New_York) with a 6:00 AM cutoff:
 *   - Before 6 AM ET  → return the previous calendar day (last night's games)
 *   - 6 AM ET or later → return today's ET calendar date
 *
 * This prevents the app from switching to the next day at UTC midnight
 * (~7 PM ET), which happens mid-game.
 */
export function getGameDayDate() {
  const now = new Date();

  const etParts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York',
    year:   'numeric',
    month:  '2-digit',
    day:    '2-digit',
    hour:   '2-digit',
    hour12: false,
  }).formatToParts(now);

  const year  = parseInt(etParts.find(p => p.type === 'year').value);
  const month = parseInt(etParts.find(p => p.type === 'month').value) - 1; // 0-indexed
  const day   = parseInt(etParts.find(p => p.type === 'day').value);
  const hour  = parseInt(etParts.find(p => p.type === 'hour').value);

  // Build ET date object
  const etDate = new Date(year, month, day);

  // Before 6 AM ET → still the previous game day
  if (hour < 6) {
    etDate.setDate(etDate.getDate() - 1);
  }

  const y = etDate.getFullYear();
  const m = String(etDate.getMonth() + 1).padStart(2, '0');
  const d = String(etDate.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}
