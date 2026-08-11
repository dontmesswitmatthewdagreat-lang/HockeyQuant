-- HockeyQuant — earning Puck Freeze shields
-- Run once in the Supabase SQL editor. Idempotent.
--
-- 029 taught the grader to *spend* shields but nothing ever granted one, so the
-- mechanic could never fire. Shields are now earned every 7th consecutive
-- correct pick, capped at 3 in hand.
--
-- Earning off the streak (rather than daily logins) keeps the reward tied to
-- the thing being protected: the shield you spend to save a streak is one an
-- earlier streak paid for. The cap stops a long run banking enough shields to
-- make the streak effectively unbreakable, which would drain the tension the
-- streak is there to create.

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
    v_correct       boolean;
    v_beat          boolean;
    v_xp            int;
    v_p             numeric;
    v_odds_mult     numeric;
    v_streak_mult   numeric;
    v_streak        int;
    v_shields       int;
    v_shield_used   boolean;
    v_shield_earned boolean;
    v_new_streak    int;
    v_new_shields   int;
    v_already_saved boolean;
    c_shield_every  constant int := 7;
    c_shield_cap    constant int := 3;
begin
    if p_actual_winner is null then return; end if;

    for r in
        select * from public.user_picks
        where game_date = p_game_date and away_team = p_away and home_team = p_home
          and correct is null and pick_type = 'ML'
    loop
        v_correct := upper(r.pick) = upper(p_actual_winner);
        v_beat    := v_correct and r.model_pick is not null and upper(r.model_pick) <> upper(p_actual_winner);

        select coalesce(current_streak, 0), coalesce(streak_shields, 0)
          into v_streak, v_shields
          from public.user_stats where user_id = r.user_id;
        v_streak  := coalesce(v_streak, 0);
        v_shields := coalesce(v_shields, 0);

        -- Odds weighting. Clamped at both ends: the floor stops a mis-stored
        -- longshot minting unbounded XP, the ceiling keeps a near-lock worth
        -- slightly more than nothing. Null win_prob scores as it did before.
        if r.win_prob is null or r.win_prob <= 0 then
            v_odds_mult := 1.0;
        else
            v_p := greatest(0.10, least(0.95, r.win_prob));
            v_odds_mult := least(3.0, power(1.0 / v_p, 0.6));
        end if;

        -- Gentle kicker, not a second exponential — stacked on the odds term it
        -- would run away on a hot week.
        v_streak_mult := 1.0 + (least(v_streak, 10) * 0.03);

        if v_correct then
            v_xp := round(10 * v_odds_mult * v_streak_mult);
        else
            v_xp := 2;
        end if;
        if v_beat then
            v_xp := v_xp + 15;
        end if;

        -- At most one save per slate, or one bad night drains the stock in a
        -- single grading run.
        select exists(
            select 1 from public.streak_shield_uses
             where user_id = r.user_id and game_date = p_game_date::date
        ) into v_already_saved;

        v_shield_used := (not v_correct) and v_shields > 0 and v_streak > 0 and not v_already_saved;

        v_new_streak := case
            when v_correct     then v_streak + 1
            when v_shield_used then v_streak
            else 0
        end;

        -- Earned on every 7th consecutive correct pick, while under the cap.
        v_shield_earned := v_correct
                       and v_new_streak > 0
                       and (v_new_streak % c_shield_every) = 0
                       and v_shields < c_shield_cap;

        v_new_shields := least(
            c_shield_cap,
            greatest(0, v_shields
                        - (case when v_shield_used   then 1 else 0 end)
                        + (case when v_shield_earned then 1 else 0 end))
        );

        update public.user_picks
           set correct = v_correct, xp_awarded = v_xp
         where id = r.id;

        insert into public.user_stats as us (
            user_id, total_xp, level, picks_made, picks_correct, beats_model,
            current_streak, best_streak, streak_shields, shields_earned_total,
            last_graded_date, updated_at
        )
        values (
            r.user_id, v_xp, 1, 1,
            (case when v_correct then 1 else 0 end),
            (case when v_beat then 1 else 0 end),
            v_new_streak, v_new_streak, v_new_shields,
            (case when v_shield_earned then 1 else 0 end),
            p_game_date, now()
        )
        on conflict (user_id) do update set
            total_xp       = us.total_xp + v_xp,
            picks_made     = us.picks_made + 1,
            picks_correct  = us.picks_correct + (case when v_correct then 1 else 0 end),
            beats_model    = us.beats_model + (case when v_beat then 1 else 0 end),
            current_streak = v_new_streak,
            best_streak    = greatest(us.best_streak, v_new_streak),
            streak_shields = v_new_shields,
            shields_earned_total = us.shields_earned_total + (case when v_shield_earned then 1 else 0 end),
            last_graded_date = p_game_date,
            updated_at     = now();

        if v_shield_used then
            insert into public.streak_shield_uses (user_id, game_date, streak_kept)
            values (r.user_id, p_game_date::date, v_streak)
            on conflict (user_id, game_date) do nothing;
        end if;

        update public.user_stats
           set level = 1 + (total_xp / 100)
         where user_id = r.user_id;

        perform public.award_achievements(r.user_id);
    end loop;
end;
$$;
