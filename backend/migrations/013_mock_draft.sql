-- HockeyQuant — Weekly mock draft
-- Run once in the Supabase SQL editor. Idempotent.
--
-- A server-generated first-round mock draft, refreshed weekly from the latest
-- standings + team stats. Backend writes via the service key; the app reads it
-- through GET /api/prospects/mock-draft.

create table if not exists public.mock_drafts (
    id            uuid primary key default gen_random_uuid(),
    draft_year    int not null,
    edition       text not null,                 -- ISO year-week, e.g. 2026-W25
    order_basis   text,                          -- e.g. "Projected from standings as of YYYY-MM-DD"
    picks         jsonb not null default '[]',   -- [{overall, round, team, team_name, need, reason, prospect{…}}]
    generated_at  timestamptz not null default now(),
    unique (draft_year, edition)
);

create index if not exists mock_drafts_recent_idx on public.mock_drafts (generated_at desc);

alter table public.mock_drafts enable row level security;

do $$
begin
    if not exists (select 1 from pg_policies where tablename = 'mock_drafts' and policyname = 'mock drafts readable') then
        create policy "mock drafts readable" on public.mock_drafts for select to authenticated using (true);
    end if;
end $$;
