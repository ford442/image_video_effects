# storage_manager/middleware.py
import time
import asyncio
from typing import Dict, List
from fastapi import Request
from fastapi.responses import PlainTextResponse
from starlette.middleware.base import BaseHTTPMiddleware

from .config import RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW, RATE_LIMIT_PATHS, RATE_LIMIT_IP_HEADER


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, requests: int = RATE_LIMIT_REQUESTS, window: int = RATE_LIMIT_WINDOW, path_prefixes=None):
        super().__init__(app)
        self.requests = requests
        self.window = window
        self.path_prefixes = path_prefixes or RATE_LIMIT_PATHS
        self.counters: Dict[str, List[float]] = {}
        self.lock = asyncio.Lock()

    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if not any(path.startswith(prefix) for prefix in self.path_prefixes):
            return await call_next(request)

        client_ip = request.headers.get(RATE_LIMIT_IP_HEADER, "")
        if client_ip:
            client_ip = client_ip.split(",")[0].strip()
        if not client_ip and request.client is not None:
            client_ip = request.client.host
        if not client_ip:
            client_ip = "unknown"

        key = f"{client_ip}:{request.method}:api"
        now = time.time()

        async with self.lock:
            entry = self.counters.get(key)
            if entry is None or entry[1] <= now:
                self.counters[key] = [1, now + self.window]
            else:
                entry[0] += 1
            count, reset = self.counters[key]

        if count > self.requests:
            retry_after = max(1, int(reset - now))
            return PlainTextResponse(
                "Too many requests",
                status_code=429,
                headers={"Retry-After": str(retry_after)},
            )

        response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(self.requests)
        response.headers["X-RateLimit-Remaining"] = str(max(0, self.requests - count))
        response.headers["X-RateLimit-Reset"] = str(int(reset))
        return response
