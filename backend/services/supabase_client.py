"""
Supabase REST client for HockeyQuant
Uses direct REST API calls instead of the Python client to avoid connection issues
"""

import os
import httpx
from typing import Optional, List, Dict, Any


class SupabaseClient:
    """Simple Supabase REST client"""

    def __init__(self, url: str, key: str):
        self.url = url.rstrip('/')
        self.key = key
        self.rest_url = f"{self.url}/rest/v1"
        self.headers = {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        }

    def table(self, name: str) -> "TableQuery":
        return TableQuery(self, name)


class TableQuery:
    """Query builder for Supabase tables"""

    def __init__(self, client: SupabaseClient, table: str):
        self.client = client
        self.table = table
        self.params: Dict[str, str] = {}
        self._select_cols = "*"

    def select(self, columns: str = "*") -> "TableQuery":
        self._select_cols = columns
        self.params["select"] = columns
        return self

    def eq(self, column: str, value: Any) -> "TableQuery":
        self.params[column] = f"eq.{value}"
        return self

    def gte(self, column: str, value: Any) -> "TableQuery":
        self.params[column] = f"gte.{value}"
        return self

    def lte(self, column: str, value: Any) -> "TableQuery":
        self.params[column] = f"lte.{value}"
        return self

    def is_(self, column: str, value: str) -> "TableQuery":
        self.params[column] = f"is.{value}"
        return self

    def not_is(self, column: str, value: str) -> "TableQuery":
        self.params[column] = f"not.is.{value}"
        return self

    def order(self, column: str, desc: bool = False) -> "TableQuery":
        direction = "desc" if desc else "asc"
        self.params["order"] = f"{column}.{direction}"
        return self

    def limit(self, count: int) -> "TableQuery":
        self.params["limit"] = str(count)
        return self

    def execute(self) -> "QueryResult":
        url = f"{self.client.rest_url}/{self.table}"
        with httpx.Client(timeout=30.0) as http:
            response = http.get(url, headers=self.client.headers, params=self.params)
            response.raise_for_status()
            return QueryResult(response.json())

    def insert(self, records: List[Dict[str, Any]]) -> "QueryResult":
        url = f"{self.client.rest_url}/{self.table}"
        with httpx.Client(timeout=30.0) as http:
            response = http.post(url, headers=self.client.headers, json=records)
            response.raise_for_status()
            return QueryResult(response.json())

    def update(self, data: Dict[str, Any]) -> "UpdateQuery":
        return UpdateQuery(self.client, self.table, data, self.params)


class UpdateQuery:
    """Update query builder"""

    def __init__(self, client: SupabaseClient, table: str, data: Dict[str, Any], params: Dict[str, str]):
        self.client = client
        self.table = table
        self.data = data
        self.params = params.copy()

    def eq(self, column: str, value: Any) -> "UpdateQuery":
        self.params[column] = f"eq.{value}"
        return self

    def execute(self) -> "QueryResult":
        url = f"{self.client.rest_url}/{self.table}"
        with httpx.Client(timeout=30.0) as http:
            response = http.patch(url, headers=self.client.headers, params=self.params, json=self.data)
            response.raise_for_status()
            return QueryResult(response.json())


class QueryResult:
    """Result wrapper"""

    def __init__(self, data: Any):
        self.data = data if isinstance(data, list) else [data] if data else []


# Global client instance
_client: Optional[SupabaseClient] = None


def get_supabase() -> Optional[SupabaseClient]:
    """Get or create Supabase client instance. Returns None if env vars not configured."""
    global _client
    if _client is None:
        # Load env vars at call time (not module load time)
        supabase_url = os.getenv("SUPABASE_URL", "").strip()
        supabase_key = os.getenv("SUPABASE_SERVICE_KEY", "").strip()
        if not supabase_url or not supabase_key:
            # Return None to allow fallback to on-demand computation
            return None
        _client = SupabaseClient(supabase_url, supabase_key)
    return _client
