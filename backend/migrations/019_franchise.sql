-- HockeyQuant — My Franchise (card-collection mode). Migration 019.
-- A personal, single-player card game: buy player CARDS from a rotating shop with Coins,
-- build a dream-team lineup, and play a nightly challenge vs a real NHL team. Cards are
-- valued/rarity-rated from fantasy_players.cost (no extra column needed). One franchise per
-- account. Run once in the Supabase SQL editor. Idempotent.
--
-- RLS note: like the other game tables, these have RLS enabled with NO policies (deny-all to
-- clients). All access is through the service-key backend; the app reads via the API.

-- 1. The franchise wallet (one per user) -----------------------------------
create table if not exists public.franchises (
    user_id           uuid primary key references auth.users(id) on delete cascade,
    coins             bigint not null default 5000,     -- starting Coins
    last_daily_reward date,
    season_year       int,
    created_at        timestamptz not null default now()
);
alter table public.franchises enable row level security;

-- 2. Owned cards (collection; duplicates allowed) --------------------------
create table if not exists public.franchise_cards (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    player_id    uuid not null references public.fantasy_players(id) on delete cascade,
    rarity       text not null,                          -- common|uncommon|rare|epic|legend
    acquired_via text not null default 'shop',           -- shop|rookie|trade|starter
    created_at   timestamptz not null default now()
);
create index if not exists franchise_cards_user_idx on public.franchise_cards (user_id);
alter table public.franchise_cards enable row level security;

-- 3. The dream-team lineup (12 slots, same shape as ROSTER_SLOTS) ----------
create table if not exists public.franchise_lineup (
    user_id  uuid not null references auth.users(id) on delete cascade,
    slot     text not null,                              -- LW1..G_BACKUP
    card_id  uuid references public.franchise_cards(id) on delete set null,
    primary key (user_id, slot)
);
alter table public.franchise_lineup enable row level security;

-- 4. The daily-rotating shop (one row per date; same offers for everyone) ---
create table if not exists public.shop_rotation (
    rotation_date date primary key,
    items         jsonb not null default '[]'            -- [{player_id, rarity, price}]
);
alter table public.shop_rotation enable row level security;

-- 5. Nightly challenge results --------------------------------------------
create table if not exists public.franchise_challenges (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references auth.users(id) on delete cascade,
    game_date     text not null,
    opponent_team text not null,                         -- NHL team abbrev you challenged
    lineup        jsonb not null default '[]',           -- snapshot of card player_ids
    my_score      numeric,
    opp_score     numeric,
    won           boolean,
    coins_awarded int not null default 0,
    xp_awarded    int not null default 0,
    graded        boolean not null default false,
    created_at    timestamptz not null default now(),
    unique (user_id, game_date)
);
create index if not exists franchise_challenges_date_idx on public.franchise_challenges (game_date) where not graded;
alter table public.franchise_challenges enable row level security;

-- 6. Lottery-allocated rookie-draft picks (annual) -------------------------
create table if not exists public.rookie_picks (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    season_year int not null,
    round       int not null,
    used        boolean not null default false,
    created_at  timestamptz not null default now()
);
create index if not exists rookie_picks_user_idx on public.rookie_picks (user_id, season_year) where not used;
alter table public.rookie_picks enable row level security;
