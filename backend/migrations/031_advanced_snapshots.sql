-- Daily snapshots of raw MoneyPuck season totals, for skaters and teams.
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Why this exists: MoneyPuck only ever serves *current cumulative* totals, and
-- the NHL per-game log carries none of these columns (no blocks, no faceoffs,
-- no on-ice shot attempts). So the only way to ever compute a windowed rate —
-- "Game Score per 60 over the last two weeks" — is to difference two snapshots.
-- That also means history cannot be backfilled: a day the cron doesn't run is a
-- day that can never be reconstructed.
--
-- These tables store RAW COUNTING COMPONENTS, never derived metrics. Game Score
-- weights and percentile baselines will be retuned; if the archive stored
-- `game_score`, every retune would silently invalidate its own history. Storing
-- the inputs means the entire archive can be recomputed under new weights —
-- the same reasoning that makes user_models.fork_count a cache of model_forks
-- rather than the source of truth.

create table if not exists skater_snapshots (
    id bigserial primary key,
    snap_date date not null,
    player_id bigint not null,
    name text not null,
    team text,
    position text,
    situation text not null,              -- 'all' | '5on5'
    games_played numeric,
    icetime numeric,                      -- seconds
    -- Game Score components
    i_f_goals numeric,
    i_f_primary_assists numeric,
    i_f_secondary_assists numeric,
    i_f_shots_on_goal numeric,
    i_f_xgoals numeric,
    shots_blocked_by_player numeric,
    penalties numeric,
    penalties_drawn numeric,
    faceoffs_won numeric,
    faceoffs_lost numeric,
    -- On-ice run of play
    on_ice_f_shot_attempts numeric,
    on_ice_a_shot_attempts numeric,
    on_ice_f_goals numeric,
    on_ice_a_goals numeric,
    on_ice_f_xgoals numeric,
    on_ice_a_xgoals numeric,
    off_ice_f_xgoals numeric,
    off_ice_a_xgoals numeric,
    unique (player_id, snap_date, situation)
);

create index if not exists idx_skater_snap_date on skater_snapshots (snap_date desc);
create index if not exists idx_skater_snap_player on skater_snapshots (player_id, snap_date desc);
create index if not exists idx_skater_snap_team on skater_snapshots (team, snap_date desc);

create table if not exists team_snapshots (
    id bigserial primary key,
    snap_date date not null,
    team text not null,
    situation text not null,              -- 'all' | '5on5' | '5on4' | '4on5' | 'other'
    games_played numeric,
    ice_time numeric,
    goals_for numeric,
    goals_against numeric,
    xgoals_for numeric,
    xgoals_against numeric,
    shot_attempts_for numeric,
    shot_attempts_against numeric,
    unblocked_shot_attempts_for numeric,
    unblocked_shot_attempts_against numeric,
    high_danger_xgoals_for numeric,
    high_danger_xgoals_against numeric,
    unique (team, snap_date, situation)
);

create index if not exists idx_team_snap_date on team_snapshots (snap_date desc);
create index if not exists idx_team_snap_team on team_snapshots (team, snap_date desc);

alter table skater_snapshots enable row level security;
alter table team_snapshots enable row level security;

-- Guarded so re-running the file doesn't error on an existing policy.
do $$
begin
    if not exists (select 1 from pg_policies
                   where tablename = 'skater_snapshots' and policyname = 'skater_snapshots read') then
        create policy "skater_snapshots read" on skater_snapshots for select using (true);
    end if;
    if not exists (select 1 from pg_policies
                   where tablename = 'team_snapshots' and policyname = 'team_snapshots read') then
        create policy "team_snapshots read" on team_snapshots for select using (true);
    end if;
end $$;

-- Writes stay service-key only: these are cron-populated and must not be
-- editable from the client.
