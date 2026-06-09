-- HockeyQuant — Async draft pick clock + push device tokens
-- Run once in the Supabase SQL editor. Idempotent.

-- Per-pick deadline so drafts can run asynchronously (auto-pick on expiry).
alter table public.fantasy_draft_state
    add column if not exists pick_deadline timestamptz;

-- APNs device tokens for push (one row per device; re-mapped to the latest user).
create table if not exists public.device_tokens (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    token       text not null unique,
    platform    text not null default 'ios',
    updated_at  timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
