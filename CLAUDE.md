# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HockeyQuant is an NHL game prediction system with two interfaces:
- **Desktop App** (PyQt6): Standalone application at root (`NHL_Moneyline_Generator_APP_Phase3.py`)
- **Web App** (React + FastAPI): `backend/` and `frontend/` folders

## Development Commands

### Backend (FastAPI)
```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```
API docs available at http://localhost:8000/docs

### Frontend (React + Vite)
```bash
cd frontend
npm install
npm run dev          # Dev server at http://localhost:5173
npm run build        # Production build
npm run lint         # ESLint
```

### Desktop App
```bash
python NHL_Moneyline_Generator_APP_Phase3.py
```

## Architecture

### Core Prediction Engine
`backend/services/analyzer.py` - The NHLAnalyzer class powers all predictions:
- Fetches data from NHL API, MoneyPuck (xG stats), ESPN (injuries), Daily Faceoff (confirmed starters)
- Calculates: fatigue/travel penalties, goalie metrics (GSAX), streaks, special teams, H2H history
- Scoring formula: `base_score * fatigue_mult * streak_mult * st_mult * injury_mult * h2h_mult`
- Confidence levels: STRONG (≥10pt diff), MODERATE (≥5pt), CLOSE (<5pt)

### Goal Prediction Engine (Betting Lines)
`backend/services/goal_predictor.py` - Dixon-Coles/Poisson model for actual goal predictions:
- Separate from quality-score moneyline — predicts actual expected goals per team
- Blends MoneyPuck xG (65%) with actual goals (35%) for offensive/defensive strength
- Adjusts for: goalie GSAX, fatigue, injuries, special teams, home ice (+3%)
- Poisson probability matrix (11×11) for spread and total probabilities
- Used for: puck line predictions, over/under predictions, optimal alternate lines

### Odds Fetcher
`backend/services/odds_fetcher.py` - Fetches real sportsbook lines from The Odds API:
- Free tier (500 req/month), 30-minute in-memory cache
- Provides spreads (puck line) and totals (O/U) from DraftKings/FanDuel
- Graceful fallback: defaults to ±1.5 puck line and model-estimated O/U if no API key

### API Endpoints

**Predictions:**
- `GET /api/predictions/{date}` - Game predictions with per-game official status (checks cache first)
- `GET /api/predictions/today` - Convenience endpoint for current day
- `POST /api/predictions/{date}` - DISABLED (goalie overrides not available for official model)
- `GET /api/predictions/status/{date}` - Lightweight polling for cache status
- `GET /api/games/{date}` - Basic game list without full analysis

**Prediction Response Fields:**
- `game_time` - ISO timestamp of game start (UTC)
- `is_official` - True if within 15-min window before game (locked)
- `official_at` - ISO timestamp when prediction becomes official
- `goalie_status_away/home` - "confirmed" or "expected" based on Daily Faceoff
- `betting_lines` - Puck line and O/U predictions with Poisson probabilities:
  - `away_expected_goals`, `home_expected_goals`, `predicted_total`, `predicted_margin`
  - `puck_line`, `puck_line_source`, `puck_line_home_cover_prob`, `puck_line_away_cover_prob`
  - `over_under`, `over_under_source`, `over_prob`, `under_prob`, `push_prob`
  - `optimal_spread`, `optimal_spread_prob`, `optimal_spread_side`
  - `optimal_total`, `optimal_total_prob`, `optimal_total_rec`

**Teams:**
- `GET /api/teams` - All 32 teams with division/conference info
- `GET /api/teams/{abbrev}` - Team details (standings, xG, goalies, injuries, form, advanced stats)
- `GET /api/teams/{abbrev}/goalies` - Team's goalie stats (GSAX, SV%, GAA)
- `GET /api/divisions` - NHL division structure

**AI Summary:**
- `POST /api/summary` - Generate AI explanation for a prediction pick (Groq/Llama, cached per game per day)

**Accuracy:**
- `GET /api/accuracy/stats` - Accuracy with filters (date range, team, confidence)
- `GET /api/accuracy/trend` - Rolling accuracy trend data for charts
- `POST /api/accuracy/store-predictions/{date}` - Store predictions before games (cron)
- `POST /api/accuracy/update-results/{date}` - Update results after games (cron)
- `POST /api/accuracy/update-all-pending` - Batch update all pending results + backfill PL/O/U grades
- `POST /api/accuracy/backfill` - Backfill puck line and O/U picks and grades for existing predictions
- `GET /api/accuracy/first-game-time/{date}` - For scheduling cron jobs
- `GET /api/accuracy/last-game-time/{date}` - Game day cutoff time
- `GET /api/accuracy/debug` - Supabase connection diagnostics

**User Models (auth required):**
- `GET /api/models` - List user's models with accuracy stats
- `POST /api/models` - Create new model (weights must sum to 100)
- `GET /api/models/{id}` - Get model details with accuracy
- `PUT /api/models/{id}` - Update model name/description/weights
- `DELETE /api/models/{id}` - Delete model and its predictions
- `GET /api/models/{id}/predictions/{date}` - Get predictions using custom weights

### Database
Supabase (PostgreSQL) for storing predictions and tracking accuracy:

**`predictions` table** - Flat records for accuracy tracking:
- `game_date`, `game_id`, `away_team`, `home_team`
- `away_score`, `home_score`, `pick`, `confidence`, `diff`
- `away_final`, `home_final`, `actual_winner`, `correct` (nullable, filled after games)
- `predicted_at` - Timestamp when official prediction was locked
- `goalie_confirmed_away`, `goalie_confirmed_home` - Boolean flags for goalie confirmation status
- `puck_line_pick` ("home"/"away"), `puck_line_line` (float), `puck_line_correct` (nullable bool)
- `ou_pick` ("over"/"under"), `ou_line` (float), `ou_correct` (nullable bool, null on pushes)

**`daily_predictions` table** - Full JSON cache for instant API responses:
- `game_date` (unique), `games_count`, `predictions` (JSON array)
- `updated_at`, `first_game_time`

**`profiles` table** - User profiles for authentication:
- `id`, `username`, `favorite_team`, `created_at`

**`user_models` table** - Custom user prediction models:
- `id`, `user_id`, `name`, `description`
- `weights` (JSON): `{offense, defense, goaltending, points_pct, win_rate}` - must sum to 100
- `is_active`, `created_at`, `updated_at`

**`model_predictions` table** - Track predictions per model:
- `id`, `model_id`, `game_id`, `game_date`
- `away_team`, `home_team`, `pick`, `away_score`, `home_score`, `confidence`
- `actual_winner`, `correct` (filled after games)

### Deployment
- Frontend: Vercel (hockeyquant.vercel.app)
- Backend: Render (hockeyquant.onrender.com)
- CI/CD: GitHub Actions for accuracy automation and Windows builds
- **Environment Variables (Render):** `GROQ_API_KEY` required for AI summaries, `ODDS_API_KEY` optional for real sportsbook lines

### Per-Game Prediction Scheduling
Predictions become "official" 15 minutes before each individual game start time:

**How it works:**
1. GitHub Actions cron runs every 10 minutes during game hours (5 PM - 1 AM ET)
2. Each run calls `POST /api/accuracy/store-predictions/{date}`
3. Endpoint checks each game: if `current_time >= game_time - 15 minutes` AND not already stored, locks the prediction
4. Locked predictions are stored in `predictions` table for accuracy tracking
5. `daily_predictions` cache is always updated with current status for all games

**Prediction States:**
- **Estimated** (yellow banner): Before 15-min window, may change as goalie info updates
- **Official** (green banner): Within 15-min window, locked for accuracy tracking

**Goalie Confirmation:**
- Daily Faceoff scraper detects "Confirmed" vs "Expected" status
- Shown as checkmark (✓) or question mark (?) badges on game cards

## Frontend Features

### Pages (7 total)
| Page | Route | Features |
|------|-------|----------|
| Games | `/` | Main landing, date navigation, summary stats, 2-column game cards with team logos |
| Teams | `/teams` | Conference/division grouping, team detail modal, goalie stats, injuries |
| Models | `/models` | Custom prediction models with configurable weights, accuracy tracking per model |
| About | `/about` | About me section, model methodology explanation |
| Account | `/account` | User settings, favorite team selector, profile management (auth required) |
| Login | `/login` | Email/password auth via Supabase |
| Signup | `/signup` | Registration with email verification |

### Key Components
| Component | Purpose |
|-----------|---------|
| `Navbar.jsx` | Responsive nav with hamburger menu, auth-aware user menu |
| `GameCard.jsx` | Prediction display with confidence banners, "Predicted Winner" label, per-team goalie badges, expandable AI summary ("Why [team]?") |
| `AccuracyChart.jsx` | Recharts line chart with rolling/cumulative accuracy, window selector |
| `ProgressBar.jsx` | Animated loading with cycling status messages |
| `UserMenu.jsx` | Avatar dropdown with account links and logout |
| `LoginForm.jsx` / `SignupForm.jsx` | Supabase authentication forms |

### Advanced Frontend Features
- **Dark Mode**: Toggle via ThemeContext, persisted to localStorage, CSS variables with `[data-theme="dark"]` selectors
- **AI Game Summaries**: Expandable "Why [team]?" button on each GameCard, powered by Groq (llama-3.1-8b-instant), cached per game per day
- **GameCard Redesign**: Confidence color banners (green/yellow/gray), "Predicted Winner" centered label, 100px team logos, per-team goalie status badges (confirmed ✓ / expected ?)
- **Advanced Team Stats**: Tabbed view in team detail modal — Overview, Advanced (Corsi%, Fenwick%, xG%, PDO), Goalies
- **Client-side Caching**: Module-level cache with 5-min TTL, cache indicators in UI
- **Per-Game Status Display**: Official (green) vs Estimated (yellow) status banners, goalie confirmation badges
- **Authentication**: Supabase auth with session management, protected routes, user profiles
- **Accuracy Visualization**: Multi-metric charts, window selection (10/20/30/50 games), date/team/confidence filters
- **Mobile Responsive**: Hamburger menu, touch-friendly UI, responsive tables and grids

## Key Files

### Backend
| File | Purpose |
|------|---------|
| `backend/main.py` | FastAPI app with CORS, routers, health checks |
| `backend/services/analyzer.py` | Core prediction engine (NHLAnalyzer) |
| `backend/services/data_loader.py` | External data fetcher (MoneyPuck, ESPN, Daily Faceoff) |
| `backend/services/constants.py` | Team mappings, timezones, divisions |
| `backend/routers/predictions.py` | Prediction API endpoints with caching |
| `backend/routers/teams.py` | Team and goalie API endpoints |
| `backend/routers/accuracy.py` | Accuracy tracking, storage, trend analysis |
| `backend/routers/models.py` | User custom models CRUD, predictions with custom weights |
| `backend/routers/summary.py` | AI game explanation endpoint (Groq/Llama), in-memory cache |
| `backend/services/goal_predictor.py` | Dixon-Coles/Poisson goal prediction + probability math |
| `backend/services/odds_fetcher.py` | The Odds API client for sportsbook lines |

### Frontend
| File | Purpose |
|------|---------|
| `frontend/src/api.js` | API client with all endpoint functions |
| `frontend/src/context/AuthContext.jsx` | Supabase auth state management |
| `frontend/src/context/ThemeContext.jsx` | Dark mode toggle, localStorage persistence, `data-theme` attribute |
| `frontend/src/pages/Predictions.jsx` | Games UI with date nav, summary stats, 2-column grid |
| `frontend/src/pages/Teams.jsx` | Team browser with detail modals |
| `frontend/src/pages/Models.jsx` | User custom models with weight sliders |
| `frontend/src/components/GameCard.jsx` | Game card with team logos, win probability badges |
| `frontend/src/components/ModelCard.jsx` | Model display with weight distribution bars |
| `frontend/src/components/CreateModelModal.jsx` | Create/edit model form with weight sliders |
| `frontend/src/utils/teamLogos.js` | NHL CDN logo URLs and team name mappings |

## Data Sources

- **NHL API** (`api-web.nhle.com`): Schedules, standings, game results, team schedules
- **MoneyPuck** (CSV feeds): xG (expected goals), goalie metrics (GSAX), skater stats
- **ESPN** (web scraped): Injury reports with player importance scoring
- **Daily Faceoff** (web scraped): Confirmed starting goalies
- **The Odds API** (`api.the-odds-api.com`): Sportsbook spreads (puck line) and totals (O/U)

## Prediction Multipliers

| Factor | Range | Description |
|--------|-------|-------------|
| Fatigue | 0.93-1.02 | Back-to-back, rest days, travel patterns, road trips |
| Streak | 0.95-1.05 | Hot/cold form vs season average, win/loss streaks |
| Special Teams | 0.95-1.05 | PP% vs opponent PK% matchup analysis |
| Injuries | 0.90-1.00 | Weighted by player importance (points, ice time, xG) |
| Head-to-Head | 0.94-1.06 | Recent matchup history (division/conference aware) |

## Dependencies

### Backend
- fastapi, uvicorn, gunicorn (web framework)
- pandas, requests, httpx (data processing)
- beautifulsoup4 (web scraping)
- pydantic (validation)
- groq (AI summary generation via Groq API)

### Frontend
- react 19, react-dom, react-router-dom 7 (UI framework)
- @supabase/supabase-js (authentication & database)
- recharts (data visualization)
- vite (build tool)
