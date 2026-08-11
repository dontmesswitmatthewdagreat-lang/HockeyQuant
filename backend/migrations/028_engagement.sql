-- HockeyQuant — Phase 2 engagement mechanics
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Schema for four mechanics: odds-weighted XP (no schema of its own — the win
-- probabilities already live on predictions), the Puck Freeze streak shield,
-- the Flash Slate nightly duel, and the open model marketplace.

-- ---------------------------------------------------------------- Puck Freeze
-- A shield absorbs one wrong pick instead of resetting the streak. Kept on
-- user_stats beside the streak it protects, so grading reads and writes one row.
alter table public.user_stats add column if not exists streak_shields int not null default 0;
alter table public.user_stats add column if not exists shields_earned_total int not null default 0;

-- One row per save. A bare counter would let the app silently preserve a streak,
-- which reads as a bug; this is what lets the UI say "your streak was saved"
-- and show when. Also the audit trail if shield accounting is ever disputed.
create table if not exists public.streak_shield_uses (
    id          bigint generated always as identity primary key,
    user_id     uuid not null references auth.users(id) on delete cascade,
    game_date   date not null,
    streak_kept int not null,              -- what the streak would have reset from
    used_at     timestamptz not null default now(),
    unique (user_id, game_date)            -- at most one save per slate
);

create index if not exists streak_shield_uses_user_idx
    on public.streak_shield_uses (user_id, used_at desc);

-- ---------------------------------------------------------------- Flash Slate
-- The nightly duel is the weekly engine with a shorter window, so it gets a
-- discriminator rather than a forked table. Existing rows are weekly by
-- definition, which is why the default backfills correctly.
alter table public.duels add column if not exists mode text not null default 'weekly';

-- A flash duel is scoped to one night, so week_start/week_end collapse to the
-- same date and this index carries both modes.
create index if not exists duels_mode_week_idx on public.duels (mode, week_start desc);

-- The queue needs the same split, or a player waiting for Friday night gets
-- matched into a seven-day duel.
alter table public.duel_queue add column if not exists mode text not null default 'weekly';

-- Queue membership is per mode: you can be waiting for both at once. Replaces
-- the single-row-per-user primary key with a per-mode one.
alter table public.duel_queue drop constraint if exists duel_queue_pkey;
alter table public.duel_queue add primary key (user_id, mode);

-- ------------------------------------------------------------ Model marketplace
alter table public.user_models add column if not exists is_public boolean not null default false;
alter table public.user_models add column if not exists published_at timestamptz;
alter table public.user_models add column if not exists forked_from uuid references public.user_models(id) on delete set null;
alter table public.user_models add column if not exists fork_count int not null default 0;

create index if not exists user_models_public_idx on public.user_models (is_public, published_at desc);
create index if not exists user_models_forked_from_idx on public.user_models (forked_from);

-- Explicit fork rows rather than trusting fork_count alone: reputation has to be
-- recomputable, and a counter that can only be incremented can't be audited or
-- corrected. The unique constraint stops one user farming a model repeatedly.
create table if not exists public.model_forks (
    id          bigint generated always as identity primary key,
    source_id   uuid not null references public.user_models(id) on delete cascade,
    forked_id   uuid not null references public.user_models(id) on delete cascade,
    user_id     uuid not null references auth.users(id) on delete cascade,
    created_at  timestamptz not null default now(),
    unique (source_id, user_id)
);

create index if not exists model_forks_source_idx on public.model_forks (source_id);

alter table public.streak_shield_uses enable row level security;
alter table public.model_forks        enable row level security;

do $$
begin
    -- Your own saves only — another user's streak history isn't public.
    if not exists (select 1 from pg_policies where tablename = 'streak_shield_uses' and policyname = 'own shield uses readable') then
        create policy "own shield uses readable" on public.streak_shield_uses
            for select to authenticated using (auth.uid() = user_id);
    end if;
    -- Forks are public: they're the reputation signal on the marketplace.
    if not exists (select 1 from pg_policies where tablename = 'model_forks' and policyname = 'model forks readable') then
        create policy "model forks readable" on public.model_forks
            for select to authenticated using (true);
    end if;
end $$;

-- Writes stay service-key only: shields must be spent exactly once during
-- grading, and fork_count has to move in lockstep with the model_forks row.
