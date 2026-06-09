"""
Tests for hardened /api/images/{image_id} and /api/videos/{video_id} endpoints.

Design B: signed-URL 302 redirect (primary), hardened proxy fallback (ADC/no-key).

Run with:
    pytest storage_manager/tests/test_streaming_endpoints.py -v

All tests use TestClient(follow_redirects=False) so 302 responses are
inspectable rather than followed.
"""

from __future__ import annotations

import asyncio
import json
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List, Optional
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Stub Google Cloud libs before importing the app (mirrors test_sync_endpoints)
# ---------------------------------------------------------------------------
import sys
import types

_gcs_stub = types.ModuleType("google.cloud.storage")
_gcs_stub.Client = MagicMock()

# Stub the retry sub-module that the proxy path imports at call time.
_gcs_retry_stub = types.ModuleType("google.cloud.storage.retry")
_gcs_retry_stub.DEFAULT_RETRY = MagicMock()
_gcs_stub.retry = _gcs_retry_stub

_google_stub = types.ModuleType("google")
_cloud_stub = types.ModuleType("google.cloud")
_auth_stub = types.ModuleType("google.oauth2")
_creds_stub = types.ModuleType("google.oauth2.service_account")
_creds_stub.Credentials = MagicMock()

for mod_name, mod in [
    ("google", _google_stub),
    ("google.cloud", _cloud_stub),
    ("google.cloud.storage", _gcs_stub),
    ("google.cloud.storage.retry", _gcs_retry_stub),
    ("google.oauth2", _auth_stub),
    ("google.oauth2.service_account", _creds_stub),
]:
    sys.modules.setdefault(mod_name, mod)

# ---------------------------------------------------------------------------
# Environment setup before import
# ---------------------------------------------------------------------------
import os

os.environ.setdefault("GCP_BUCKET_NAME", "test-bucket")

# ---------------------------------------------------------------------------
# Import app internals
# ---------------------------------------------------------------------------
import storage_manager.app as app_module
from storage_manager.app import (
    GCS_SIGNED_URL_EXPIRATION_SECONDS,
    GCS_SIGNED_URL_MAX_SECONDS,
    MEDIA_STREAM_MAX_CONCURRENT,
    app,
)

# ---------------------------------------------------------------------------
# Helpers: bucket + blob factories
# ---------------------------------------------------------------------------


def _make_startup_bucket() -> MagicMock:
    """Minimal mock bucket for the lifespan startup (shader-seeding)."""
    blob = MagicMock()
    blob.exists.return_value = False
    blob.download_as_text.return_value = "[]"
    blob.upload_from_string.return_value = None
    bucket = MagicMock()
    bucket.blob.return_value = blob
    bucket.list_blobs.return_value = iter([])
    bucket.copy_blob.return_value = None
    return bucket


def _make_gcs_client(startup_bucket: MagicMock) -> MagicMock:
    client = MagicMock()
    client.bucket.return_value = startup_bucket
    return client


def _make_image_blob(
    signed_url: str = "https://storage.googleapis.com/signed/img.png",
    exists: bool = True,
    size: int = 2048,
    data: bytes = b"fake-image-data",
) -> MagicMock:
    blob = MagicMock()
    blob.exists.return_value = exists
    blob.size = size
    blob.generate_signed_url.return_value = signed_url
    blob.download_as_bytes.return_value = data
    return blob


def _make_video_blob(
    signed_url: str = "https://storage.googleapis.com/signed/vid.mp4",
    exists: bool = True,
    size: int = 4096,
    data: bytes = b"fake-video-data",
) -> MagicMock:
    blob = MagicMock()
    blob.exists.return_value = exists
    blob.size = size
    blob.generate_signed_url.return_value = signed_url
    blob.download_as_bytes.return_value = data
    return blob


_IMAGE_ENTRY = {
    "id": "img-001",
    "filename": "test.png",
    "name": "Test Image",
}
_VIDEO_ENTRY = {
    "id": "vid-001",
    "filename": "test.mp4",
    "name": "Test Video",
}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def reset_rate_limiter():
    """Reset RateLimitMiddleware counters before each test to prevent
    cross-test rate-limit interference."""
    from storage_manager.app import RateLimitMiddleware

    mw = app.middleware_stack
    while mw is not None:
        if isinstance(mw, RateLimitMiddleware):
            mw.counters.clear()
            break
        mw = getattr(mw, "app", None)
    yield


@pytest.fixture()
def client_signed():
    """TestClient with signing credentials enabled (_has_signing_creds=True)."""
    from fastapi.testclient import TestClient

    startup_bucket = _make_startup_bucket()
    gcs_client = _make_gcs_client(startup_bucket)
    app_module.io_executor = ThreadPoolExecutor(max_workers=4)

    with patch("storage_manager.app.get_gcs_client", return_value=gcs_client):
        with TestClient(app, raise_server_exceptions=True) as c:
            app_module._has_signing_creds = True
            app_module._media_semaphore = asyncio.Semaphore(MEDIA_STREAM_MAX_CONCURRENT)
            yield c


@pytest.fixture()
def client_no_sign():
    """TestClient without signing credentials (_has_signing_creds=False → proxy)."""
    from fastapi.testclient import TestClient

    startup_bucket = _make_startup_bucket()
    gcs_client = _make_gcs_client(startup_bucket)
    app_module.io_executor = ThreadPoolExecutor(max_workers=4)

    with patch("storage_manager.app.get_gcs_client", return_value=gcs_client):
        with TestClient(app, raise_server_exceptions=True) as c:
            app_module._has_signing_creds = False
            app_module._media_semaphore = asyncio.Semaphore(MEDIA_STREAM_MAX_CONCURRENT)
            yield c


# ---------------------------------------------------------------------------
# Helper: configure a mock bucket for a single image/video request
# ---------------------------------------------------------------------------


def _configure_for_image(mock_bucket: MagicMock, image_blob: MagicMock) -> None:
    """Set up mock_bucket so that requests for 'img-001' resolve correctly."""
    def _blob(path: str) -> MagicMock:
        if path == "images/_images.json":
            b = MagicMock()
            b.exists.return_value = True
            b.download_as_text.return_value = json.dumps([_IMAGE_ENTRY])
            return b
        if path == f"images/{_IMAGE_ENTRY['filename']}":
            return image_blob
        b = MagicMock()
        b.exists.return_value = False
        b.download_as_text.return_value = "[]"
        return b

    mock_bucket.blob.side_effect = _blob


def _configure_for_video(mock_bucket: MagicMock, video_blob: MagicMock) -> None:
    """Set up mock_bucket so that requests for 'vid-001' resolve correctly."""
    def _blob(path: str) -> MagicMock:
        if path == "videos/_videos.json":
            b = MagicMock()
            b.exists.return_value = True
            b.download_as_text.return_value = json.dumps([_VIDEO_ENTRY])
            return b
        if path == f"videos/{_VIDEO_ENTRY['filename']}":
            return video_blob
        b = MagicMock()
        b.exists.return_value = False
        b.download_as_text.return_value = "[]"
        return b

    mock_bucket.blob.side_effect = _blob


# ---------------------------------------------------------------------------
# Tests: configuration / env-var defaults
# ---------------------------------------------------------------------------


class TestConfiguration:
    def test_default_expiration_is_3600(self):
        assert GCS_SIGNED_URL_EXPIRATION_SECONDS == int(
            os.environ.get("GCS_SIGNED_URL_EXPIRATION_SECONDS", "3600")
        )

    def test_expiration_clamped_to_max(self):
        """Expiration is capped at 604800 s regardless of env setting."""
        assert GCS_SIGNED_URL_EXPIRATION_SECONDS <= GCS_SIGNED_URL_MAX_SECONDS

    def test_default_max_concurrent_is_10(self):
        assert MEDIA_STREAM_MAX_CONCURRENT == int(
            os.environ.get("MEDIA_STREAM_MAX_CONCURRENT", "10")
        )


# ---------------------------------------------------------------------------
# Tests: image endpoint — signed-URL redirect (happy path)
# ---------------------------------------------------------------------------


class TestImageSignedRedirect:
    def test_returns_302(self, client_signed):
        c = client_signed
        blob = _make_image_blob(signed_url="https://signed.example.com/img.png")
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        assert resp.status_code == 302

    def test_location_header_is_signed_url(self, client_signed):
        c = client_signed
        expected_url = "https://signed.example.com/img.png?X-Goog-Signature=abc"
        blob = _make_image_blob(signed_url=expected_url)
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        assert resp.headers["location"] == expected_url

    def test_cache_control_header_set(self, client_signed):
        c = client_signed
        blob = _make_image_blob()
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        assert "cache-control" in resp.headers
        assert resp.headers["cache-control"] == "private, max-age=0"

    def test_generate_signed_url_called_with_correct_args(self, client_signed):
        c = client_signed
        blob = _make_image_blob()
        _configure_for_image(app_module.bucket, blob)

        c.get("/api/images/img-001", follow_redirects=False)

        blob.generate_signed_url.assert_called_once()
        call_kwargs = blob.generate_signed_url.call_args.kwargs
        assert call_kwargs.get("version") == "v4"
        assert call_kwargs.get("method") == "GET"


# ---------------------------------------------------------------------------
# Tests: image endpoint — 404 fail-fast
# ---------------------------------------------------------------------------


class TestImageNotFound:
    def test_missing_index_entry_returns_404(self, client_signed):
        """ID not in index → 404 without touching any blob or signed URL."""
        c = client_signed
        missing_blob = MagicMock()

        def _blob(path: str) -> MagicMock:
            b = MagicMock()
            b.exists.return_value = True
            b.download_as_text.return_value = "[]"  # empty index
            return b

        app_module.bucket.blob.side_effect = _blob

        resp = c.get("/api/images/nonexistent", follow_redirects=False)
        assert resp.status_code == 404
        missing_blob.generate_signed_url.assert_not_called()

    def test_blob_not_found_returns_404(self, client_signed):
        """Blob exists() == False → 404; generate_signed_url must NOT be called."""
        c = client_signed
        blob = _make_image_blob(exists=False)
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        assert resp.status_code == 404
        blob.generate_signed_url.assert_not_called()

    def test_blob_not_found_detail(self, client_signed):
        c = client_signed
        blob = _make_image_blob(exists=False)
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        assert "missing" in resp.json().get("detail", "").lower()


# ---------------------------------------------------------------------------
# Tests: video endpoint — signed-URL redirect (happy path)
# ---------------------------------------------------------------------------


class TestVideoSignedRedirect:
    def test_returns_302(self, client_signed):
        c = client_signed
        blob = _make_video_blob()
        _configure_for_video(app_module.bucket, blob)

        resp = c.get("/api/videos/vid-001", follow_redirects=False)
        assert resp.status_code == 302

    def test_location_header_is_signed_url(self, client_signed):
        c = client_signed
        expected_url = "https://signed.example.com/vid.mp4?X-Goog-Signature=xyz"
        blob = _make_video_blob(signed_url=expected_url)
        _configure_for_video(app_module.bucket, blob)

        resp = c.get("/api/videos/vid-001", follow_redirects=False)
        assert resp.headers["location"] == expected_url

    def test_missing_video_entry_returns_404(self, client_signed):
        c = client_signed

        def _blob(path: str) -> MagicMock:
            b = MagicMock()
            b.exists.return_value = True
            b.download_as_text.return_value = "[]"
            return b

        app_module.bucket.blob.side_effect = _blob

        resp = c.get("/api/videos/nonexistent", follow_redirects=False)
        assert resp.status_code == 404

    def test_blob_not_found_returns_404_without_sign(self, client_signed):
        c = client_signed
        blob = _make_video_blob(exists=False)
        _configure_for_video(app_module.bucket, blob)

        resp = c.get("/api/videos/vid-001", follow_redirects=False)
        assert resp.status_code == 404
        blob.generate_signed_url.assert_not_called()


# ---------------------------------------------------------------------------
# Tests: concurrent requests — signing path uses no per-request thread block
# ---------------------------------------------------------------------------


class TestConcurrency:
    def test_50_concurrent_image_requests_all_succeed(self, client_signed):
        """50 concurrent signed-URL redirects must all resolve without deadlock."""
        c = client_signed

        blob = _make_image_blob()
        _configure_for_image(app_module.bucket, blob)

        results: list[int] = []
        errors: list[Exception] = []
        lock = threading.Lock()

        def _do_request() -> None:
            try:
                r = c.get("/api/images/img-001", follow_redirects=False)
                with lock:
                    results.append(r.status_code)
            except Exception as exc:
                with lock:
                    errors.append(exc)

        threads = [threading.Thread(target=_do_request) for _ in range(50)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        assert not errors, f"Errors during concurrent requests: {errors}"
        assert all(s == 302 for s in results), f"Unexpected status codes: {set(results)}"
        assert len(results) == 50

    def test_50_concurrent_video_requests_all_succeed(self, client_signed):
        c = client_signed

        blob = _make_video_blob()
        _configure_for_video(app_module.bucket, blob)

        results: list[int] = []
        errors: list[Exception] = []
        lock = threading.Lock()

        def _do_request() -> None:
            try:
                r = c.get("/api/videos/vid-001", follow_redirects=False)
                with lock:
                    results.append(r.status_code)
            except Exception as exc:
                with lock:
                    errors.append(exc)

        threads = [threading.Thread(target=_do_request) for _ in range(50)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        assert not errors, f"Errors during concurrent requests: {errors}"
        assert all(s == 302 for s in results), f"Unexpected status codes: {set(results)}"
        assert len(results) == 50


# ---------------------------------------------------------------------------
# Tests: ADC / no-private-key fallback — proxy path, never 500
# ---------------------------------------------------------------------------


class TestAdcFallback:
    def test_image_falls_back_to_200_proxy(self, client_no_sign):
        """Without signing creds the endpoint must return 200 (proxy), not 5xx."""
        c = client_no_sign
        blob = _make_image_blob(data=b"img-bytes")
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        assert resp.status_code == 200
        assert resp.content == b"img-bytes"

    def test_video_falls_back_to_200_proxy(self, client_no_sign):
        c = client_no_sign
        blob = _make_video_blob(data=b"vid-bytes")
        _configure_for_video(app_module.bucket, blob)

        resp = c.get("/api/videos/vid-001", follow_redirects=False)
        assert resp.status_code == 200
        assert resp.content == b"vid-bytes"

    def test_signing_exception_falls_back_to_proxy(self, client_signed):
        """Even when _has_signing_creds is True, if generate_signed_url raises,
        the endpoint must fall back to proxy — never return 500."""
        c = client_signed

        blob = _make_image_blob(data=b"fallback-bytes")
        blob.generate_signed_url.side_effect = Exception("iam.signBlob denied")
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        # Must not be 500; acceptable responses are 200 (proxy) or 302 (retry)
        assert resp.status_code != 500
        assert resp.status_code in (200, 206)

    def test_no_generate_signed_url_called_on_adc_path(self, client_no_sign):
        """generate_signed_url must NOT be called when _has_signing_creds is False."""
        c = client_no_sign
        blob = _make_image_blob()
        _configure_for_image(app_module.bucket, blob)

        c.get("/api/images/img-001", follow_redirects=False)
        blob.generate_signed_url.assert_not_called()

    def test_proxy_returns_correct_media_type_image(self, client_no_sign):
        c = client_no_sign
        blob = _make_image_blob(data=b"png-bytes")
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        assert resp.headers["content-type"].startswith("image/png")

    def test_proxy_returns_correct_media_type_video(self, client_no_sign):
        c = client_no_sign
        blob = _make_video_blob(data=b"mp4-bytes")
        _configure_for_video(app_module.bucket, blob)

        resp = c.get("/api/videos/vid-001", follow_redirects=False)
        assert resp.headers["content-type"].startswith("video/mp4")


# ---------------------------------------------------------------------------
# Tests: proxy fallback — HTTP Range / 206 Partial Content
# ---------------------------------------------------------------------------


class TestProxyRangeRequests:
    def test_range_request_returns_206(self, client_no_sign):
        c = client_no_sign
        data = b"0123456789ABCDEF"  # 16 bytes
        blob = _make_video_blob(data=data[:5], size=16)  # mock returns only slice
        _configure_for_video(app_module.bucket, blob)

        resp = c.get(
            "/api/videos/vid-001",
            headers={"Range": "bytes=0-4"},
            follow_redirects=False,
        )
        assert resp.status_code == 206

    def test_range_response_has_content_range_header(self, client_no_sign):
        c = client_no_sign
        blob = _make_video_blob(data=b"HELLO", size=16)
        _configure_for_video(app_module.bucket, blob)

        resp = c.get(
            "/api/videos/vid-001",
            headers={"Range": "bytes=0-4"},
            follow_redirects=False,
        )
        assert "content-range" in resp.headers
        assert resp.headers["content-range"] == "bytes 0-4/16"

    def test_range_response_has_accept_ranges_header(self, client_no_sign):
        c = client_no_sign
        blob = _make_video_blob(data=b"WORLD", size=16)
        _configure_for_video(app_module.bucket, blob)

        resp = c.get(
            "/api/videos/vid-001",
            headers={"Range": "bytes=0-4"},
            follow_redirects=False,
        )
        assert resp.headers.get("accept-ranges") == "bytes"

    def test_no_range_header_returns_200(self, client_no_sign):
        c = client_no_sign
        blob = _make_video_blob(data=b"full-content")
        _configure_for_video(app_module.bucket, blob)

        resp = c.get("/api/videos/vid-001", follow_redirects=False)
        assert resp.status_code == 200

    def test_download_as_bytes_called_with_range_args(self, client_no_sign):
        """When a Range header is present, download_as_bytes is called with
        start/end so only the requested bytes are fetched from GCS."""
        c = client_no_sign
        blob = _make_video_blob(data=b"XYZ", size=100)
        _configure_for_video(app_module.bucket, blob)

        c.get(
            "/api/videos/vid-001",
            headers={"Range": "bytes=10-19"},
            follow_redirects=False,
        )

        blob.download_as_bytes.assert_called_once()
        call_kwargs = blob.download_as_bytes.call_args.kwargs
        assert call_kwargs.get("start") == 10
        # GCS end is exclusive, so end+1
        assert call_kwargs.get("end") == 20

    def test_proxy_accept_ranges_header_on_200(self, client_no_sign):
        """Even 200 responses should advertise Accept-Ranges: bytes."""
        c = client_no_sign
        blob = _make_image_blob(data=b"img")
        _configure_for_image(app_module.bucket, blob)

        resp = c.get("/api/images/img-001", follow_redirects=False)
        assert resp.headers.get("accept-ranges") == "bytes"
