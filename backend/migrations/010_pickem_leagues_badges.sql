-- HockeyQuant — Phase 1: Pick'em friend leagues + expanded badges. Run once in
-- Supabase. Idempotent. Backend uses the service key (bypasses RLS).

-- ---------------------------------------------------------------------------
-- Private Pick'em leagues (mirrors fantasy_leagues/members, simpler)
-- ---------------------------------------------------------------------------

create table if not exists public.pickem_leagues (
    id              uuid primary key default gen_random_uuid(),
    name            text not null,
    commissioner_id uuid not null references auth.users(id) on delete cascade,
    invite_code     text unique not null,
    season_year     int not null,
    max_members     int not null default 20,
    status          text not null default 'active',   -- active | archived
    created_at      timestamptz not null default now()
);

create table if not exists public.pickem_members (
    id          uuid primary key default gen_random_uuid(),
    league_id   uuid not null references public.pickem_leagues(id) on delete cascade,
    user_id     uuid not null references auth.users(id) on delete cascade,
    joined_at   timestamptz not null default now(),
    unique (league_id, user_id)
);

create index if not exists pickem_members_league_idx on public.pickem_members (league_id);
create index if not exists pickem_members_user_idx   on public.pickem_members (user_id);

alter table public.pickem_leagues enable row level security;
alter table public.pickem_members enable row level security;

do $$ begin
    create policy "pickem leagues readable" on public.pickem_leagues for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
    create policy "pickem members readable" on public.pickem_members for select to authenticated using (true);
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Expanded badge catalog
-- ---------------------------------------------------------------------------

insert into public.achievements (id, name, description, icon, sort) values
    ('sharp_50',  'Sharper',      'Reach 50 total correct picks.',     'scope',                 8),
    ('sharp_100', 'Sniper',       'Reach 100 total correct picks.',    'target',                9),
    ('streak_15', 'Locked In',    'Hit 15 correct picks in a row.',    'bolt.circle.fill',     10),
    ('beats_15',  'Giant Killer', 'Beat the model 15 times.',          'crown.fill',           11),
    ('xp_1000',   'All-Star',     'Earn 1,000 total XP.',              'star.circle.fill',     12),
    ('century',   'Centurion',    'Make 100 total picks.',             'flag.checkered',       13)
on conflict (id) do update set
    name = excluded.name, description = excluded.description, icon = excluded.icon, sort = excluded.sort;

-- Extend the auto-award function (idempotent) with the new stat-based badges.
create or replace function public.award_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare s public.user_stats;
begin
    select * into s from public.user_stats where user_id = p_user_id;
    if s is null then return; end if;

    if s.picks_correct >= 1   then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'first_win')    on conflict do nothing; end if;
    if s.best_streak  >= 3    then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'streak_3')     on conflict do nothing; end if;
    if s.best_streak  >= 5    then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'streak_5')     on conflict do nothing; end if;
    if s.best_streak  >= 10   then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'streak_10')    on conflict do nothing; end if;
    if s.best_streak  >= 15   then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'streak_15')    on conflict do nothing; end if;
    if s.picks_correct >= 25  then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'sharp_25')     on conflict do nothing; end if;
    if s.picks_correct >= 50  then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'sharp_50')     on conflict do nothing; end if;
    if s.picks_correct >= 100 then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'sharp_100')    on conflict do nothing; end if;
    if s.picks_made   >= 100  then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'century')      on conflict do nothing; end if;
    if s.beats_model  >= 5    then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'model_slayer') on conflict do nothing; end if;
    if s.beats_model  >= 15   then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'beats_15')     on conflict do nothing; end if;
    if s.total_xp     >= 500  then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'xp_500')       on conflict do nothing; end if;
    if s.total_xp     >= 1000 then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'xp_1000')      on conflict do nothing; end if;
end;
$$;
