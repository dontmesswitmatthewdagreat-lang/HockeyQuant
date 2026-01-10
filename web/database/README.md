# Database Configuration

This folder contains the Supabase client configurations for HockeyQuant.

## Files

- **supabase_client.py** - Python REST client for backend (FastAPI)
- **supabaseClient.js** - JavaScript client for frontend (React)

## Environment Variables

### Backend
Set these in your environment or `.env` file:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-key
```

### Frontend
Set in `frontend/.env`:
```
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

## Database Tables

- `daily_predictions` - Stores pre-computed predictions for each game date
- `prediction_results` - Tracks prediction accuracy after games complete

## Notes

The Python client uses a custom REST implementation (httpx) instead of the official Supabase Python SDK to avoid connection issues in serverless environments.
