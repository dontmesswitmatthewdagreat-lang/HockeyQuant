-- HockeyQuant — My Franchise card trading (migration 021).
-- Two ways to trade cards across accounts: a public marketplace (list a card for Coins,
-- anyone buys) and direct card-for-card offers (+/- Coins) between two managers.
-- Run once in the Supabase SQL editor. Idempotent.
--
-- RLS note: like the other game tables, these have RLS enabled with NO policies (deny-all
-- to clients). All access is through the service-key backend.

-- 1. Marketplace listings ---------------------------------------------------
create table if not exists public.card_listings (
    id          uuid primary key default gen_random_uuid(),
    seller_id   uuid not null references auth.users(id) on delete cascade,
    card_id     uuid not null references public.franchise_cards(id) on delete cascade,
    player_id   uuid not null references public.fantasy_players(id) on delete cascade,
    rarity      text not null,
    price       bigint not null,
    status      text not null default 'open',      -- open | sold | cancelled
    buyer_id    uuid references auth.users(id) on delete set null,
    created_at  timestamptz not null default now(),
    resolved_at timestamptz
);
create index if not exists card_listings_open_idx on public.card_listings (status) where status = 'open';
alter table public.card_listings enable row level security;

-- 2. Direct card-for-card offers -------------------------------------------
create table if not exists public.card_offers (
    id           uuid primary key default gen_random_uuid(),
    from_user    uuid not null references auth.users(id) on delete cascade,
    to_user      uuid not null references auth.users(id) on delete cascade,
    from_card_id uuid references public.franchise_cards(id) on delete set null,
    to_card_id   uuid references public.franchise_cards(id) on delete set null,
    from_coins   bigint not null default 0,         -- Coins the proposer adds
    to_coins     bigint not null default 0,         -- Coins the receiver adds
    status       text not null default 'pending',   -- pending | accepted | rejected | cancelled
    created_at   timestamptz not null default now(),
    resolved_at  timestamptz
);
create index if not exists card_offers_inbox_idx on public.card_offers (to_user, status);
alter table public.card_offers enable row level security;
