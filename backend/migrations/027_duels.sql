-- HockeyQuant — Global League weekly duels
-- Run once in the Supabase SQL editor. Idempotent.
--
-- The ranked mode: each week you're matched against another player, you snake
-- draft a roster from randomly offered pools, and the higher weekly score wins.
-- Deliberately separate from private leagues, which stay season-long with
-- friends — nothing here touches fantasy_teams or league_* tables.
--
-- Depth slots ("1C", "2D", "3LW") are league-wide tiers, not team depth charts:
-- rank every skater at a position by model value and cut every 32. So "2C" is
-- roughly the second-line centre of an average team. Scarcer slots offer fewer
-- choices, which is what keeps an elite pick from also being a free choice.

create table if not exists public.duels (
    id            bigint generated always as identity primary key,
    week_start    date not null,                      -- Monday of the scoring week
    week_end      date not null,
    user_a        uuid not null references auth.users(id) on delete cascade,
    user_b        uuid not null references auth.users(id) on delete cascade,
    state         text not null default 'drafting',   -- drafting | live | final
    turn_user     uuid,                               -- whose pick it is (null once drafted)
    pick_no       int not null default 0,             -- picks made so far
    score_a       numeric,
    score_b       numeric,
    bonus_a       numeric,                            -- defensive + goalie weighting
    bonus_b       numeric,
    winner        uuid,                               -- null = tie or ungraded
    created_at    timestamptz not null default now(),
    graded_at     timestamptz,
    unique (week_start, user_a, user_b)
);

-- One row per pick. `offered` is the pool the drafter actually saw, kept so a
-- disputed or audited draft can be replayed exactly.
create table if not exists public.duel_picks (
    id            bigint generated always as identity primary key,
    duel_id       bigint not null references public.duels(id) on delete cascade,
    pick_no       int not null,
    user_id       uuid not null references auth.users(id) on delete cascade,
    slot          text not null,                      -- 1C | 2C | 1D | 2LW | G ...
    offered       jsonb not null,                     -- [{nhl_id, name, team, pos}, ...]
    chosen_nhl_id bigint,                             -- null until picked
    auto_picked   boolean not null default false,     -- true when the clock picked for you
    picked_at     timestamptz,
    unique (duel_id, pick_no)
);

-- Per-user ranked standing. Elo-style so beating a strong opponent is worth
-- more than farming a weak one, which is the point of ranking at all.
create table if not exists public.duel_rankings (
    user_id       uuid primary key references auth.users(id) on delete cascade,
    rating        int not null default 1000,
    wins          int not null default 0,
    losses        int not null default 0,
    ties          int not null default 0,
    streak        int not null default 0,             -- negative = losing streak
    best_rating   int not null default 1000,
    duels_played  int not null default 0,
    updated_at    timestamptz not null default now()
);

-- Queue of players waiting to be matched for an upcoming week.
create table if not exists public.duel_queue (
    user_id       uuid primary key references auth.users(id) on delete cascade,
    week_start    date not null,
    rating        int not null default 1000,          -- snapshot, for banded matching
    joined_at     timestamptz not null default now()
);

create index if not exists duels_week_idx     on public.duels (week_start);
create index if not exists duels_user_a_idx   on public.duels (user_a, week_start desc);
create index if not exists duels_user_b_idx   on public.duels (user_b, week_start desc);
create index if not exists duels_state_idx    on public.duels (state);
create index if not exists duel_picks_duel_idx on public.duel_picks (duel_id, pick_no);
create index if not exists duel_rank_idx      on public.duel_rankings (rating desc);
create index if not exists duel_queue_week_idx on public.duel_queue (week_start, rating);

alter table public.duels          enable row level security;
alter table public.duel_picks     enable row level security;
alter table public.duel_rankings  enable row level security;
alter table public.duel_queue     enable row level security;

do $$
begin
    -- Duels and picks are readable by anyone signed in: you can scout an
    -- opponent's roster, and the leaderboard needs to show completed matchups.
    if not exists (select 1 from pg_policies where tablename = 'duels' and policyname = 'duels readable') then
        create policy "duels readable" on public.duels for select to authenticated using (true);
    end if;
    if not exists (select 1 from pg_policies where tablename = 'duel_picks' and policyname = 'duel picks readable') then
        create policy "duel picks readable" on public.duel_picks for select to authenticated using (true);
    end if;
    if not exists (select 1 from pg_policies where tablename = 'duel_rankings' and policyname = 'duel rankings readable') then
        create policy "duel rankings readable" on public.duel_rankings for select to authenticated using (true);
    end if;
    if not exists (select 1 from pg_policies where tablename = 'duel_queue' and policyname = 'duel queue readable') then
        create policy "duel queue readable" on public.duel_queue for select to authenticated using (true);
    end if;
end $$;

-- Writes go through the backend on the service key only: the draft has to
-- enforce whose turn it is, that a pick came from the pool actually offered,
-- and that nobody drafts a player already taken in that duel.
