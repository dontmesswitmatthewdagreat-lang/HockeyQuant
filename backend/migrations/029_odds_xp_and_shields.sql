-- HockeyQuant — odds-weighted XP + Puck Freeze streak shields
-- Run once in the Supabase SQL editor. Idempotent.
--
-- Replaces the flat XP award (10 correct / 2 wrong / +15 beat-the-model) with
-- one scaled by how unlikely the called result was, and teaches the grader to
-- spend a shield instead of resetting a streak.
--
-- Why the probability lives on the pick rather than being looked up at grading
-- time: it isn't available at grading time. `predictions` has no probability
-- column — `ml_home_prob` only ever exists inside the `daily_predictions` JSON
-- blob and the live API response. Recording it on the pick is also the fairer
-- reading: you're rewarded for the risk you took *when you took it*, not for a
-- number that moved after a goalie was confirmed.

alter table public.user_picks add column if not exists win_prob numeric;

comment on column public.user_picks.win_prob is
    'Model win probability (0-1) for the picked team, captured when the pick was
     placed. Null on picks made before odds-weighting shipped — those fall back
     to the flat award.';

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
    v_correct      boolean;
    v_beat         boolean;
    v_xp           int;
    v_p            numeric;
    v_odds_mult    numeric;
    v_streak_mult  numeric;
    v_streak       int;
    v_shields      int;
    v_shield_used  boolean;
    v_new_streak   int;
    v_already_saved boolean;
begin
    if p_actual_winner is null then return; end if;

    for r in
        select * from public.user_picks
        where game_date = p_game_date and away_team = p_away and home_team = p_home
          and correct is null and pick_type = 'ML'
    loop
        v_correct := upper(r.pick) = upper(p_actual_winner);
        v_beat    := v_correct and r.model_pick is not null and upper(r.model_pick) <> upper(p_actual_winner);

        -- Standing before this pick is applied.
        select coalesce(current_streak, 0), coalesce(streak_shields, 0)
          into v_streak, v_shields
          from public.user_stats where user_id = r.user_id;
        v_streak  := coalesce(v_streak, 0);
        v_shields := coalesce(v_shields, 0);

        -- Odds weighting. Clamped at both ends: the floor stops a mis-stored
        -- 1% longshot minting unbounded XP, the ceiling keeps a near-lock worth
        -- slightly more than nothing. Null win_prob (picks placed before this
        -- shipped) scores exactly as it did before.
        if r.win_prob is null or r.win_prob <= 0 then
            v_odds_mult := 1.0;
        else
            v_p := greatest(0.10, least(0.95, r.win_prob));
            v_odds_mult := least(3.0, power(1.0 / v_p, 0.6));
        end if;

        -- Streak is a gentle kicker, not a second exponential — stacked on the
        -- odds multiplier it would run away on a hot week.
        v_streak_mult := 1.0 + (least(v_streak, 10) * 0.03);

        if v_correct then
            v_xp := round(10 * v_odds_mult * v_streak_mult);
        else
            v_xp := 2;      -- consolation stays flat; bravery isn't rewarded for being wrong
        end if;
        if v_beat then
            v_xp := v_xp + 15;
        end if;

        -- Puck Freeze: absorb one loss rather than resetting. Only when there's
        -- a streak worth saving, and at most one save per slate — otherwise a
        -- bad night would drain the whole stock in one grading run.
        select exists(
            select 1 from public.streak_shield_uses
             where user_id = r.user_id and game_date = p_game_date::date
        ) into v_already_saved;

        v_shield_used := (not v_correct) and v_shields > 0 and v_streak > 0 and not v_already_saved;

        v_new_streak := case
            when v_correct     then v_streak + 1
            when v_shield_used then v_streak      -- held, not advanced
            else 0
        end;

        update public.user_picks
           set correct = v_correct, xp_awarded = v_xp
         where id = r.id;

        insert into public.user_stats as us (
            user_id, total_xp, level, picks_made, picks_correct, beats_model,
            current_streak, best_streak, streak_shields, last_graded_date, updated_at
        )
        values (
            r.user_id, v_xp, 1, 1,
            (case when v_correct then 1 else 0 end),
            (case when v_beat then 1 else 0 end),
            v_new_streak, v_new_streak,
            greatest(0, v_shields - (case when v_shield_used then 1 else 0 end)),
            p_game_date, now()
        )
        on conflict (user_id) do update set
            total_xp       = us.total_xp + v_xp,
            picks_made     = us.picks_made + 1,
            picks_correct  = us.picks_correct + (case when v_correct then 1 else 0 end),
            beats_model    = us.beats_model + (case when v_beat then 1 else 0 end),
            current_streak = v_new_streak,
            best_streak    = greatest(us.best_streak, v_new_streak),
            streak_shields = greatest(0, us.streak_shields - (case when v_shield_used then 1 else 0 end)),
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
