"""Regression: the Redis-backed response cache must serve GET /api/shaders.

`state._create_cache_backend()` used to pass `serializer={"class": "..."}` (the
config-dict form that only `caches.add()` understands). With REDIS_URL set,
aiocache 0.12.x then called `.loads` on a dict and `GET /api/shaders` answered
500 ("'dict' object has no attribute 'loads'"). Every other suite runs on the
in-memory cache, so nothing noticed.
"""

from __future__ import annotations

import asyncio
import json
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from storage_manager import config, state
from storage_manager.app import app
from tests.test_webhook_tokens import FakeBucket


@pytest.fixture()
def redis_cache(redis_server, monkeypatch):
    """Point state.cache at a real Redis through the production factory."""
    monkeypatch.setattr(state, "REDIS_URL", f"redis://127.0.0.1:{redis_server}/0")
    monkeypatch.setattr(state, "REDIS_HOST", None)
    backend = state._create_cache_backend()
    assert type(backend).__name__ == "RedisCache", "factory fell back to the in-memory cache"
    monkeypatch.setattr(state, "cache", backend)
    yield backend
    try:
        asyncio.run(backend.close())
    except RuntimeError:
        pass  # pool was bound to the TestClient's (now closed) loop


def test_cache_backend_uses_a_serializer_instance(redis_cache):
    # The dict form is what broke: aiocache calls .dumps/.loads on this attribute.
    assert callable(getattr(redis_cache.serializer, "loads", None))
    assert callable(getattr(redis_cache.serializer, "dumps", None))


def test_list_shaders_with_redis_cache(redis_cache, monkeypatch):
    bucket = FakeBucket()
    index = [
        {"id": "a", "name": "Alpha", "stars": 4.5, "tags": ["generative"]},
        {"id": "b", "name": "Beta", "stars": 2.0, "tags": []},
    ]
    bucket.blob(config.STORAGE_MAP["shader"]["index"]).upload_from_string(json.dumps(index))
    monkeypatch.setattr(state, "bucket", bucket)
    monkeypatch.setattr(state, "io_executor", ThreadPoolExecutor(max_workers=2))

    # `with` keeps one event loop for both requests; a bare TestClient starts a new loop
    # per request, which a pooled Redis connection cannot survive.
    with TestClient(app) as client:
        first = client.get("/api/shaders")
        assert first.status_code == 200, first.text
        assert [s["id"] for s in first.json()] == ["a", "b"]  # sorted by rating

        # Second call is a cache hit: delete the bucket object to prove it is served from Redis.
        bucket.objects.clear()
        second = client.get("/api/shaders")
        assert second.status_code == 200, second.text
        assert second.json() == first.json()
