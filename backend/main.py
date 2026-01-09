"""
HockeyQuant API
FastAPI backend for NHL game predictions
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import predictions, teams, accuracy

# Create FastAPI app
app = FastAPI(
    title="HockeyQuant API",
    description="NHL Game Prediction API powered by advanced analytics",
    version="1.0.0",
)

# CORS middleware - allow frontend to make requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",  # React dev server
        "http://localhost:5173",  # Vite dev server
        "https://hockeyquant.vercel.app",  # Vercel frontend
        "https://frontend-pi-beige-13.vercel.app",  # Vercel frontend (alt)
        "https://hockeyquant.com",  # Production domain (future)
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(predictions.router, prefix="/api", tags=["predictions"])
app.include_router(teams.router, prefix="/api", tags=["teams"])
app.include_router(accuracy.router, prefix="/api", tags=["accuracy"])


@app.get("/")
async def root():
    """API root - health check"""
    return {
        "name": "HockeyQuant API",
        "version": "1.0.0",
        "status": "healthy",
        "docs": "/docs",
    }


@app.get("/health")
async def health_check():
    """Health check endpoint for deployment platforms"""
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
