-- HockeyQuant — Stanley Cup system: scale Cap Space to real NHL dollars
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Player costs are now real cap hits (league min ~$0.78M up to ~$12-13M for elites,
-- set by routers/fantasy.py + a re-sync). This rescales the Cap Space EARNED per
-- pick to match: a correct pick pays $1.0M, beating the model adds $0.5M. Only the
-- v_cap payout line changes vs migration 015. Existing balances stay (everyone is
-- at 0 from the reset, so the new scale applies cleanly going forward).

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
        -- Cap Space in real dollars: a correct call earns $1.0M of cap, beating the model +$0.5M.
        v_cap     := (case when v_correct then 1000000 else 0 end) + (case when v_beat then 500000 else 0 end);

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
