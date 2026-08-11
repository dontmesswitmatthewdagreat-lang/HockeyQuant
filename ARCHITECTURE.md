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
