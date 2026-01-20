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

**Teams:**
- `GET /api/teams` - All 32 teams with division/conference info
- `GET /api/teams/{abbrev}` - Team details (standings, xG, goalies, injuries, form)
- `GET /api/teams/{abbrev}/goalies` - Team's goalie stats (GSAX, SV%, GAA)
- `GET /api/divisions` - NHL division structure

**Accuracy:**
- `GET /api/accuracy/stats` - Accuracy with filters (date range, team, confidence)
- `GET /api/accuracy/trend` - Rolling accuracy trend data for charts
- `POST /api/accuracy/store-predictions/{date}` - Store predictions before games (cron)
- `POST /api/accuracy/update-results/{date}` - Update results after games (cron)
- `POST /api/accuracy/update-all-pending` - Batch update all pending results
- `GET /api/accuracy/first-game-time/{date}` - For scheduling cron jobs
- `GET /api/accuracy/last-game-time/{date}` - Game day cutoff time
- `GET /api/accuracy/debug` - Supabase connection diagnostics

### Database
Supabase (PostgreSQL) for storing predictions and tracking accuracy:

**`predictions` table** - Flat records for accuracy tracking:
- `game_date`, `game_id`, `away_team`, `home_team`
- `away_score`, `home_score`, `pick`, `confidence`, `diff`
- `away_final`, `home_final`, `actual_winner`, `correct` (nullable, filled after games)
- `predicted_at` - Timestamp when official prediction was locked
- `goalie_confirmed_away`, `goalie_confirmed_home` - Boolean flags for goalie confirmation status

**`daily_predictions` table** - Full JSON cache for instant API responses:
- `game_date` (unique), `games_count`, `predictions` (JSON array)
- `updated_at`, `first_game_time`

**`profiles` table** - User profiles for authentication:
- `id`, `username`, `favorite_team`, `created_at`

### Deployment
- Frontend: Vercel (hockeyquant.vercel.app)
- Backend: Render (hockeyquant.onrender.com)
- CI/CD: GitHub Actions for accuracy automation and Windows builds

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

### Pages (8 total)
| Page | Route | Features |
|------|-------|----------|
| Home | `/` | Navigation cards, data source attribution, "Coming Soon" placeholders |
| Predictions | `/predictions` | Date picker, client caching (5-min TTL), official/estimated status banners |
| Teams | `/teams` | Conference/division grouping, team detail modal, goalie stats, injuries |
| Accuracy | `/accuracy` | Quick stats cards, confidence breakdown, filters, trend chart, recent predictions table |
| About | `/about` | About me section, model methodology explanation |
| Account | `/account` | User settings, favorite team selector, profile management (auth required) |
| Login | `/login` | Email/password auth via Supabase |
| Signup | `/signup` | Registration with email verification |

### Key Components
| Component | Purpose |
|-----------|---------|
| `Navbar.jsx` | Responsive nav with hamburger menu, auth-aware user menu |
| `GameCard.jsx` | Prediction display with status banner (official/estimated), confidence badge, goalie confirmation indicators |
| `AccuracyChart.jsx` | Recharts line chart with rolling/cumulative accuracy, window selector |
| `ProgressBar.jsx` | Animated loading with cycling status messages |
| `UserMenu.jsx` | Avatar dropdown with account links and logout |
| `LoginForm.jsx` / `SignupForm.jsx` | Supabase authentication forms |

### Advanced Frontend Features
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

### Frontend
| File | Purpose |
|------|---------|
| `frontend/src/api.js` | API client with all endpoint functions |
| `frontend/src/context/AuthContext.jsx` | Supabase auth state management |
| `frontend/src/pages/Predictions.jsx` | Predictions UI with caching (official model, no goalie overrides) |
| `frontend/src/pages/Accuracy.jsx` | Accuracy dashboard with filters and charts |
| `frontend/src/pages/Teams.jsx` | Team browser with detail modals |
| `frontend/src/components/GameCard.jsx` | Individual game prediction card |
| `frontend/src/components/AccuracyChart.jsx` | Trend visualization with Recharts |

## Data Sources

- **NHL API** (`api-web.nhle.com`): Schedules, standings, game results, team schedules
- **MoneyPuck** (CSV feeds): xG (expected goals), goalie metrics (GSAX), skater stats
- **ESPN** (web scraped): Injury reports with player importance scoring
- **Daily Faceoff** (web scraped): Confirmed starting goalies

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

### Frontend
- react 19, react-dom, react-router-dom 7 (UI framework)
- @supabase/supabase-js (authentication & database)
- recharts (data visualization)
- vite (build tool)
