# storage_manager/state.py
import json
import logging
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from typing import Dict, Optional

from .config import (
    REDIS_URL, REDIS_HOST, REDIS_PORT, REDIS_DB, REDIS_PASSWORD,
    CREDENTIALS_JSON
)

# OpenTelemetry initialization check
try:
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    _OTEL_AVAILABLE = True
except ImportError:
    _OTEL_AVAILABLE = False

# Structured Logging
_log_handler = logging.StreamHandler()
_log_handler.setFormatter(logging.Formatter("%(message)s"))
_struct_logger = logging.getLogger("storage_manager.sync")
_struct_logger.setLevel(logging.INFO)
if not _struct_logger.handlers:
    _struct_logger.addHandler(_log_handler)
_struct_logger.propagate = False


def _log_event(event: str, **kwargs) -> None:
    """Emit a structured JSON log line for intent state transitions."""
    record = {"event": event, "ts": datetime.utcnow().isoformat() + "Z", **kwargs}
    _struct_logger.info(json.dumps(record))


# Global Cloud Storage & I/O
gcs_client = None
bucket = None
io_executor = ThreadPoolExecutor(max_workers=20)

_has_signing_creds: bool = False
_media_semaphore: Optional[asyncio.Semaphore] = None


def _create_cache_backend():
    if REDIS_URL or REDIS_HOST:
        try:
            from urllib.parse import urlparse
            from aiocache import Cache

            if REDIS_URL:
                parsed = urlparse(REDIS_URL)
                host = parsed.hostname or "localhost"
                port = parsed.port or 6379
                password = parsed.password
                db = int(parsed.path.lstrip("/") or 0)
            else:
                host = REDIS_HOST
                port = REDIS_PORT
                password = REDIS_PASSWORD
                db = REDIS_DB

            return Cache(
                Cache.REDIS,
                endpoint=host,
                port=port,
                password=password,
                db=db,
                namespace="storage_manager",
                serializer={"class": "aiocache.serializers.JsonSerializer"},
            )
        except Exception as exc:
            _log_event("redis_cache_init_failed", error=str(exc))

    from aiocache import Cache
    return Cache(Cache.MEMORY)


cache = _create_cache_backend()

RESOURCE_LOCKS: Dict[str, asyncio.Lock] = {}


def get_resource_lock(resource_type: str) -> asyncio.Lock:
    """Return (creating if necessary) a per-resource asyncio.Lock."""
    if resource_type not in RESOURCE_LOCKS:
        RESOURCE_LOCKS[resource_type] = asyncio.Lock()
    return RESOURCE_LOCKS[resource_type]


async def clear_cache_for_type(item_type: Optional[str] = None) -> None:
    """Invalidate cache entries for a specific asset type or clear everything."""
    if item_type is None:
        await cache.clear()
        return

    patterns = {"library:all"}
    if item_type == "shader":
        patterns.update({"shaders:list", "shader:", "library:shader"})
    else:
        patterns.add(f"library:{item_type}")

    try:
        keys = await cache.keys("*")
    except Exception:
        await cache.clear()
        return

    for key in keys:
        if any(pattern in str(key) for pattern in patterns):
            await cache.delete(key)


def get_gcs_client():
    global gcs_client
    if gcs_client is None:
        from google.cloud import storage
        from google.oauth2 import service_account
        if CREDENTIALS_JSON:
            try:
                info = json.loads(CREDENTIALS_JSON)
                creds = service_account.Credentials.from_service_account_info(info)
                gcs_client = storage.Client(credentials=creds)
            except Exception:
                gcs_client = storage.Client()
        else:
            gcs_client = storage.Client()
    return gcs_client


async def run_io(func, *args, **kwargs):
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(io_executor, lambda: func(*args, **kwargs))
