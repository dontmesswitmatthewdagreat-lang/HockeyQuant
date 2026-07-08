-- Daily player-value snapshots: powers the market index chart, per-player
-- value sparklines, and "today's movers". Run once in the Supabase SQL editor.
create table if not exists player_values (
    id bigserial primary key,
    snap_date date not null,
    name text not null,
    team text,
    position text,
    aav numeric,
    model_value numeric not null,
    market_value numeric not null,
    unique (name, snap_date)
);

create index if not exists idx_player_values_date on player_values (snap_date desc);
create index if not exists idx_player_values_name on player_values (name, snap_date desc);

alter table player_values enable row level security;
create policy "player_values read" on player_values for select using (true);
