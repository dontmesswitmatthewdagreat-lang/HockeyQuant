-- HockeyQuant — News digests + Prospect tracking
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Digests store AI-written summaries + source links only (no full article text).
-- Backend writes via the service key; clients get read-only access (public content).

create table if not exists public.news_digests (
    id           uuid primary key default gen_random_uuid(),
    digest_date  text not null,                 -- YYYY-MM-DD (ET)
    kind         text not null,                 -- morning | pregame | postgame
    scope        text not null,                 -- 'league' or a team abbrev
    title        text not null,
    intro        text,
    items        jsonb not null default '[]',   -- [{headline, blurb, tag, source, url, published_at}]
    model        text,
    created_at   timestamptz not null default now(),
    unique (digest_date, kind, scope)
);

create index if not exists news_digests_lookup_idx on public.news_digests (scope, kind, digest_date desc);

create table if not exists public.prospects (
    id             uuid primary key default gen_random_uuid(),
    nhl_id         bigint unique,
    name           text not null,
    team           text,                         -- NHL team abbrev (drafted by / in system)
    position       text,
    draft_year     int,
    draft_overall  int,
    league         text,                          -- current league (CHL/AHL/NCAA/etc.)
    ranking        int,                           -- draft ranking when applicable
    notable        boolean not null default false,
    info           jsonb not null default '{}',
    updated_at     timestamptz not null default now()
);

create index if not exists prospects_team_idx on public.prospects (team);

alter table public.news_digests enable row level security;
alter table public.prospects    enable row level security;

do $$
begin
    if not exists (select 1 from pg_policies where tablename = 'news_digests' and policyname = 'digests readable') then
        create policy "digests readable" on public.news_digests for select to authenticated using (true);
    end if;
    if not exists (select 1 from pg_policies where tablename = 'prospects' and policyname = 'prospects readable') then
        create policy "prospects readable" on public.prospects for select to authenticated using (true);
    end if;
end $$;
