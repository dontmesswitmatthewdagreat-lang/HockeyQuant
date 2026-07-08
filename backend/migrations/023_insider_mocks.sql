-- Insider mock drafts: one mock_drafts row per (year, edition, source), where
-- source is "HockeyQuant" (internal engine) or an outlet ("ESPN", "TSN", ...).
-- Run once in the Supabase SQL editor. Idempotent.

alter table public.mock_drafts
    add column if not exists source text not null default 'HockeyQuant';

alter table public.mock_drafts
    drop constraint if exists mock_drafts_draft_year_edition_key;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'mock_drafts_year_edition_source_key') then
        alter table public.mock_drafts
            add constraint mock_drafts_year_edition_source_key unique (draft_year, edition, source);
    end if;
end $$;

-- The app now reads mocks anonymously through the backend service key only,
-- but keep the anon read in line with the prospects tables.
do $$
begin
    if not exists (select 1 from pg_policies where tablename = 'mock_drafts' and policyname = 'mock drafts public read') then
        create policy "mock drafts public read" on public.mock_drafts for select using (true);
    end if;
end $$;
