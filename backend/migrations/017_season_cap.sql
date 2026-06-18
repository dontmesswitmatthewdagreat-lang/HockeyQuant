-- HockeyQuant — Stanley Cup system: the maximum salary cap = the real NHL cap,
-- scaling each season. Run once in the Supabase SQL editor. Idempotent.
--
-- A manager's Cap Space (earned from picks) is now clamped to that season's real
-- NHL upper limit, so you can never field a roster richer than a real NHL team's
-- cap. The ceiling rises every year with the actual NHL cap (values below, from
-- the NHL/NHLPA's announced three-year schedule).

-- 1. The real NHL salary-cap upper limit by season (start year) -------------
create table if not exists public.season_caps (
    season_year int primary key,
    cap_dollars bigint not null
);

insert into public.season_caps (season_year, cap_dollars) values
    (2021, 81500000),
    (2022, 82500000),
    (2023, 83500000),
    (2024, 88000000),
    (2025, 95500000),    -- 2025-26
    (2026, 104000000),   -- 2026-27 (announced)
    (2027, 113500000)    -- 2027-28 (announced)
on conflict (season_year) do update set cap_dollars = excluded.cap_dollars;

-- 2. Grading clamps earned Cap Space at the season's NHL cap ----------------
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
    v_season  int;
    v_cap_max bigint;
begin
    if p_actual_winner is null then return; end if;

    for r in
        select * from public.user_picks
        where game_date = p_game_date and away_team = p_away and home_team = p_home
          and correct is null and pick_type = 'ML'
    loop
        v_correct := upper(r.pick) = upper(p_actual_winner);
        v_beat    := v_correct and r.model_pick is not null and upper(r.model_pick) <> upper(p_actual_winner);
        v_cap     := (case when v_correct then 1000000 else 0 end) + (case when v_beat then 500000 else 0 end);

        -- Season for this pick (Oct–Jun spans two calendar years) → that year's NHL cap.
        v_season := (case
            when extract(month from r.game_date::date) >= 9 then extract(year from r.game_date::date)
            when extract(month from r.game_date::date) <= 4 then extract(year from r.game_date::date) - 1
            else extract(year from r.game_date::date) end)::int;
        v_cap_max := coalesce(
            (select cap_dollars from public.season_caps where season_year = v_season),
            (select cap_dollars from public.season_caps order by season_year desc limit 1));

        update public.user_picks
           set correct = v_correct, xp_awarded = v_cap
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
            cap_space      = least(v_cap_max::int, us.cap_space + v_cap),   -- clamp at the NHL cap
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
