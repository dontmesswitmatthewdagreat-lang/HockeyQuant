-- HockeyQuant — Per-league draft pace (Rapid / Standard / Slow)
-- Run once in the Supabase SQL editor. Idempotent.

alter table public.fantasy_leagues
    add column if not exists draft_pace text not null default 'slow';

alter table public.fantasy_leagues
    add column if not exists pick_clock_seconds int not null default 21600;  -- 6h
