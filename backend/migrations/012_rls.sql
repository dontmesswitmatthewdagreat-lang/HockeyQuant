-- 012_rls.sql
-- Resolves Supabase's `rls_disabled_in_public` warning. These tables predate the
-- migration chain and never had RLS. The backend uses the service key (bypasses
-- RLS), so enabling RLS with no anon policies = zero backend change, and the
-- public REST surface is closed.

ALTER TABLE public.predictions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_models       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_parlays     ENABLE ROW LEVEL SECURITY;

-- profiles IS read/written directly from the iOS app (username editor, with the
-- signed-in user's JWT), so it needs policies, not just RLS.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select_all ON public.profiles;
CREATE POLICY profiles_select_all ON public.profiles
    FOR SELECT USING (true);            -- usernames are shown on public leaderboards

DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
    FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Note: the fantasy_* and device_tokens tables already have RLS enabled with no
-- policies, which in Postgres means deny-all for anon — intentionally untouched.
