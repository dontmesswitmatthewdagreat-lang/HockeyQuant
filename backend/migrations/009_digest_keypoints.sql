-- HockeyQuant — News digest "key points" (AI takeaways). Run once in Supabase. Idempotent.

alter table public.news_digests
    add column if not exists key_points jsonb not null default '[]';
