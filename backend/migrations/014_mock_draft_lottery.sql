-- HockeyQuant — Draft lottery odds on the weekly mock draft
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Each weekly mock draft now carries the draft-lottery odds (chance at the No. 1
-- pick) for the 16 non-playoff teams, computed from current standings. The app
-- shows these as a bar chart during the regular season; once the order goes
-- official (NHL API / post-lottery reporting) the card flips to the results.

alter table public.mock_drafts
    add column if not exists lottery_odds jsonb not null default '[]';
    -- [{abbrev, team_name, odds, draft_slot, points, games_played}], worst record first
