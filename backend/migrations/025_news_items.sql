-- HockeyQuant — flat news archive (News 2.0)
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Every article/blurb any source produces lands here exactly once (unique on
-- the normalized URL). Digests draw from and mark back into this table, which
-- gives us: cross-run dedupe (no day-to-day repeats), a scrollable archive
-- feed, and full-text search. Headlines + snippets + links only — never full
-- article text.

create table if not exists public.news_items (
    id            bigint generated always as identity primary key,
    url           text not null,
    url_norm      text not null,      -- lowercased, no query string / trailing slash
    title         text not null,
    title_norm    text not null,      -- lowercased alnum+spaces, first 80 chars
    snippet       text,
    source        text not null,      -- display name ("Pro Hockey Rumors")
    source_id     text not null,      -- registry id ("phr", "bsky_puckpedia")
    kind          text not null default 'article',   -- article | blurb
    scope         text not null default 'league',    -- league | team
    team          text,                               -- abbrev when team-scoped
    tag           text not null default 'Other',
    image_url     text,
    published_at  timestamptz,
    first_seen_at timestamptz not null default now(),
    used_in_digest_at timestamptz,    -- set when a digest features it (72h repeat-exclusion)
    fts tsvector generated always as
        (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(snippet, ''))) stored,
    unique (url_norm)
);

create index if not exists news_items_feed_idx  on public.news_items (kind, id desc);
create index if not exists news_items_team_idx  on public.news_items (team, id desc);
create index if not exists news_items_title_idx on public.news_items (title_norm);
create index if not exists news_items_fts_idx   on public.news_items using gin (fts);

alter table public.news_items enable row level security;

do $$
begin
    if not exists (select 1 from pg_policies where tablename = 'news_items' and policyname = 'news items readable') then
        create policy "news items readable" on public.news_items for select to authenticated using (true);
    end if;
end $$;
