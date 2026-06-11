"""
HockeyQuant API
FastAPI backend for NHL game predictions
"""

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import predictions, teams, accuracy, models, summary, fantasy, news, prospects, pickem, shotmap, whatif

# Create FastAPI app
app = FastAPI(
    title="HockeyQuant API",
    description="NHL Game Prediction API powered by advanced analytics",
    version="1.0.0",
)

# CORS middleware - allow frontend to make requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for now
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(predictions.router, prefix="/api", tags=["predictions"])
app.include_router(teams.router, prefix="/api", tags=["teams"])
app.include_router(accuracy.router, prefix="/api", tags=["accuracy"])
app.include_router(models.router, prefix="/api", tags=["models"])
app.include_router(summary.router, prefix="/api", tags=["summary"])
app.include_router(fantasy.router, prefix="/api", tags=["fantasy"])
app.include_router(news.router, prefix="/api", tags=["news"])
app.include_router(prospects.router, prefix="/api", tags=["prospects"])
app.include_router(pickem.router, prefix="/api", tags=["pickem"])
app.include_router(shotmap.router, prefix="/api", tags=["shotmap"])
app.include_router(whatif.router, prefix="/api", tags=["whatif"])


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
