"""
Pytest suite for the intent-based plan/apply sync endpoints.

The tests mock GCS and the intent store so they run without real cloud
credentials.  A fresh MemoryIntentStore is injected before each test via
the module-level ``intent_store`` reference in app.py so tests remain
isolated.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List, Optional
from unittest.mock import MagicMock, patch

import pytest
import pytest_asyncio

# ---------------------------------------------------------------------------
# Stub out GCS / bucket before importing the app so the lifespan does not
# try to connect to real Google Cloud.
# ---------------------------------------------------------------------------
import sys
import types

_gcs_stub = types.ModuleType("google.cloud.storage")
_gcs_stub.Client = MagicMock()
_google_stub = types.ModuleType("google")
_cloud_stub = types.ModuleType("google.cloud")
_auth_stub = types.ModuleType("google.oauth2")
_creds_stub = types.ModuleType("google.oauth2.service_account")
_creds_stub.Credentials = MagicMock()

for mod_name, mod in [
    ("google", _google_stub),
    ("google.cloud", _cloud_stub),
    ("google.cloud.storage", _gcs_stub),
    ("google.oauth2", _auth_stub),
    ("google.oauth2.service_account", _creds_stub),
]:
    sys.modules.setdefault(mod_name, mod)

# ---------------------------------------------------------------------------
# Patch environment before import
# ---------------------------------------------------------------------------
import os

os.environ.setdefault("GCP_BUCKET_NAME", "test-bucket")
os.environ.setdefault("GCP_CREDENTIALS", "")

# ---------------------------------------------------------------------------
# Now import app internals
# ---------------------------------------------------------------------------
import storage_manager.app as app_module

from storage_manager.app import (
    DIFF_PREVIEW_CAP,
    INTENT_TTL_SECONDS,
    MemoryIntentStore,
    SyncIntentDocument,
    _build_diff_preview,
    _compute_sync_diff_sync,
    app,
    intent_store,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_startup_bucket() -> MagicMock:
    """Return a mock bucket that satisfies the lifespan's shader-seeding check."""
    blob = MagicMock()
    blob.exists.return_value = False  # → no shader index → seeding skipped cleanly
    blob.download_as_text.return_value = "[]"
    blob.upload_from_string.return_value = None
    bucket = MagicMock()
    bucket.blob.return_value = blob
    bucket.list_blobs.return_value = iter([])
    bucket.copy_blob.return_value = None
    return bucket


def _make_test_bucket() -> MagicMock:
    """Return a fresh, unconfigured mock bucket for test-level setup."""
    bucket = MagicMock()
    bucket.copy_blob.return_value = None
    return bucket


def _make_gcs_client(startup_bucket: MagicMock) -> MagicMock:
    client = MagicMock()
    client.bucket.return_value = startup_bucket
    return client


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def fresh_intent_store():
    """Replace the module-level intent store with a fresh instance for each test."""
    fresh = MemoryIntentStore(ttl=INTENT_TTL_SECONDS)
    app_module.intent_store = fresh
    yield fresh
    app_module.intent_store = fresh


@pytest.fixture()
def client(fresh_intent_store):
    """FastAPI TestClient with GCS fully mocked.

    Strategy:
    - Patch ``get_gcs_client`` so the lifespan doesn't reach real GCS.
    - Create a fresh ``ThreadPoolExecutor`` so the lifespan can use ``run_io``
      even after a previous test's lifespan called ``io_executor.shutdown()``.
    - After the lifespan completes, override ``app_module.bucket`` with a
      *test-controlled* mock so each test can configure its own responses.
    """
    from fastapi.testclient import TestClient

    startup_bucket = _make_startup_bucket()
    gcs_client = _make_gcs_client(startup_bucket)

    # Fresh executor — previous test's lifespan may have shut the old one down.
    app_module.io_executor = ThreadPoolExecutor(max_workers=2)

    with patch("storage_manager.app.get_gcs_client", return_value=gcs_client):
        with TestClient(app, raise_server_exceptions=True) as c:
            # The lifespan has now run and set bucket = gcs_client.bucket(…).
            # Override with a new test-controlled mock.
            test_bucket = _make_test_bucket()
            app_module.bucket = test_bucket
            yield c, test_bucket


# ---------------------------------------------------------------------------
# GCS mock helpers
# ---------------------------------------------------------------------------


def _make_blob(name: str, size: int = 1024, public_url: str = "") -> MagicMock:
    b = MagicMock()
    b.name = name
    b.size = size
    b.public_url = public_url or f"https://storage.googleapis.com/test-bucket/{name}"
    return b


def _configure_bucket_for_images(
    mock_bucket: MagicMock,
    gcs_files: List[Dict],
    index_content: List[Dict],
    index_blob_name: str = "images/_images.json",
) -> None:
    blobs = [_make_blob(f"images/{fi['filename']}", fi.get("size", 1024)) for fi in gcs_files]

    def _list_blobs(prefix="", **kwargs):
        return iter([b for b in blobs if b.name.startswith(prefix)])

    mock_bucket.list_blobs.side_effect = _list_blobs

    def _blob(path):
        b = MagicMock()
        b.exists.return_value = True
        b.download_as_text.return_value = (
            json.dumps(index_content) if path == index_blob_name else "[]"
        )
        b.upload_from_string.return_value = None
        b.delete.return_value = None
        return b

    mock_bucket.blob.side_effect = _blob


def _configure_bucket_for_videos(
    mock_bucket: MagicMock,
    gcs_files: List[Dict],
    index_content: List[Dict],
    index_blob_name: str = "videos/_videos.json",
) -> None:
    blobs = [_make_blob(f"videos/{fi['filename']}", fi.get("size", 2048)) for fi in gcs_files]

    def _list_blobs(prefix="", **kwargs):
        return iter([b for b in blobs if b.name.startswith(prefix)])

    mock_bucket.list_blobs.side_effect = _list_blobs

    def _blob(path):
        b = MagicMock()
        b.exists.return_value = True
        b.download_as_text.return_value = (
            json.dumps(index_content) if path == index_blob_name else "[]"
        )
        b.upload_from_string.return_value = None
        b.delete.return_value = None
        return b

    mock_bucket.blob.side_effect = _blob


# ---------------------------------------------------------------------------
# Unit tests: MemoryIntentStore
# ---------------------------------------------------------------------------


class TestMemoryIntentStore:
    def _make_doc(
        self, resource_type="image", status="PENDING", ttl_offset=100
    ) -> SyncIntentDocument:
        now = time.time()
        return SyncIntentDocument(
            intent_id=str(uuid.uuid4()),
            resource_type=resource_type,
            status=status,
            created_at=now,
            expires_at=now + ttl_offset,
            gcs_snapshot_sha="abc",
            index_snapshot_sha="def",
            diff={"to_add": [], "to_remove": [], "divergent": [], "unchanged_count": 0},
            diff_preview={"to_add": [], "to_remove": [], "divergent": [], "unchanged_count": 0},
        )

    def test_put_and_get(self):
        store = MemoryIntentStore()
        doc = self._make_doc()
        store.put(doc)
        retrieved = store.get(doc.intent_id)
        assert retrieved is not None
        assert retrieved.intent_id == doc.intent_id

    def test_get_missing_returns_none(self):
        store = MemoryIntentStore()
        assert store.get("nonexistent") is None

    def test_expired_pending_intent_returns_expired_status(self):
        store = MemoryIntentStore()
        doc = self._make_doc(ttl_offset=-1)
        store.put(doc)
        retrieved = store.get(doc.intent_id)
        assert retrieved is not None
        assert retrieved.status == "EXPIRED"

    def test_executed_intent_not_expired_by_ttl(self):
        store = MemoryIntentStore()
        doc = self._make_doc(status="EXECUTED", ttl_offset=-1)
        store.put(doc)
        retrieved = store.get(doc.intent_id)
        assert retrieved is not None
        assert retrieved.status == "EXECUTED"

    def test_cleanup_removes_expired_pending(self):
        store = MemoryIntentStore()
        doc = self._make_doc(ttl_offset=-1)
        store.put(doc)
        removed = store.cleanup_expired()
        assert removed == 1
        assert store.get(doc.intent_id) is None

    def test_cleanup_removes_old_executed(self):
        store = MemoryIntentStore()
        doc = self._make_doc(status="EXECUTED")
        doc.created_at = time.time() - 8 * 24 * 3600
        store.put(doc)
        removed = store.cleanup_expired()
        assert removed == 1

    def test_list_recent_filters_by_resource_type(self):
        store = MemoryIntentStore()
        for _ in range(3):
            store.put(self._make_doc(resource_type="image"))
        for _ in range(2):
            store.put(self._make_doc(resource_type="video"))
        assert len(store.list_recent("image", limit=10)) == 3
        assert len(store.list_recent("video", limit=10)) == 2

    def test_list_recent_respects_limit(self):
        store = MemoryIntentStore()
        for _ in range(10):
            store.put(self._make_doc())
        assert len(store.list_recent("image", limit=5)) == 5


# ---------------------------------------------------------------------------
# Unit tests: _build_diff_preview
# ---------------------------------------------------------------------------


class TestBuildDiffPreview:
    def _make_diff(self, n_add=0, n_remove=0, n_divergent=0, unchanged=0):
        return {
            "to_add": [{"filename": f"f{i}.png"} for i in range(n_add)],
            "to_remove": [{"filename": f"r{i}.png"} for i in range(n_remove)],
            "divergent": [{"filename": f"d{i}.png"} for i in range(n_divergent)],
            "unchanged_count": unchanged,
        }

    def test_no_truncation_when_under_cap(self):
        diff = self._make_diff(n_add=5, n_remove=3)
        preview, truncated = _build_diff_preview(diff)
        assert truncated is False
        assert len(preview["to_add"]) == 5

    def test_truncation_when_over_cap(self):
        diff = self._make_diff(n_add=DIFF_PREVIEW_CAP + 10)
        preview, truncated = _build_diff_preview(diff)
        assert truncated is True
        assert len(preview["to_add"]) == DIFF_PREVIEW_CAP

    def test_unchanged_count_always_preserved(self):
        diff = self._make_diff(unchanged=42)
        preview, _ = _build_diff_preview(diff)
        assert preview["unchanged_count"] == 42


# ---------------------------------------------------------------------------
# Integration tests: plan endpoint (images)
# ---------------------------------------------------------------------------


class TestPlanSyncImages:
    def test_plan_returns_intent_id(self, client):
        c, mock_bucket = client
        _configure_bucket_for_images(mock_bucket, [], [])
        resp = c.post("/api/admin/sync-images/plan")
        assert resp.status_code == 200
        data = resp.json()
        assert "intent_id" in data
        assert "gcs_snapshot_sha" in data
        assert "index_snapshot_sha" in data
        assert "expires_at" in data
        assert "diff" in data

    def test_plan_no_writes_to_gcs(self, client):
        c, mock_bucket = client
        _configure_bucket_for_images(mock_bucket, [{"filename": "a.png"}], [])
        resp = c.post("/api/admin/sync-images/plan")
        assert resp.status_code == 200
        for call in mock_bucket.mock_calls:
            assert "upload_from_string" not in str(call), "Plan must not write to GCS"

    def test_plan_detects_files_to_add(self, client):
        c, mock_bucket = client
        _configure_bucket_for_images(mock_bucket, [{"filename": "new.png"}], [])
        resp = c.post("/api/admin/sync-images/plan")
        assert resp.status_code == 200
        diff = resp.json()["diff"]
        assert len(diff["to_add"]) == 1
        assert diff["to_add"][0]["filename"] == "new.png"

    def test_plan_detects_files_to_remove(self, client):
        c, mock_bucket = client
        _configure_bucket_for_images(
            mock_bucket, [], [{"id": "x", "filename": "old.png"}]
        )
        resp = c.post("/api/admin/sync-images/plan")
        assert resp.status_code == 200
        diff = resp.json()["diff"]
        assert len(diff["to_remove"]) == 1
        assert diff["to_remove"][0]["filename"] == "old.png"

    def test_plan_stores_intent(self, client, fresh_intent_store):
        c, mock_bucket = client
        _configure_bucket_for_images(mock_bucket, [], [])
        resp = c.post("/api/admin/sync-images/plan")
        assert resp.status_code == 200
        intent_id = resp.json()["intent_id"]
        doc = fresh_intent_store.get(intent_id)
        assert doc is not None
        assert doc.status == "PENDING"
        assert doc.resource_type == "image"


# ---------------------------------------------------------------------------
# Integration tests: plan endpoint (videos)
# ---------------------------------------------------------------------------


class TestPlanSyncVideos:
    def test_plan_returns_intent_id(self, client):
        c, mock_bucket = client
        _configure_bucket_for_videos(mock_bucket, [], [])
        resp = c.post("/api/admin/sync-videos/plan")
        assert resp.status_code == 200
        assert "intent_id" in resp.json()

    def test_plan_detects_video_files(self, client):
        c, mock_bucket = client
        _configure_bucket_for_videos(mock_bucket, [{"filename": "clip.mp4"}], [])
        resp = c.post("/api/admin/sync-videos/plan")
        assert resp.status_code == 200
        diff = resp.json()["diff"]
        assert diff["to_add"][0]["filename"] == "clip.mp4"


# ---------------------------------------------------------------------------
# Integration tests: apply endpoint (images) — happy path
# ---------------------------------------------------------------------------


class TestApplySyncImages:
    def _plan(self, c, mock_bucket, gcs_files=None, index_content=None) -> str:
        _configure_bucket_for_images(mock_bucket, gcs_files or [], index_content or [])
        resp = c.post("/api/admin/sync-images/plan")
        assert resp.status_code == 200
        return resp.json()["intent_id"]

    def test_apply_happy_path(self, client):
        c, mock_bucket = client
        intent_id = self._plan(c, mock_bucket, gcs_files=[{"filename": "img.png"}])
        # Re-configure so apply sees the same GCS state
        _configure_bucket_for_images(mock_bucket, [{"filename": "img.png"}], [])
        resp = c.post("/api/admin/sync-images/apply", json={"intent_id": intent_id})
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "EXECUTED"
        assert data["changes_applied"] is True

    def test_apply_idempotent_returns_200(self, client, fresh_intent_store):
        c, mock_bucket = client
        intent_id = self._plan(c, mock_bucket)
        doc = fresh_intent_store.get(intent_id)
        doc.status = "EXECUTED"
        doc.duration_ms = 10.0
        doc.backup_path = "images/_images.json.backup.20260101T000000Z"
        fresh_intent_store.put(doc)

        resp = c.post("/api/admin/sync-images/apply", json={"intent_id": intent_id})
        assert resp.status_code == 200
        assert resp.json()["status"] == "EXECUTED"

    def test_apply_executing_returns_409(self, client, fresh_intent_store):
        c, mock_bucket = client
        intent_id = self._plan(c, mock_bucket)
        doc = fresh_intent_store.get(intent_id)
        doc.status = "EXECUTING"
        fresh_intent_store.put(doc)

        resp = c.post("/api/admin/sync-images/apply", json={"intent_id": intent_id})
        assert resp.status_code == 409
        assert resp.json()["detail"]["error"] == "EXECUTING"

    def test_apply_expired_returns_410(self, client, fresh_intent_store):
        c, mock_bucket = client
        intent_id = self._plan(c, mock_bucket)
        doc = fresh_intent_store.get(intent_id)
        doc.expires_at = time.time() - 1
        doc.status = "PENDING"
        fresh_intent_store.put(doc)

        resp = c.post("/api/admin/sync-images/apply", json={"intent_id": intent_id})
        assert resp.status_code == 410
        assert resp.json()["detail"]["error"] == "INTENT_NOT_FOUND"

    def test_apply_unknown_intent_returns_410(self, client):
        c, _ = client
        resp = c.post("/api/admin/sync-images/apply", json={"intent_id": str(uuid.uuid4())})
        assert resp.status_code == 410

    def test_apply_state_changed_returns_409(self, client, fresh_intent_store):
        """GCS snapshot changes between plan and apply → 409 STATE_CHANGED."""
        c, mock_bucket = client
        intent_id = self._plan(c, mock_bucket, gcs_files=[{"filename": "a.png"}])

        # Change GCS state before apply
        _configure_bucket_for_images(
            mock_bucket,
            [{"filename": "a.png"}, {"filename": "b.png"}],
            [],
        )
        resp = c.post("/api/admin/sync-images/apply", json={"intent_id": intent_id})
        assert resp.status_code == 409
        assert resp.json()["detail"]["error"] == "STATE_CHANGED"

    def test_apply_divergence_blocks_without_acknowledge(self, client, fresh_intent_store):
        c, mock_bucket = client
        intent_id = self._plan(c, mock_bucket)
        doc = fresh_intent_store.get(intent_id)
        doc.diff["divergent"] = [{"filename": "x.png", "gcs": {}, "index": {}, "sync_base": {}}]
        fresh_intent_store.put(doc)

        resp = c.post(
            "/api/admin/sync-images/apply",
            json={"intent_id": intent_id, "acknowledge_divergence": False},
        )
        assert resp.status_code == 409
        assert resp.json()["detail"]["error"] == "INDEX_DIVERGED"

    def test_apply_divergence_proceeds_with_acknowledge(self, client, fresh_intent_store):
        c, mock_bucket = client
        # Plan with empty GCS + empty index so hashes are predictable
        _configure_bucket_for_images(mock_bucket, [], [])
        plan_resp = c.post("/api/admin/sync-images/plan")
        assert plan_resp.status_code == 200
        intent_id = plan_resp.json()["intent_id"]

        doc = fresh_intent_store.get(intent_id)
        doc.diff["divergent"] = [{"filename": "x.png", "gcs": {}, "index": {}, "sync_base": {}}]
        fresh_intent_store.put(doc)

        # Apply with same GCS state so hashes match
        _configure_bucket_for_images(mock_bucket, [], [])
        resp = c.post(
            "/api/admin/sync-images/apply",
            json={"intent_id": intent_id, "acknowledge_divergence": True},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "EXECUTED"


# ---------------------------------------------------------------------------
# Integration tests: audit endpoints
# ---------------------------------------------------------------------------


class TestAuditEndpoints:
    def test_list_image_intents_empty(self, client):
        c, _ = client
        resp = c.get("/api/admin/sync-images/intents")
        assert resp.status_code == 200
        assert resp.json() == {"intents": []}

    def test_list_image_intents_after_plan(self, client):
        c, mock_bucket = client
        _configure_bucket_for_images(mock_bucket, [], [])
        c.post("/api/admin/sync-images/plan")
        resp = c.get("/api/admin/sync-images/intents")
        assert resp.status_code == 200
        assert len(resp.json()["intents"]) == 1

    def test_get_image_intent_detail(self, client):
        c, mock_bucket = client
        _configure_bucket_for_images(mock_bucket, [], [])
        plan_resp = c.post("/api/admin/sync-images/plan")
        intent_id = plan_resp.json()["intent_id"]
        resp = c.get(f"/api/admin/sync-images/intents/{intent_id}")
        assert resp.status_code == 200
        data = resp.json()
        assert data["intent_id"] == intent_id
        assert "diff" in data

    def test_get_image_intent_not_found(self, client):
        c, _ = client
        resp = c.get(f"/api/admin/sync-images/intents/{uuid.uuid4()}")
        assert resp.status_code == 404

    def test_list_video_intents_empty(self, client):
        c, _ = client
        resp = c.get("/api/admin/sync-videos/intents")
        assert resp.status_code == 200
        assert resp.json() == {"intents": []}

    def test_get_video_intent_not_found(self, client):
        c, _ = client
        resp = c.get(f"/api/admin/sync-videos/intents/{uuid.uuid4()}")
        assert resp.status_code == 404

    def test_image_intent_not_accessible_via_video_endpoint(self, client):
        c, mock_bucket = client
        _configure_bucket_for_images(mock_bucket, [], [])
        plan_resp = c.post("/api/admin/sync-images/plan")
        intent_id = plan_resp.json()["intent_id"]
        resp = c.get(f"/api/admin/sync-videos/intents/{intent_id}")
        assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Integration tests: legacy 410 endpoints
# ---------------------------------------------------------------------------


class TestLegacyEndpoints410:
    def test_legacy_sync_images_returns_410(self, client):
        c, _ = client
        resp = c.post("/api/admin/sync-images")
        assert resp.status_code == 410
        data = resp.json()
        assert data["error"] == "ENDPOINT_RETIRED"
        assert "/api/admin/sync-images/plan" in data["plan_endpoint"]

    def test_legacy_sync_videos_returns_410(self, client):
        c, _ = client
        resp = c.post("/api/admin/sync-videos")
        assert resp.status_code == 410
        data = resp.json()
        assert data["error"] == "ENDPOINT_RETIRED"
        assert "/api/admin/sync-videos/plan" in data["plan_endpoint"]


# ---------------------------------------------------------------------------
# Integration tests: per-resource locks don't block different resources
# ---------------------------------------------------------------------------


class TestPerResourceLocks:
    def test_different_resources_have_different_locks(self):
        from storage_manager.app import get_resource_lock

        image_lock = get_resource_lock("image")
        video_lock = get_resource_lock("video")
        shader_lock = get_resource_lock("shader")
        assert image_lock is not video_lock
        assert image_lock is not shader_lock
        assert video_lock is not shader_lock

    def test_same_resource_returns_same_lock(self):
        from storage_manager.app import get_resource_lock

        assert get_resource_lock("image") is get_resource_lock("image")

    @pytest.mark.asyncio
    async def test_image_lock_acquired_does_not_block_video(self):
        from storage_manager.app import get_resource_lock

        image_lock = get_resource_lock("image")
        video_lock = get_resource_lock("video")

        async with image_lock:
            acquired = False

            async def acquire_video():
                nonlocal acquired
                async with video_lock:
                    acquired = True

            await asyncio.wait_for(acquire_video(), timeout=0.5)
            assert acquired


# ---------------------------------------------------------------------------
# Unit tests: _write_json_atomic_sync backup & rollback path
# ---------------------------------------------------------------------------


class TestWriteJsonAtomicSync:
    def test_atomic_write_creates_backup_when_existing(self):
        from storage_manager.app import _write_json_atomic_sync

        mock_bucket = _make_test_bucket()
        tmp_blob = MagicMock()
        tmp_blob.upload_from_string.return_value = None
        tmp_blob.delete.return_value = None
        main_blob = MagicMock()
        main_blob.exists.return_value = True
        main_blob.upload_from_string.return_value = None

        def _blob(path):
            if ".tmp." in path:
                return tmp_blob
            return main_blob

        mock_bucket.blob.side_effect = _blob
        app_module.bucket = mock_bucket

        backup = _write_json_atomic_sync("images/_images.json", {"new": True})

        assert mock_bucket.copy_blob.call_count == 1
        assert ".backup." in backup

    def test_atomic_write_skips_backup_when_no_existing(self):
        from storage_manager.app import _write_json_atomic_sync

        mock_bucket = _make_test_bucket()
        tmp_blob = MagicMock()
        tmp_blob.upload_from_string.return_value = None
        tmp_blob.delete.return_value = None
        main_blob = MagicMock()
        main_blob.exists.return_value = False
        main_blob.upload_from_string.return_value = None

        def _blob(path):
            if ".tmp." in path:
                return tmp_blob
            return main_blob

        mock_bucket.blob.side_effect = _blob
        app_module.bucket = mock_bucket

        backup = _write_json_atomic_sync("images/_images.json", {})

        assert mock_bucket.copy_blob.call_count == 0
        assert backup == ""


# ---------------------------------------------------------------------------
# Cache consistency: invalidation happens inside the lock during apply
# ---------------------------------------------------------------------------


class TestCacheConsistency:
    def test_apply_invalidates_cache_keys(self, client, fresh_intent_store):
        """cache.delete must be called with both library keys after apply."""
        c, mock_bucket = client
        _configure_bucket_for_images(mock_bucket, [], [])
        plan_resp = c.post("/api/admin/sync-images/plan")
        intent_id = plan_resp.json()["intent_id"]

        deleted_keys: List[str] = []
        original_delete = app_module.cache.delete

        async def tracking_delete(key):
            deleted_keys.append(key)
            return await original_delete(key)

        app_module.cache.delete = tracking_delete

        # Same GCS state for apply
        _configure_bucket_for_images(mock_bucket, [], [])
        resp = c.post("/api/admin/sync-images/apply", json={"intent_id": intent_id})
        assert resp.status_code == 200

        app_module.cache.delete = original_delete

        assert "library:image" in deleted_keys
        assert "library:all" in deleted_keys
