"""
Supabase client for HockeyQuant
"""

import os
from supabase import create_client, Client

# Get credentials from environment variables
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")

_client: Client = None


def get_supabase() -> Client:
    """Get or create Supabase client instance"""
    global _client
    if _client is None:
        if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
            raise ValueError("Missing SUPABASE_URL or SUPABASE_SERVICE_KEY environment variables")
        _client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    return _client
