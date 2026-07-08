-- Ranking history snapshots: one row per prospect per sync day, so the app can
-- show trend arrows (rank_delta) and a ranking sparkline in the detail sheet.
create table if not exists prospect_rankings (
    id bigserial primary key,
    nhl_id bigint not null,
    list_date date not null,
    category_id int,
    rank int not null,
    unique (nhl_id, list_date)
);

create index if not exists idx_prospect_rankings_nhl_id on prospect_rankings (nhl_id, list_date desc);
create index if not exists idx_prospect_rankings_date on prospect_rankings (list_date desc);

alter table prospect_rankings enable row level security;
create policy "prospect_rankings read" on prospect_rankings for select using (true);
