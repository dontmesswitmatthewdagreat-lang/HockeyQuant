-- HockeyQuant — Off-Season Franchise Mode (migration 018)
-- Wraps the Stanley Cup system in a seasonal cycle with an off-season build phase:
-- prospects become draftable players, leagues gain a season phase + per-league
-- franchise Cap Space + CPU GMs, draft picks become tradeable assets, and a season
-- archive survives the reset. Run once in the Supabase SQL editor. Idempotent.
--
-- RLS note: like the other fantasy_* tables, the new tables have RLS enabled with NO
-- policies (deny-all to clients). All access is through the service-key backend; the
-- app reads fantasy data via the API, never PostgREST directly.

-- 1. Prospects become draftable fantasy_players -----------------------------
alter table public.fantasy_players add column if not exists is_prospect      boolean not null default false;
alter table public.fantasy_players add column if not exists prospect_ranking int;     -- consensus board rank (1 = best)
alter table public.fantasy_players add column if not exists draft_class      int;     -- draft year this prospect is eligible
create index if not exists fantasy_players_prospect_idx on public.fantasy_players (roster_pos) where is_prospect;

-- 2. Members: nullable user (CPU GMs), per-league franchise bank + pick credits
alter table public.fantasy_members alter column user_id drop not null;
alter table public.fantasy_members add column if not exists is_cpu       boolean not null default false;
alter table public.fantasy_members add column if not exists cap_space    bigint  not null default 0;   -- franchise bank (carries across seasons)
alter table public.fantasy_members add column if not exists pick_credits int     not null default 0;   -- extra picks bought with Cap Space

-- 3. Leagues: season phase, mode, lottery payload ---------------------------
-- season_phase: offseason_lottery | offseason_draft | offseason_open | regular | playoffs | complete
alter table public.fantasy_leagues add column if not exists season_phase text not null default 'regular';
alter table public.fantasy_leagues add column if not exists mode         text not null default 'group';  -- group | global | solo
alter table public.fantasy_leagues add column if not exists lottery      jsonb;                          -- odds + reveal order for the animated UI

-- 4. Tradeable draft-pick assets --------------------------------------------
create table if not exists public.fantasy_draft_pick_assets (
    id                  uuid primary key default gen_random_uuid(),
    league_id           uuid not null references public.fantasy_leagues(id) on delete cascade,
    season_year         int not null,
    round               int not null,
    original_member_id  uuid references public.fantasy_members(id) on delete set null,   -- whose slot it was
    owner_member_id     uuid references public.fantasy_members(id) on delete cascade,    -- who holds it now
    used                boolean not null default false,
    created_at          timestamptz not null default now()
);
create index if not exists draft_pick_assets_league_idx on public.fantasy_draft_pick_assets (league_id, season_year);
alter table public.fantasy_draft_pick_assets enable row level security;

-- 5. Season archive (kept across resets) ------------------------------------
create table if not exists public.fantasy_team_archive (
    id           uuid primary key default gen_random_uuid(),
    league_id    uuid not null references public.fantasy_leagues(id) on delete cascade,
    season_year  int  not null,
    member_id    uuid references public.fantasy_members(id) on delete set null,
    team_name    text,
    final_cups   int  not null default 0,
    final_rank   int,
    team_rating  int  not null default 0,
    created_at   timestamptz not null default now(),
    unique (league_id, season_year, member_id)
);
alter table public.fantasy_team_archive enable row level security;

-- 6. Trades can include picks + currency, not just players ------------------
alter table public.fantasy_trades alter column proposer_player_id drop not null;
alter table public.fantasy_trades alter column receiver_player_id drop not null;
alter table public.fantasy_trades alter column slot_type          drop not null;
alter table public.fantasy_trades add column if not exists proposer_pick_id uuid references public.fantasy_draft_pick_assets(id) on delete set null;
alter table public.fantasy_trades add column if not exists receiver_pick_id uuid references public.fantasy_draft_pick_assets(id) on delete set null;
alter table public.fantasy_trades add column if not exists proposer_cap     bigint not null default 0;   -- Cap Space sent by proposer
alter table public.fantasy_trades add column if not exists receiver_cap     bigint not null default 0;   -- Cap Space sent by receiver
