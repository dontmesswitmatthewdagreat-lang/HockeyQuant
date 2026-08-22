# HockeyQuant — Architecture Primer

Context document for handing to an AI assistant. Describes how the system is
built, where things live, and the non-obvious constraints that have caused real
bugs. Written 2026-08.

> `CLAUDE.md` in this repo predates the iOS app and covers only the original
> React/FastAPI web product. Where the two disagree, this file is current.

---

## 1. What it is

An NHL prediction and analytics product. Two independent prediction engines
score every game; every prediction is stored and graded afterwards, so accuracy
is tracked publicly. Around that core sit news, fantasy/collection game modes,
a custom-model builder, and an offseason GM simulator.

It displays odds and probabilities but never accepts wagers — that boundary is
deliberate and affects App Store review.

## 2. Stack and deployment

| Piece | Tech | Host |
|---|---|---|
| iOS app | Swift 6, SwiftUI, iOS 17 target, XcodeGen | TestFlight/App Store (not yet shipped) |
| Backend | Python, FastAPI, gunicorn/uvicorn | Render (`hockeyquant.onrender.com`), auto-deploys on push to `main` |
| Database + auth | Supabase (Postgres) | Supabase cloud |
| Web app (legacy) | React 19 + Vite | Vercel |
| Scheduled jobs | GitHub Actions cron | GitHub |

Render's free tier spins down when idle, so cold starts are real: `keep-warm.yml`
pings `/health` (note: **`/health`, not `/api/health`**) every 10 minutes, and
cron jobs pre-warm before hitting heavy endpoints. Client code must tolerate a
30–60s first response.

## 3. Repo layout

```
backend/
  main.py              FastAPI app; registers every router with prefix="/api"
  routers/             HTTP layer, one module per domain
  services/            All logic. Routers stay thin.
  migrations/*.sql     Ordered, hand-run (see §7)
frontend/              Legacy React web app
ios/
  project.yml          XcodeGen spec — .xcodeproj is generated, gitignored
  HockeyQuant/
    App/               Entry point, root view
    Core/              AuthStore, Supa client, TeamInfo, ThemeStore
    Networking/        APIClient + Decodable models
    DesignSystem/      Theme, Card, CrestView, TeamGlyph, TeamSprite
    Features/          One folder per surface (see §6)
  Tools/               Dev scripts (sprite rendering, image→sprite conversion)
art/sprites/           Source art for crest sprites
.github/workflows/     Cron jobs
```

## 4. Backend

### Routers
`predictions, teams, accuracy, models, summary, fantasy, news, prospects,
pickem, shotmap, whatif, franchise, offseason, market, duels`

All are mounted in `main.py` with `prefix="/api"`. **A router must not set its
own `/api` prefix** or paths double up.

Auth: `get_user_id_from_token(authorization)` (defined in `routers/pickem.py`,
re-exported through `routers/fantasy.py`) validates the Supabase JWT and returns
the user id. Endpoints take `authorization: Optional[str] = Header(None)`.

### Key services

- **`analyzer.py`** — moneyline engine. Produces *quality scores* in the 30–70
  range via multipliers: fatigue/travel, streak, special teams, injuries, H2H.
- **`goal_predictor.py`** — Dixon-Coles/Poisson engine. Produces *expected
  goals* in the 1.5–5.5 range; drives puck line, over/under and the scoreline
  grid.
- **`player_market.py`** — contract valuations, market heat, and the Offseason
  Report Card (grades a team's summer; includes a bounded LLM "context" pass).
- **`trade_store.py`** — durable trade ledger (§8).
- **`duels.py` / `duel_scoring.py`** — ranked weekly head-to-head: matchmaking,
  snake draft with randomly offered pools, weekly scoring, Elo.
- **`news_registry.py` / `news_sources.py` / `news_digester.py`** — source
  adapters (RSS, Google News, Reddit, Bluesky), ingestion, and digest building.
- **`league_pulse.py`** — league-wide dials (luck meter, race tightness, etc.).
- **`season_sim.py`, `whatif.py`, `model_engine.py`, `shot_map.py`** — the
  quant/Playground tools and user-defined models.
- **`supabase_client.py`** — see §7, it is not the official SDK.
- **`llm.py`** — Groq wrapper (`groq_chat`). All LLM use is bounded and
  optional; every caller must work when it fails.

### ⚠️ Never conflate the two score types
`away_score`/`home_score` at the top level of a prediction are **quality
scores** (30–70). `betting_lines.away_expected_goals`/`home_expected_goals` are
**expected goals** (1.5–5.5). Feeding quality scores into Poisson math produces
plausible nonsense. This has bitten before.

## 5. Data model (Supabase)

Grouped by domain; see `migrations/` for exact columns.

- **Predictions/accuracy** — `predictions` (flat, one row per graded game),
  `daily_predictions` (JSON cache for fast reads), `daily_parlays`
- **Users** — `profiles`, `user_stats`, `achievements`, `user_achievements`,
  `user_picks`
- **Custom models** — `user_models` (weights JSON, `model_type`, `ml_meta`),
  `model_predictions`
- **Fantasy/franchise** — `fantasy_players` (the player catalogue: `nhl_id`,
  `roster_pos`, `cost`, `is_goalie`, `is_prospect`), `franchises`,
  `franchise_cards`, `franchise_lineup`, `shop_rotation`,
  `franchise_challenges`, `rookie_picks`, `card_listings`, `card_offers`
- **News** — `news_items` (flat archive, FTS, 120-day retention), `news_digests`
- **Market** — `player_values`, `trade_players`, `trade_picks`
- **Duels** — `duels`, `duel_picks`, `duel_rankings`, `duel_queue`
- **Draft** — mock draft + lottery tables, `prospect_rankings`

`fantasy_players.cost` doubles as the general player-value signal — franchise
card rarity and duel depth tiers both derive from it, which avoids fragile
name-matching against other sources.

## 6. iOS app

Five tabs: **Schedule, News, Play, Models, Statistics**. Feature folders:
`Today, News, Play, Fantasy, Franchise, Duels, Offseason, Models, Stats, Teams,
GameDetail, Profile, Onboarding, Premium`.

- **`APIClient`** — one `perform(method, url, token:body:)` core with optional
  bearer auth; JSON decoding uses `.convertFromSnakeCase`, so backend
  `chosen_name` arrives as Swift `chosenName` automatically.
- **`AuthStore`** — Supabase auth. `accessToken()` is an **async function**, not
  a property. `userId` returns an **uppercased** UUID while Postgres stores it
  lowercase — always case-fold before comparing, or you will silently render
  another user's data as the current user's.
- **`ThemeStore`** — the favorite team themes the whole app. `Theme.Palette.*`
  are plain statics SwiftUI can't observe, so `ThemeStore.generation` bumps and
  `RootView().id(theme.generation)` forces a rebuild on team change.
- **`CrestView`** — original team crests: a 24×24 hand-authored pixel sprite
  (`TeamSprite`) where one exists, else an SF Symbol (`TeamGlyph`), else a
  monogram. **No NHL logos anywhere in the app** — see §9.

New Swift files require `cd ios && xcodegen generate` before they appear in the
project.

## 7. Hard-won constraints

These are the things that have actually caused bugs. Read before changing
related code.

1. **Migrations are run by hand.** The developer pastes `migrations/NNN_*.sql`
   into the Supabase SQL editor. Nothing applies them automatically. Write them
   idempotent (`create table if not exists`, guarded policy blocks) and assume
   a new table does not exist until confirmed.

2. **`services/supabase_client.py` is a custom httpx REST wrapper, not
   `supabase-py`.** It supports `select/eq/gte/lte/gt/lt/filter/is_/not_is/
   ilike/in_/or_/order/limit/offset/insert/upsert/update/delete`. There is
   **no `.neq()`** and no `.range()`. `in_()` values may need manual quoting.
   `upsert` is merge-duplicates: only the columns you send get written.
   PostgREST caps reads at 1000 rows — paginate aggregations.

3. **Row Level Security** is on for user tables. The backend uses the service
   key and bypasses RLS; policies exist for direct client reads. Writes that
   must enforce rules (turn order, ownership) go through the backend only.

4. **The LazyVStack accessibility hang.** A `LazyVStack` of stateful rows can
   wedge the main thread at 100% CPU during the offscreen accessibility pass.
   The News feed uses a plain `VStack` with explicit paging for this reason —
   do not "optimize" it back.

5. **Pixel-art crests are judged with `ios/Tools/render_sprites.py`, not
   simulator screenshots.** Screenshots are downscaled far past what 24×24 art
   can be assessed at; shapes that look fine enlarged turn to mush at crest
   size.

6. **Verify a deploy with something only the new code returns.** Polling an
   endpoint that already existed proves nothing and has produced false
   "deployed" reads.

7. **ISO8601 with fractional seconds** — Postgres timestamps need
   `.withFractionalSeconds` or Swift parsing silently returns nil.

8. **GitHub Actions cron must use `TZ='America/New_York'`** for game dates. The
   NHL API uses ET; UTC dates put evening games on the wrong day.

## 8. Scraped sources are hostile — treat them as such

External feeds change shape and drop history without warning. Two failures
already rewrote every team's Offseason Report Card:

- Spotrac changed its transactions markup, so the trade parser silently matched
  nothing.
- Spotrac's transactions feed is a **rolling window** (~7 real pages; pages
  beyond the last are clamped duplicates) and **purges at the league-year
  rollover**, so June trades vanished in August.

The response pattern, which should be reused for any scraped source:

- **Persist to Postgres and treat the DB as the system of record.**
- **Sync jobs are additive.** An empty scrape is a no-op, never a wipe.
- **Reads serve the union of stored data and the live fetch**, so either leg can
  fail alone without taking the feature down.
- **Never cache an empty result.**

Sources: NHL API (`api-web.nhle.com`), MoneyPuck (xG, GSAX), ESPN (injuries),
Daily Faceoff (starting goalies), Spotrac (contracts/transactions), The Odds
API, plus news RSS/Reddit/Bluesky.

## 9. Legal boundaries baked into the product

- **No NHL logos or team marks.** Crests are original art. This is a trademark
  constraint and also App Store guideline 5.2.5. Pixelating or restyling a logo
  does not change this — a derivative of the mark is still the mark.
- **No wagering.** Odds and probabilities are informational only.
- **News is headline + snippet + link**, never full article text.
- Known outstanding issues: the legacy web frontend still hotlinks real NHL
  logos from `assets.nhle.com`, and the backend pulls unlicensed NHL player
  photography. Both need resolving before charging money.

## 10. Running it

```bash
# Backend
cd backend && pip install -r requirements.txt
uvicorn main:app --reload --port 8000        # docs at /docs

# iOS
cd ios && xcodegen generate                   # after adding/removing files
# then build the HockeyQuant scheme for a simulator

# Legacy web
cd frontend && npm install && npm run dev
```

Secrets live in `backend/.env`: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`,
`GROQ_API_KEY`, optional `ODDS_API_KEY`. The Supabase anon key for iOS is in
`ios/HockeyQuant/Core/SupabaseConfig.swift` (gitignored).

## 11. Conventions

- Logic in `services/`, HTTP in `routers/`. Routers stay thin.
- Every external call degrades gracefully — a failed scrape, LLM call or photo
  fetch must never take down the endpoint around it.
- LLM output is always bounded and always optional: the deterministic result
  must survive the model failing or returning nonsense.
- Comments explain constraints and non-obvious "why", not what the code does.

---

## 12. Ranked play: duels, XP, and shields (added 2026-08)

### Where grading actually happens
**Pick XP is awarded by a plpgsql function, not Python.**
`grade_user_picks_for_game` (created in `001_gamification.sql`, replaced by 029
and 030) does the whole job: marks picks correct, awards XP, moves the streak,
spends and grants shields, then calls `award_achievements`. Changing any of that
is a migration, not a code change. Nothing in `routers/` writes `user_stats`
except the franchise XP credit at `routers/franchise.py:104`.

Picks are written **client-side straight to Supabase** (`GamificationStore.submitPick`),
not through the backend. The only backend reference to `user_picks` is a read.

### Odds-weighted XP
`XP = 10 × (1/P)^0.6 × (1 + 0.03 × min(streak,10))`, `P` clamped to [0.10, 0.95],
odds multiplier capped at 3.0, `+15` for beating the model, flat `2` for a miss.
Roughly: 0.95 → 10 XP, 0.50 → 15, 0.10 → 30.

`P` comes from **`user_picks.win_prob`, captured when the pick is placed** — it is
*not* available at grading time. `predictions` has no probability column at all;
`ml_home_prob` exists only inside the `daily_predictions` JSON and the live API
response. Recording it on the pick is also the fairer reading: the user is paid
for the risk taken at decision time, not for odds that moved afterwards. A null
`win_prob` (pre-029 picks) scores exactly as the old flat award did.

The streak term is deliberately linear, not a second exponential — stacked on the
odds multiplier it runs away on a hot week.

### Puck Freeze shields
Earned every 7th consecutive correct pick, capped at 3 (`030`). One absorbs a loss
instead of resetting the streak, at most one save per slate.

Every save writes a `streak_shield_uses` row. That table exists because **a
mechanic the player can't see reads as a bug** — a streak that quietly survives a
loss looks like broken grading, not a reward. The same reasoning drives the UI:
`PlayView` shows the streak and shield pips together, and announces a save for
three days after it fires.

The cap is load-bearing. Without it a long run banks enough shields to make the
streak effectively unbreakable, which removes the tension the streak creates.

### Duels (weekly + Flash Slate)
One engine, `services/duels.py`, discriminated by `duels.mode`:

- **weekly** — Monday→Sunday, roster `C, LW, RW, D, D, G` (12 picks)
- **flash** — a single night, roster `C, LW, D, G` (8 picks)

Two mechanics carry the design:

**Depth slots are league-wide tiers.** Rank every player at a position by
`fantasy_players.cost` and cut every 32, so "2C" means roughly the second-line
centre of an average team and means the same to both drafters. That read is
paginated — a truncated player list silently reshapes every draft board.

**Scarcity buys away agency.** `TIER_OPTIONS = {1:2, 2:3, 3:4, 4:5}` — a 1C hands
you a star with almost no decision; a 4C is where reading matchups wins the week.

Pools are drawn at pick time, not duel creation, so they exclude everyone already
taken. The pool actually shown is stored on the pick so a draft can be replayed.
The pick clock restarts on each selection (`routers/duels.py:_turn_deadline`), and
a stalled draft autopicks rather than forfeits — a no-show would otherwise cost
the *opponent* their week.

Queue rows are keyed `(user_id, mode)`: you can wait for tonight and the week at
once, and queueing for one must not cancel the other.

Weekly scoring (`duel_scoring.py`) is skater points as the base plus a bonus of
plus/minus and shorthanded production, with goalies on wins/saves/GA/shutouts.
**Hits, blocks and takeaways are not available** — the NHL per-game log doesn't
carry them; they exist only in per-game boxscores.

### Model marketplace
`is_public` / `published_at` / `forked_from` / `fork_count` on `user_models`, plus
`model_forks` (unique on `(source_id, user_id)`).

Forks **copy by exclusion** — everything except identity, ownership, timestamps and
the source's publication state. The model schema has already gained columns twice
(multipliers, then `ml_meta`), and an explicit copy list silently drops them.

`fork_count` is only a cache of `model_forks`; reputation must stay recomputable
rather than being a counter that can only increase.

Listed at **`/api/marketplace/models`**, not `/models/public` — `GET
/models/{model_id}` is declared earlier and would match `"public"` as an id.

That endpoint serves **raw `user_models` rows**, so the client reassembles
weights from the `weight_*` columns and humanizes the `ml_meta.features` ids
itself — unlike `/api/models`, nothing is shaped for it. It also carries no
accuracy, so `ModelMarketplaceView` joins `/api/models/leaderboard` by model id;
that join is decoration and is allowed to fail on its own.

## 13. The ranked/marketplace UI

All three surfaces from the old "working but unreachable" list now have screens
(2026-08). What they are and where they hang:

- **Model marketplace** — `Features/Models/ModelMarketplaceView.swift`, reached
  from a full-width row under the Lab tool grid. Browse, sort by forks or joined
  accuracy, and fork. Publishing is a toggle on your own `ModelCard`
  (`MarketplacePublishRow`), which is why `/api/models` now returns `is_public`,
  `published_at`, `fork_count` and `forked_from` — the owner's list is where the
  decision is made, so it has to carry the state.
- **Duel scoreboard** — `Features/Duels/DuelScoreboardView.swift`, opened from
  the locked-roster card on the draft screen. The endpoint now also returns the
  drafted `slot` per player and both `names`, so the scoreboard names a roster
  spot the same way the draft board does.
- **Ranked ladder** — `Features/Duels/DuelRankingsView.swift`, on the draft
  screen's toolbar (present in every state, including "no duel this week").

Two things to know before touching these:

- **Everything degrades against an older backend on purpose.** Every new field
  is optional client-side: pre-deploy, the publish row reads "Private" and
  scoreboard rows fall back to position instead of slot. That is the app talking
  to a Render deploy that hasn't caught up, not a bug.
- **In the offseason a scoreboard is all zeros**, because scoring reads the NHL
  per-game log for the duel's week. To exercise it, point a duel's
  `week_start`/`week_end` at a played week — but note `/api/duels/current` only
  returns duels from the last ~7 days, so a back-dated duel disappears from the
  draft screen that links to it.

## 14. The draft room

`GET /api/prospects/draft-room` (`build_draft_room`) hands the app one payload —
pick order, the whole consensus board, per-team needs, the AI's scoring weights
— and the draft itself runs on device (`DraftRoomEngine`, `Features/Draft/`).
Same split as `MonteCarloEngine`, for a specific reason: a request per pick would
put a Render cold start between a user and their next selection.

`DraftRoomEngine` is a **port of `build_mock_draft`'s pick rule**, not a second
opinion — the AI GMs have to behave like the mock the user reads all season. The
weights ride along in the payload so retuning the mock retunes the room without
an app release.

**Once a class has been drafted the room becomes a re-draft.** `is_redraft` flips
on real results, the order becomes the true first round, and each board entry
carries where the league actually took that player, so a finished draft is scored
against reality. That's also why the board hides `actual` during the draft and
only reveals it in the verdict.

Order resolution is a cascade: real results → the stored internal mock → a full
`_resolve_order` (which fetches news and calls an LLM, so it is a last resort).
⚠️ The stored mock **must** be the `source = 'HockeyQuant'` row: `mock_drafts`
also holds imported insider mocks (023), which are partial — an article listing
19 of 32 picks would run the room out of teams mid-draft.

### Lottery re-roll and trades

Both run on device beside the draft itself.

**`DraftLottery`** re-runs the real two-draw lottery, including the rule that a
team may climb at most 10 places — which is why only lottery positions 1–11 can
win the first pick. It draws from **`standings_order`** (reverse standings), not
`order`: that one already has a lottery applied, and in a re-draft it's the real
one, so drawing on top of it applies a second lottery and moves the wrong teams.
Because slot *p* of the standings order is the pick of the team sitting *p*th,
permuting the standings carries pick ownership along with it. Known
simplification: restricting each draw to teams that can legally reach the pick
renormalizes the odds, so an eligible team wins slightly more often than its
published number (18.5% → ~19.7%).

**`DraftTrades`** prices a slot with a shifted power law
(`1000 · ((n+3)/4)^-0.75`): #5 ≈ 595, #32 ≈ 196, #64 ≈ 121. An exponential was
tried first and is wrong in a way that matters — it collapses past round one,
pricing a second-rounder at ~2% of a first, which makes future picks worthless
as currency and quietly kills trading up. AI GMs accept at a 6% premium, so
moving down pays and moving up one slot near the top costs about a future 2nd.

⚠️ Trading away the pick you're on the clock with hands the turn back to an AI
GM. The AI loop has already exited by then, so `DraftBoardView.onTraded` must
restart it — without that the draft stops dead on "…is picking".

### Lineup builder

`LineupBuilder` / `LineupBuilderView`, reached from the draft results. It fills a
real 4-line / 3-pair / 2-goalie depth chart from `GET /api/fantasy/players?team=`
(the `team` filter was added for this) and lets you drop a drafted prospect in to
see who he pushes down.

Lines are ordered by `fantasy_players.cost`, the same value signal the draft
board and franchise card rarity use — one definition of "better" across the app
rather than a third. Handedness is honoured (LHD left, RHD right), with a
same-group fallback so a club short a natural RHD still dresses a full lineup
instead of showing a hole. A prospect has no cap value yet, so a line's total
visibly *drops* when you promote him — that's the honest read, not a bug.

## 15. Advanced metrics

`services/advanced_metrics.py` + `routers/advanced.py`, surfaced on the team page.
All of it comes from MoneyPuck data the app already downloaded — `data_loader.py`
was filtering to `situation == 'all'` and discarding the rest, so `team_5on5`,
`team_other` and `skater_5on5` were added beside the existing slices at zero
network cost.

**The goal-differential decomposition is an exact identity, not a model.** Within
a strength state, `(xGF−xGA) + (GF−xGF) − (GA−xGA)` collapses algebraically to
`GF−GA`. The API returns the computed `residual` at both levels and the card
shows a warning if it isn't zero — that's the tripwire for MoneyPuck renaming or
adding a strength state. ⚠️ `situation == 'other'` (3-on-3 OT, 4-on-4, empty net)
is load-bearing: it's worth +14 goals to EDM, and dropping it turns an exact
identity into a wrong one.

⚠️ **MoneyPuck's `gameScore` column is unusable** — byte-identical between the
'all' and '5on5' rows for 98% of skaters, and it credits 49.42 to a player with
153 shorthanded seconds. Game Score is computed from components in `_game_score`,
in one place, so live reads and snapshots can't diverge.

⚠️ **Never sum skater rows to get a team total.** A traded player appears once
with his season total on one team, inflating summed team ice time by ~7%. Team
numbers always come from the team frame.

The percentile floor is calibrated, not guessed: 300 minutes ranks ~73% of
skaters while excluding *zero* players with 55+ games. An earlier 20-hour floor
dropped Brayden Point, Brady Tkachuk and Mark Stone, which makes the card look
broken for exactly the players people look up. Percentiles are always within
position group — a defenceman must not read as bottom-percentile for scoring
less than a winger.

**The team page and this card disagree on purpose.** The NHL awards a goal for
winning a shootout; the play-by-play these numbers come from doesn't. COL reads
+101 here and +99 in the standings, so the card says so rather than letting both
look wrong.

**Goalies** get the same treatment (`team_goalies` / `goalie_impact`,
`GoalieImpactSheet`), led by GSAx — goals saved above what the shots he actually
faced were worth, which is the only fair comparison across defences. Their floor
is 500 minutes, separate from the skater floor because goalies play far fewer.
⚠️ `rebound_control` is **rank-only, never display the raw value**: MoneyPuck's
xRebounds isn't calibrated against actual rebounds, so it comes out negative for
71 of 72 qualified goalies and the number would damn everyone. The ordering is
still meaningful, so it's ranked into a percentile and the figure stays hidden.

`TeamShotMapView` has a period filter and draws **only the attacking half**. All
shots are rotated 180° onto one end (`shot_map.py:62-63`) — a rotation, negating
*both* x and y, not an x-flip; an x-flip would scramble left/right and destroy
exactly the handedness signal the map is for. So the far half is always empty,
and cropping to `RinkGeometry.attackingHalf` doubles the scale of everything at
the same width. Unfolding to show both ends would just split one offence into two
half-strength blobs telling you which period it was; the period filter is the
honest version of that question, since the 2nd is the long change and the only
period with a structural reason to differ.

### Line chemistry

`services/line_metrics.py` + `LineChemistryView`, off the team page. Built on
MoneyPuck's `lines.csv`, which the app had never fetched.

⚠️ **`lines.csv` is loaded lazily and cached separately** (`DataLoader.lines_data`,
6h TTL), deliberately *not* inside `load_all_data`. That method re-raises on any
failure, so folding this file in would mean one 404 — plausible each autumn
before MoneyPuck posts the new season — taking down every prediction in the app.
A failed fetch serves the last good frame and never caches an empty result.

⚠️ **`lineId` is a concatenation of 7-digit player ids** — 21 digits for a
forward line, 14 for a pair. It overflows int64 and MoneyPuck wraps it in quotes,
so it must be read as text (`dtype={"lineId": str}`) and stripped; `line_player_ids`
returns `[]` on anything that isn't a clean multiple of 7 so an upstream format
change drops rows instead of producing garbage joins. Every id parsed this way
resolves in `skaters.csv`, so the join is exact — do not write a name matcher.

**Chemistry** is unit xGF% minus what its members manage in their *other* minutes,
with each member's baseline excluding this unit's own time (otherwise the unit
partly predicts itself). Those baselines are still contaminated by the members'
other shared units, so the UI calls it "vs. their other minutes", not a clean
effect, and clamps to ±15.

⚠️ **With/Without is defence-only, and that's a data limit, not an oversight.**
MoneyPuck lists only combinations that played 10+ minutes together, so listed
time doesn't sum to a player's total. For pairs the gap is ~2%; for forwards it's
~17–21%, because a settled duo gets rotated through many short-lived third-man
trios — time genuinely spent *with* the partner that lands in the "without"
bucket. That inflates the apart side by up to half, always in the same direction,
worst for exactly the star duos anyone would look up. Pairs below 90% coverage
are dropped rather than shown with a caveat, since a number beside a warning
still gets read as a number.

`RinkGeometry`, `RinkCanvas` and `HeatCanvas` all take an `xRange` so one code
path draws any slice of ice; the defaults are the full sheet, which is what the
per-game map (legitimately two-ended) keeps using. Two things to preserve if you
touch this:

- **Positions and distances need separate helpers.** `dx` maps a coordinate,
  `length` converts a span of feet. The old code got away with `dx(-100 + 4)` to
  mean "4 feet wide" only because the origin was fixed at −100; a shifted origin
  silently corrupts every width computed that way.
- **`HeatCanvas` splat width is specified in FEET, not cells**, so the blobs stay
  the same physical size when zoomed. Cell counts scale with the view instead
  (the half map passes `rows: 48` to match its doubled height, keeping cells the
  same size in points so the blur radius stays tuned).

`migrations/031_advanced_snapshots.sql` stores **raw counting components, never
derived metrics** — Game Score weights will be retuned, and an archive holding
`game_score` would silently invalidate its own history. MoneyPuck serves only
current cumulative totals, so windowed rates can only ever come from differencing
snapshots, and **history cannot be backfilled**: a day `advanced-snapshot.yml`
doesn't run is gone.

Deliberately not built, after checking the data: RAPM and GAR/xGAR (need
shift-level data — shift charts are never called), passing networks and graph
centrality (no pass-level data on any reachable endpoint; it's licensed tracking
data), per-game Game Score (the per-game log has no blocks, faceoffs or on-ice
shot attempts), and forward WOWY (`lines.csv` has a 600-second floor, so D-pairs
are 97.9% covered but forwards only 82.9% — the "without" bucket is overstated by
up to half for exactly the star duos anyone would look up). None of it feeds the
prediction engines, which keeps the graded record meaning one thing.

Also outstanding: nine `AsyncImage` sites still bypass `HQAsyncImage`
(`NewsView` ×4, `NewsStoryView`, `ProspectDetailSheet`, `PlayerMarketView` ×2,
`CardView`), and several `async def` handlers still call the blocking Supabase
client, which stalls the event loop — `routers/market.py`'s plain `def` is the
correct pattern there.

Migrations applied through **030**.
