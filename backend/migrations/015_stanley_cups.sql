-- HockeyQuant — Stanley Cup trophy system (Play tab redesign), phase 1a
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Repoints Play gamification from XP to a two-currency model:
--   * cap_space    — earned from correct daily picks; a growing salary-cap budget
--                    you spend to sign real NHL players onto your Global-League team.
--   * stanley_cups — a Clash-Royale-style trophy ladder driven by weekly fantasy
--                    head-to-head results (awarded by the cup-scoring job — phase 1c —
--                    NOT here). Leaderboard ranks by Cups; Arena derives from Cups.
-- Daily picks now pay Cap Space instead of XP. The legacy total_xp/level columns
-- stay but go unused, so everyone starts fresh at 0 Cups / 0 Cap Space.

-- 1. New currencies on user_stats -------------------------------------------
alter table public.user_stats add column if not exists stanley_cups int not null default 0;
alter table public.user_stats add column if not exists cap_space    int not null default 0;

-- 2. Player acquisition cost (salary-cap gating) ----------------------------
alter table public.fantasy_players add column if not exists cost int not null default 0;

-- 3. Global-league weekly Cup matches (the trophy ladder) --------------------
create table if not exists public.cup_matches (
    id               uuid primary key default gen_random_uuid(),
    season_year      int  not null,
    week             int  not null,
    member_a         uuid not null references public.fantasy_members(id) on delete cascade,
    member_b         uuid references public.fantasy_members(id) on delete cascade,  -- null = bye / ghost
    score_a          numeric not null default 0,
    score_b          numeric not null default 0,
    cups_a           int  not null default 0,        -- Cup delta applied to member_a
    cups_b           int  not null default 0,        -- Cup delta applied to member_b
    winner_member_id uuid references public.fantasy_members(id),
    is_ghost         boolean not null default false,
    graded           boolean not null default false,
    created_at       timestamptz not null default now(),
    unique (season_year, week, member_a)
);
create index if not exists cup_matches_week_idx on public.cup_matches (season_year, week);

alter table public.cup_matches enable row level security;
do $$
begin
    if not exists (select 1 from pg_policies where tablename = 'cup_matches' and policyname = 'cup matches readable') then
        create policy "cup matches readable" on public.cup_matches for select to authenticated using (true);
    end if;
end $$;

-- 4. Pick grading now pays Cap Space (not XP) -------------------------------
-- Same flow/streak/achievement logic as 001; only the payout currency changes.
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
    v_cap     int;
begin
    if p_actual_winner is null then return; end if;

    for r in
        select * from public.user_picks
        where game_date = p_game_date and away_team = p_away and home_team = p_home
          and correct is null and pick_type = 'ML'
    loop
        v_correct := upper(r.pick) = upper(p_actual_winner);
        v_beat    := v_correct and r.model_pick is not null and upper(r.model_pick) <> upper(p_actual_winner);
        -- Cap Space payout: a correct pick funds your salary cap; beating the model is a bonus.
        v_cap     := (case when v_correct then 50 else 0 end) + (case when v_beat then 25 else 0 end);

        update public.user_picks
           set correct = v_correct, xp_awarded = v_cap   -- xp_awarded column now holds Cap Space earned
         where id = r.id;

        insert into public.user_stats as us (
            user_id, cap_space, picks_made, picks_correct, beats_model,
            current_streak, best_streak, last_graded_date, updated_at
        )
        values (
            r.user_id, v_cap, 1,
            (case when v_correct then 1 else 0 end),
            (case when v_beat then 1 else 0 end),
            (case when v_correct then 1 else 0 end),
            (case when v_correct then 1 else 0 end),
            p_game_date, now()
        )
        on conflict (user_id) do update set
            cap_space      = us.cap_space + v_cap,
            picks_made     = us.picks_made + 1,
            picks_correct  = us.picks_correct + (case when v_correct then 1 else 0 end),
            beats_model    = us.beats_model + (case when v_beat then 1 else 0 end),
            current_streak = (case when v_correct then us.current_streak + 1 else 0 end),
            best_streak    = greatest(us.best_streak, (case when v_correct then us.current_streak + 1 else 0 end)),
            last_graded_date = p_game_date,
            updated_at     = now();

        perform public.award_achievements(r.user_id);
    end loop;
end;
$$;

-- 5. Leaderboard ranks by Stanley Cups --------------------------------------
drop view if exists public.leaderboard;
create view public.leaderboard as
select
    us.user_id,
    p.username,
    us.stanley_cups,
    us.cap_space,
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
order by us.stanley_cups desc, us.picks_correct desc;

grant select on public.leaderboard to anon, authenticated;
