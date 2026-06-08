-- HockeyQuant — Phase 2 Gamification schema
-- Run this once in the Supabase SQL editor (Dashboard → SQL → New query → paste → Run).
-- Safe to re-run (idempotent where practical).
--
-- Design notes:
--   * user_picks: a user's "call the game" picks. Users insert/edit their own
--     while ungraded; they can never set `correct`/`xp_awarded` themselves.
--   * user_stats: XP/level/streak. NOT directly writable by users — only the
--     SECURITY DEFINER grading functions write it (tamper-proof XP).
--   * Grading is automatic: a trigger on `predictions` fires when a game is
--     graded by the existing cron, grading any matching user picks.
--   * leaderboard: a view that bypasses RLS so rankings are public.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.user_picks (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade default auth.uid(),
    game_date   text not null,                 -- YYYY-MM-DD (ET)
    game_id     text not null,
    away_team   text not null,
    home_team   text not null,
    pick_type   text not null default 'ML',    -- ML | PL | OU
    pick        text not null,                 -- team abbrev (ML) / home|away (PL) / over|under (OU)
    model_pick  text,                          -- the model's pick, for "you vs model"
    correct     boolean,                       -- null until graded
    xp_awarded  int not null default 0,
    created_at  timestamptz not null default now(),
    unique (user_id, game_id, pick_type)
);

create index if not exists user_picks_user_date_idx on public.user_picks (user_id, game_date);
create index if not exists user_picks_game_idx on public.user_picks (game_id) where correct is null;

create table if not exists public.user_stats (
    user_id          uuid primary key references auth.users(id) on delete cascade default auth.uid(),
    total_xp         int not null default 0,
    level            int not null default 1,
    current_streak   int not null default 0,
    best_streak      int not null default 0,
    picks_made       int not null default 0,
    picks_correct    int not null default 0,
    beats_model      int not null default 0,
    last_graded_date text,
    updated_at       timestamptz not null default now()
);

create table if not exists public.achievements (
    id          text primary key,   -- slug
    name        text not null,
    description text not null,
    icon        text not null,      -- SF Symbol name
    sort        int not null default 0
);

create table if not exists public.user_achievements (
    user_id        uuid not null references auth.users(id) on delete cascade default auth.uid(),
    achievement_id text not null references public.achievements(id) on delete cascade,
    earned_at      timestamptz not null default now(),
    primary key (user_id, achievement_id)
);

-- ---------------------------------------------------------------------------
-- Achievements catalog (idempotent upsert)
-- ---------------------------------------------------------------------------

insert into public.achievements (id, name, description, icon, sort) values
    ('first_win',    'First Win',      'Get your first correct pick.',            'checkmark.seal.fill', 1),
    ('streak_3',     'Heating Up',     'Hit 3 correct picks in a row.',           'flame.fill',          2),
    ('streak_5',     'On Fire',        'Hit 5 correct picks in a row.',           'flame.fill',          3),
    ('streak_10',    'Unconscious',    'Hit 10 correct picks in a row.',          'bolt.fill',           4),
    ('sharp_25',     'Sharp',          'Reach 25 total correct picks.',           'scope',               5),
    ('model_slayer', 'Model Slayer',   'Beat the model 5 times.',                 'crown.fill',          6),
    ('xp_500',       'Veteran',        'Earn 500 total XP.',                      'star.fill',           7)
on conflict (id) do update set
    name = excluded.name, description = excluded.description, icon = excluded.icon, sort = excluded.sort;

-- ---------------------------------------------------------------------------
-- Grading
-- ---------------------------------------------------------------------------

-- Award achievements based on current stats (idempotent).
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

    if s.picks_correct >= 1  then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'first_win')    on conflict do nothing; end if;
    if s.best_streak  >= 3   then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'streak_3')     on conflict do nothing; end if;
    if s.best_streak  >= 5   then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'streak_5')     on conflict do nothing; end if;
    if s.best_streak  >= 10  then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'streak_10')    on conflict do nothing; end if;
    if s.picks_correct >= 25 then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'sharp_25')     on conflict do nothing; end if;
    if s.beats_model  >= 5   then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'model_slayer') on conflict do nothing; end if;
    if s.total_xp     >= 500 then insert into public.user_achievements(user_id, achievement_id) values (p_user_id,'xp_500')       on conflict do nothing; end if;
end;
$$;

-- Grade all ungraded ML picks for one game against the actual winner.
-- Matched on (game_date, away_team, home_team) since the prediction API does
-- not expose the NHL game_id.
create or replace function public.grade_user_picks_for_game(
    p_game_date text, p_away text, p_home text, p_actual_winner text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    r public.user_picks;
    v_correct boolean;
    v_beat    boolean;
    v_xp      int;
begin
    if p_actual_winner is null then return; end if;

    for r in
        select * from public.user_picks
        where game_date = p_game_date and away_team = p_away and home_team = p_home
          and correct is null and pick_type = 'ML'
    loop
        v_correct := upper(r.pick) = upper(p_actual_winner);
        v_beat    := v_correct and r.model_pick is not null and upper(r.model_pick) <> upper(p_actual_winner);
        v_xp      := (case when v_correct then 10 else 2 end) + (case when v_beat then 15 else 0 end);

        update public.user_picks
           set correct = v_correct, xp_awarded = v_xp
         where id = r.id;

        insert into public.user_stats as us (
            user_id, total_xp, level, picks_made, picks_correct, beats_model,
            current_streak, best_streak, last_graded_date, updated_at
        )
        values (
            r.user_id, v_xp, 1, 1,
            (case when v_correct then 1 else 0 end),
            (case when v_beat then 1 else 0 end),
            (case when v_correct then 1 else 0 end),
            (case when v_correct then 1 else 0 end),
            p_game_date, now()
        )
        on conflict (user_id) do update set
            total_xp       = us.total_xp + v_xp,
            picks_made     = us.picks_made + 1,
            picks_correct  = us.picks_correct + (case when v_correct then 1 else 0 end),
            beats_model    = us.beats_model + (case when v_beat then 1 else 0 end),
            current_streak = (case when v_correct then us.current_streak + 1 else 0 end),
            best_streak    = greatest(us.best_streak, (case when v_correct then us.current_streak + 1 else 0 end)),
            last_graded_date = p_game_date,
            updated_at     = now();

        update public.user_stats
           set level = 1 + (total_xp / 100)
         where user_id = r.user_id;

        perform public.award_achievements(r.user_id);
    end loop;
end;
$$;

-- Trigger: when the existing cron grades a prediction, grade user picks too.
create or replace function public.on_prediction_graded()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.correct is not null and (old.correct is null or old.correct is distinct from new.correct) then
        perform public.grade_user_picks_for_game(new.game_date, new.away_team, new.home_team, new.actual_winner);
    end if;
    return new;
end;
$$;

-- Install the trigger only if the predictions table exists, so this migration
-- never hard-fails. (If you hit "relation public.predictions does not exist",
-- you're likely connected to the wrong Supabase project.)
do $$
begin
    if exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'predictions'
    ) then
        drop trigger if exists trg_prediction_graded on public.predictions;
        create trigger trg_prediction_graded
            after update on public.predictions
            for each row execute function public.on_prediction_graded();
        raise notice 'Auto-grading trigger installed on public.predictions.';
    else
        raise notice 'predictions table not found in public — skipping trigger. '
                     'Use grade_user_picks_backfill() to grade picks manually.';
    end if;
end $$;

-- Backfill helper for testing: grade every ungraded pick against any already
-- graded prediction. Run manually after making test picks on a past date.
create or replace function public.grade_user_picks_backfill()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare g record;
begin
    for g in
        select distinct p.game_date::text as game_date, p.away_team, p.home_team, p.actual_winner
        from public.predictions p
        join public.user_picks up
          on up.game_date = p.game_date::text and up.away_team = p.away_team and up.home_team = p.home_team
        where p.correct is not null and up.correct is null
    loop
        perform public.grade_user_picks_for_game(g.game_date, g.away_team, g.home_team, g.actual_winner);
    end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Leaderboard view (bypasses RLS so rankings are public)
-- ---------------------------------------------------------------------------

create or replace view public.leaderboard as
select
    us.user_id,
    p.username,
    us.total_xp,
    us.level,
    us.current_streak,
    us.best_streak,
    us.picks_made,
    us.picks_correct,
    case when us.picks_made > 0
         then round(us.picks_correct::numeric / us.picks_made * 100, 1)::float8
         else 0::float8 end as accuracy
from public.user_stats us
left join public.profiles p on p.id = us.user_id
order by us.total_xp desc, us.picks_correct desc;

grant select on public.leaderboard to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.user_picks        enable row level security;
alter table public.user_stats        enable row level security;
alter table public.achievements      enable row level security;
alter table public.user_achievements enable row level security;

-- user_picks: read/insert/update/delete your own, and only while ungraded.
drop policy if exists user_picks_select on public.user_picks;
create policy user_picks_select on public.user_picks
    for select using (user_id = auth.uid());

drop policy if exists user_picks_insert on public.user_picks;
create policy user_picks_insert on public.user_picks
    for insert with check (user_id = auth.uid() and correct is null);

drop policy if exists user_picks_update on public.user_picks;
create policy user_picks_update on public.user_picks
    for update using (user_id = auth.uid() and correct is null)
    with check (user_id = auth.uid() and correct is null);

drop policy if exists user_picks_delete on public.user_picks;
create policy user_picks_delete on public.user_picks
    for delete using (user_id = auth.uid() and correct is null);

-- user_stats: read your own only. No write policies → only SECURITY DEFINER
-- functions can modify it (XP is tamper-proof).
drop policy if exists user_stats_select on public.user_stats;
create policy user_stats_select on public.user_stats
    for select using (user_id = auth.uid());

-- achievements: public catalog.
drop policy if exists achievements_select on public.achievements;
create policy achievements_select on public.achievements
    for select using (true);

-- user_achievements: read your own.
drop policy if exists user_achievements_select on public.user_achievements;
create policy user_achievements_select on public.user_achievements
    for select using (user_id = auth.uid());
