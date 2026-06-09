-- HockeyQuant — Fantasy G5: trades + playoff elimination
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Playoffs reuse fantasy_matchups (is_playoff=true, week > regular season) and
-- fantasy_weekly_results. The global league reuses the existing league/member/
-- roster tables (league_type='global', unique_players=false). Only two new
-- tables are needed: trades and the playoff elimination list.

create table if not exists public.fantasy_trades (
    id                  uuid primary key default gen_random_uuid(),
    league_id           uuid not null references public.fantasy_leagues(id) on delete cascade,
    proposer_member     uuid not null references public.fantasy_members(id) on delete cascade,
    receiver_member     uuid not null references public.fantasy_members(id) on delete cascade,
    proposer_player_id  uuid not null references public.fantasy_players(id) on delete cascade,
    receiver_player_id  uuid not null references public.fantasy_players(id) on delete cascade,
    slot_type           text not null,                 -- both players share this slot type
    status              text not null default 'pending', -- pending | accepted | rejected | cancelled
    created_at          timestamptz not null default now(),
    resolved_at         timestamptz
);

create index if not exists fantasy_trades_league_idx on public.fantasy_trades (league_id);
create index if not exists fantasy_trades_receiver_idx on public.fantasy_trades (receiver_member) where status = 'pending';

-- NHL teams eliminated from the playoffs (drives "surviving players only" scoring).
create table if not exists public.fantasy_eliminated_teams (
    id            uuid primary key default gen_random_uuid(),
    season_year   int not null,
    team          text not null,
    eliminated_at timestamptz not null default now(),
    unique (season_year, team)
);

alter table public.fantasy_trades            enable row level security;
alter table public.fantasy_eliminated_teams  enable row level security;
