-- HockeyQuant — durable trade ledger for the Offseason Report Card
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Spotrac's transactions feed is a rolling window: it paginates chronologically
-- and drops history at the league-year rollover, so trades the report card
-- graded in July can be gone in August. Twice now that silently rewrote every
-- team's grade (once from a markup change, once from the rollover itself).
-- These tables are the system of record instead: the sync job only ever adds
-- and refreshes rows, so a bad scrape day — or an upstream purge — can no
-- longer erase what we already saw.
--
-- league_year follows the NHL convention: the year free agency opened. A trade
-- on Jun 24 2026, Jul 1 2026, or Mar 2027 all belong to league year 2026.

create table if not exists public.trade_players (
    id            bigint generated always as identity primary key,
    player_name   text not null,
    name_norm     text not null,      -- lowercased, for the scraper's dedupe key
    from_team     text not null,      -- normalized abbrev (WSH, not WAS)
    to_team       text not null,
    traded_on     date,               -- null when the row carried no parseable date
    league_year   int not null,
    first_seen_at timestamptz not null default now(),
    last_seen_at  timestamptz not null default now(),
    unique (name_norm, to_team, from_team)
);

create table if not exists public.trade_picks (
    id            bigint generated always as identity primary key,
    from_team     text not null,
    to_team       text not null,
    pick_year     int not null,
    pick_round    int not null,
    conditional   boolean not null default false,
    traded_on     date,
    league_year   int not null,
    first_seen_at timestamptz not null default now(),
    last_seen_at  timestamptz not null default now(),
    unique (from_team, to_team, pick_year, pick_round)
);

create index if not exists trade_players_year_idx on public.trade_players (league_year);
create index if not exists trade_players_to_idx   on public.trade_players (to_team, league_year);
create index if not exists trade_players_from_idx on public.trade_players (from_team, league_year);
create index if not exists trade_picks_year_idx   on public.trade_picks (league_year);
create index if not exists trade_picks_to_idx     on public.trade_picks (to_team, league_year);
create index if not exists trade_picks_from_idx   on public.trade_picks (from_team, league_year);

alter table public.trade_players enable row level security;
alter table public.trade_picks   enable row level security;

do $$
begin
    if not exists (select 1 from pg_policies where tablename = 'trade_players' and policyname = 'trade players readable') then
        create policy "trade players readable" on public.trade_players for select to authenticated using (true);
    end if;
    if not exists (select 1 from pg_policies where tablename = 'trade_picks' and policyname = 'trade picks readable') then
        create policy "trade picks readable" on public.trade_picks for select to authenticated using (true);
    end if;
end $$;
