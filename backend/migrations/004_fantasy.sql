-- HockeyQuant — Fantasy League schema
-- Run once in the Supabase SQL editor (Dashboard → SQL → New query → paste → Run).
-- Safe to re-run (idempotent where practical).
--
-- Design notes:
--   * ALL fantasy operations go through the FastAPI backend (service key), which
--     bypasses RLS. RLS is enabled on every table and clients get NO write access;
--     the `players` pool is the only client-readable table (public draft board).
--   * Roster is positional: 2 LW, 2 RW, 2 C, 2 LHD, 2 RHD, 1 starting G, 1 backup G.
--     Defense is split by handedness (LHD = shoots L, RHD = shoots R).
--   * Group leagues use a unique player pool (no duplicates); the global league
--     allows duplicate players across teams. Uniqueness is enforced in the draft
--     engine (backend), not by a DB constraint (it differs per league type).
--   * Weekly scoring + grading run server-side (backend cron), mirroring the
--     existing prediction-grading pattern.

-- ---------------------------------------------------------------------------
-- Player pool (synced from the NHL API by the backend)
-- ---------------------------------------------------------------------------

create table if not exists public.fantasy_players (
    id          uuid primary key default gen_random_uuid(),
    nhl_id      bigint unique not null,
    full_name   text not null,
    team        text not null,                 -- current team abbrev
    position    text not null,                 -- C | L | R | D | G  (NHL positionCode)
    shoots      text,                           -- L | R
    roster_pos  text not null,                 -- LW | RW | C | LHD | RHD | G  (slot eligibility)
    is_goalie   boolean not null default false,
    sweater     int,
    headshot    text,
    active      boolean not null default true,
    updated_at  timestamptz not null default now()
);

create index if not exists fantasy_players_rosterpos_idx on public.fantasy_players (roster_pos) where active;
create index if not exists fantasy_players_team_idx on public.fantasy_players (team);

-- ---------------------------------------------------------------------------
-- Leagues + membership
-- ---------------------------------------------------------------------------

create table if not exists public.fantasy_leagues (
    id                      uuid primary key default gen_random_uuid(),
    name                    text not null,
    commissioner_id         uuid not null references auth.users(id) on delete cascade,
    league_type             text not null default 'group',   -- group | global
    status                  text not null default 'open',     -- open | drafting | active | playoffs | complete
    max_members             int not null default 12,
    unique_players          boolean not null default true,    -- group=true (no dupes); global=false
    trade_deadline_enabled  boolean not null default true,
    invite_code             text unique not null,
    season_year             int not null,
    draft_started_at        timestamptz,
    created_at              timestamptz not null default now()
);

create table if not exists public.fantasy_members (
    id          uuid primary key default gen_random_uuid(),
    league_id   uuid not null references public.fantasy_leagues(id) on delete cascade,
    user_id     uuid not null references auth.users(id) on delete cascade,
    team_name   text not null,
    draft_order int,                             -- assigned when the draft starts
    joined_at   timestamptz not null default now(),
    unique (league_id, user_id)
);

create index if not exists fantasy_members_league_idx on public.fantasy_members (league_id);
create index if not exists fantasy_members_user_idx on public.fantasy_members (user_id);

-- ---------------------------------------------------------------------------
-- Rosters (12 slots per member)
-- ---------------------------------------------------------------------------

create table if not exists public.fantasy_roster_slots (
    id          uuid primary key default gen_random_uuid(),
    league_id   uuid not null references public.fantasy_leagues(id) on delete cascade,
    member_id   uuid not null references public.fantasy_members(id) on delete cascade,
    slot        text not null,                  -- LW1,LW2,RW1,RW2,C1,C2,LHD1,LHD2,RHD1,RHD2,G_START,G_BACKUP
    slot_type   text not null,                  -- LW | RW | C | LHD | RHD | G
    player_id   uuid references public.fantasy_players(id) on delete set null,
    unique (league_id, member_id, slot)
);

create index if not exists fantasy_roster_member_idx on public.fantasy_roster_slots (member_id);
create index if not exists fantasy_roster_league_idx on public.fantasy_roster_slots (league_id);

-- ---------------------------------------------------------------------------
-- Draft (server-authoritative state machine)
-- ---------------------------------------------------------------------------

create table if not exists public.fantasy_draft_state (
    league_id           uuid primary key references public.fantasy_leagues(id) on delete cascade,
    status              text not null default 'not_started',  -- not_started | in_progress | complete
    current_pick_number int not null default 0,
    current_member_id   uuid references public.fantasy_members(id) on delete set null,
    required_slot_type  text,                    -- the lottery-assigned slot the on-the-clock manager must fill
    total_picks         int not null default 0,
    round               int not null default 0,
    updated_at          timestamptz not null default now()
);

create table if not exists public.fantasy_draft_picks (
    id          uuid primary key default gen_random_uuid(),
    league_id   uuid not null references public.fantasy_leagues(id) on delete cascade,
    pick_number int not null,
    member_id   uuid not null references public.fantasy_members(id) on delete cascade,
    player_id   uuid not null references public.fantasy_players(id) on delete cascade,
    slot        text not null,
    slot_type   text not null,
    created_at  timestamptz not null default now(),
    unique (league_id, pick_number)
);

create index if not exists fantasy_draft_picks_league_idx on public.fantasy_draft_picks (league_id);

-- ---------------------------------------------------------------------------
-- Weekly matchups + results
-- ---------------------------------------------------------------------------

create table if not exists public.fantasy_matchups (
    id          uuid primary key default gen_random_uuid(),
    league_id   uuid not null references public.fantasy_leagues(id) on delete cascade,
    week        int not null,
    member_a    uuid not null references public.fantasy_members(id) on delete cascade,
    member_b    uuid references public.fantasy_members(id) on delete cascade,  -- null = ghost (median) opponent
    is_ghost    boolean not null default false,
    is_playoff  boolean not null default false,
    created_at  timestamptz not null default now(),
    unique (league_id, week, member_a)
);

create table if not exists public.fantasy_weekly_results (
    id              uuid primary key default gen_random_uuid(),
    league_id       uuid not null references public.fantasy_leagues(id) on delete cascade,
    matchup_id      uuid references public.fantasy_matchups(id) on delete cascade,
    week            int not null,
    member_a        uuid not null references public.fantasy_members(id) on delete cascade,
    member_b        uuid references public.fantasy_members(id) on delete cascade,
    score_a         real not null default 0,     -- goals after goalie bonus
    score_b         real not null default 0,
    goalie_bonus_a  real not null default 1.0,    -- 1.2 / 0.8 / 1.0
    goalie_bonus_b  real not null default 1.0,
    winner_member_id uuid references public.fantasy_members(id) on delete set null,
    graded          boolean not null default false,
    updated_at      timestamptz not null default now(),
    unique (league_id, week, member_a)
);

-- ---------------------------------------------------------------------------
-- Weekly player stats (ingested from NHL results by the backend)
-- ---------------------------------------------------------------------------

create table if not exists public.fantasy_weekly_player_goals (
    id            uuid primary key default gen_random_uuid(),
    player_id     uuid not null references public.fantasy_players(id) on delete cascade,
    season_year   int not null,
    week          int not null,
    goals         int not null default 0,
    games_played  int not null default 0,
    eliminated    boolean not null default false,   -- for playoff (dwindling-roster) scoring
    updated_at    timestamptz not null default now(),
    unique (player_id, season_year, week)
);

create table if not exists public.fantasy_weekly_goalie_stats (
    id            uuid primary key default gen_random_uuid(),
    player_id     uuid not null references public.fantasy_players(id) on delete cascade,
    season_year   int not null,
    week          int not null,
    gsax          real not null default 0,
    games_played  int not null default 0,
    updated_at    timestamptz not null default now(),
    unique (player_id, season_year, week)
);

-- ---------------------------------------------------------------------------
-- RLS — backend (service key) bypasses all of this. Clients get read-only
-- access to the player pool; everything else is backend-only.
-- ---------------------------------------------------------------------------

alter table public.fantasy_players              enable row level security;
alter table public.fantasy_leagues              enable row level security;
alter table public.fantasy_members              enable row level security;
alter table public.fantasy_roster_slots         enable row level security;
alter table public.fantasy_draft_state          enable row level security;
alter table public.fantasy_draft_picks          enable row level security;
alter table public.fantasy_matchups             enable row level security;
alter table public.fantasy_weekly_results       enable row level security;
alter table public.fantasy_weekly_player_goals  enable row level security;
alter table public.fantasy_weekly_goalie_stats  enable row level security;

do $$
begin
    if not exists (select 1 from pg_policies where tablename = 'fantasy_players' and policyname = 'players readable') then
        create policy "players readable" on public.fantasy_players for select to authenticated using (true);
    end if;
end $$;
