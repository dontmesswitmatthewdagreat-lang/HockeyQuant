# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HockeyQuant is an NHL game prediction system with two interfaces:
- **Desktop App** (PyQt6): Standalone application at root (`NHL_Moneyline_Generator_APP_Phase3.py`)
- **Web App** (React + FastAPI): Full-stack app in `web/` folder

## Development Commands

### Backend (FastAPI)
```bash
cd web/backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```
API docs available at http://localhost:8000/docs

### Frontend (React + Vite)
```bash
cd web/frontend
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
`web/backend/services/analyzer.py` - The NHLAnalyzer class powers all predictions:
- Fetches data from NHL API, MoneyPuck (xG stats), ESPN (injuries)
- Calculates: fatigue/travel penalties, goalie metrics (GSAX), streaks, special teams, H2H history
- Scoring formula: `base_score * fatigue_mult * streak_mult * st_mult * injury_mult * h2h_mult`

### API Endpoints
- `GET /api/predictions/{date}` - Game predictions for a date (YYYY-MM-DD)
- `POST /api/predictions/{date}` - Predictions with custom goalie overrides
- `GET /api/teams` - All teams with current stats
- `GET /api/teams/{abbrev}/goalies` - Team's goalie stats
- `GET /api/accuracy/stats` - Historical prediction accuracy

### Database
Supabase (PostgreSQL) for storing predictions and tracking accuracy. Config in `web/database/`.

### Deployment
- Frontend: Vercel (hockeyquant.vercel.app)
- Backend: Render (hockeyquant.onrender.com)
- CI/CD: GitHub Actions for accuracy automation and Windows builds

## Key Files

| File | Purpose |
|------|---------|
| `web/backend/services/analyzer.py` | Core prediction engine (NHLAnalyzer) |
| `web/backend/services/data_loader.py` | External data fetcher (MoneyPuck, ESPN) |
| `web/backend/services/constants.py` | Team mappings, timezones, divisions |
| `web/backend/routers/predictions.py` | Prediction API endpoints |
| `web/frontend/src/api.js` | Frontend API client |
| `web/frontend/src/pages/Predictions.jsx` | Main predictions UI |

## Data Sources

- **NHL API** (`api-web.nhle.com`): Schedules, standings, game results
- **MoneyPuck**: xG (expected goals), goalie metrics (GSAX)
- **ESPN**: Injury reports (web scraped)
