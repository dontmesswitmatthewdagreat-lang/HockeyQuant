-- HockeyQuant — My Franchise badges (migration 020).
-- Adds card-collection achievements to the existing achievements table; they're awarded
-- server-side by the franchise router and show up on the existing badges strip. Idempotent.

insert into public.achievements (id, name, description, icon, sort) values
    ('fr_collector',  'Collector',     'Own 30 player cards.',            'rectangle.stack.fill',    20),
    ('fr_legend',     'Legendary',     'Own a Legend-rarity card.',       'sparkles',                21),
    ('fr_dream_team', 'Dream Team',    'Fill all 12 lineup slots.',       'person.3.sequence.fill',  22),
    ('fr_challenger', 'Challenger',    'Play a nightly challenge.',       'flame.fill',              23),
    ('fr_upset',      'Upset Special', 'Win a nightly challenge.',        'trophy.fill',             24),
    ('fr_scout',      'Bird Dog',      'Draft a rookie card.',            'binoculars.fill',         25)
on conflict (id) do update set
    name = excluded.name, description = excluded.description, icon = excluded.icon, sort = excluded.sort;
