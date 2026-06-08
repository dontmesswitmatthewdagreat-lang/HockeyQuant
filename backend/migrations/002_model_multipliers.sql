-- HockeyQuant — custom-model "factor emphasis" levers.
-- Adds per-factor intensity columns to user_models. 1.0 = official behavior,
-- 0 = ignore the factor, 2.0 = double its effect. Defaults keep every existing
-- model identical to before. Run in the Supabase SQL editor (HockeyQuant project).

alter table public.user_models add column if not exists mult_fatigue        real not null default 1.0;
alter table public.user_models add column if not exists mult_streak         real not null default 1.0;
alter table public.user_models add column if not exists mult_special_teams  real not null default 1.0;
alter table public.user_models add column if not exists mult_injuries       real not null default 1.0;
alter table public.user_models add column if not exists mult_h2h            real not null default 1.0;
