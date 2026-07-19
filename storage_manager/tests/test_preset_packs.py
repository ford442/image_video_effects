"""
Pytest suite for community preset-pack endpoints.

Mirrors the GCS-mocking pattern from test_sync_endpoints.py and validates the
round-trip contract: a SharedChain published via POST /api/preset-packs can be
fetched back via GET /api/preset-packs/{id} and decoded to the original chain.
"""

from __future__ import annotations

import base64
import json
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List
from unittest.mock import MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Stub GCS / bucket before importing the app so the lifespan does not
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
# Import app internals
# ---------------------------------------------------------------------------
import storage_manager.app as app_module
from storage_manager.app import app

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _encode_chain(chain: Dict[str, Any]) -> str:
    """Python mirror of encodeChain() in src/services/layerChainShare.ts."""
    json_str = json.dumps(chain, separators=(",", ":"))
    raw_bytes = json_str.encode("utf-8")
    return base64.urlsafe_b64encode(raw_bytes).decode("ascii").rstrip("=")


def _decode_chain(chain_str: str) -> Dict[str, Any]:
    """Python mirror of decodeChain() in src/services/layerChainShare.ts."""
    padded = chain_str.replace("-", "+").replace("_", "/")
    pad_len = (-len(padded)) % 4
    if pad_len:
        padded += "=" * pad_len
    raw_bytes = base64.b64decode(padded)
    return json.loads(raw_bytes.decode("utf-8"))


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


def _make_test_bucket(index_content: List[Dict[str, Any]] | None = None) -> MagicMock:
    """Return a test-controlled mock bucket with an in-memory preset-pack index."""
    state = {"preset_packs": list(index_content) if index_content else []}

    bucket = MagicMock()
    bucket.copy_blob.return_value = None
    bucket.list_blobs.return_value = iter([])

    def _blob(path: str) -> MagicMock:
        b = MagicMock()
        if path == "preset_packs/_preset_packs.json":
            b.exists.return_value = True
            b.download_as_text.return_value = json.dumps(state["preset_packs"])

            def _upload_from_string(data: str, **kwargs):
                state["preset_packs"] = json.loads(data)

            b.upload_from_string.side_effect = _upload_from_string
        else:
            b.exists.return_value = False
            b.download_as_text.return_value = "[]"
            b.upload_from_string.return_value = None
        b.delete.return_value = None
        return b

    bucket.blob.side_effect = _blob
    return bucket


@pytest.fixture()
def client():
    """FastAPI TestClient with GCS fully mocked."""
    from fastapi.testclient import TestClient

    startup_bucket = _make_startup_bucket()
    gcs_client = _make_gcs_client(startup_bucket)
    app_module.io_executor = ThreadPoolExecutor(max_workers=2)

    with patch("storage_manager.app.get_gcs_client", return_value=gcs_client):
        with TestClient(app, raise_server_exceptions=True) as c:
            test_bucket = _make_test_bucket()
            app_module.bucket = test_bucket
            yield c, test_bucket


# ---------------------------------------------------------------------------
# Sample data
# ---------------------------------------------------------------------------


def _sample_chain(name: str = "liquid-metal") -> Dict[str, Any]:
    return {
        "v": 1,
        "slots": [
            {"shaderId": name, "params": {"zoomParam1": 0.35}},
            {"shaderId": "liquid-rainbow"},
        ],
    }


# ---------------------------------------------------------------------------
# Unit tests: _decode_shared_chain
# ---------------------------------------------------------------------------


class TestDecodeSharedChain:
    def test_decodes_valid_chain(self):
        chain = _sample_chain()
        encoded = _encode_chain(chain)
        decoded = app_module._decode_shared_chain(encoded)
        assert decoded == chain

    def test_rejects_invalid_base64(self):
        assert app_module._decode_shared_chain("not-base64!!!") is None

    def test_rejects_bad_json(self):
        encoded = base64.urlsafe_b64encode(b"not json").decode("ascii").rstrip("=")
        assert app_module._decode_shared_chain(encoded) is None

    def test_rejects_wrong_version(self):
        chain = {"v": 99, "slots": []}
        assert app_module._decode_shared_chain(_encode_chain(chain)) is None

    def test_rejects_missing_slots(self):
        assert app_module._decode_shared_chain(_encode_chain({"v": 1})) is None

    def test_rejects_too_many_slots(self):
        chain = {"v": 1, "slots": [{"shaderId": f"s{i}"} for i in range(7)]}
        assert app_module._decode_shared_chain(_encode_chain(chain)) is None

    def test_rejects_bad_slot_mode(self):
        chain = {"v": 1, "slots": [{"shaderId": "x", "mode": "diagonal"}]}
        assert app_module._decode_shared_chain(_encode_chain(chain)) is None

    def test_rejects_non_numeric_params(self):
        chain = {"v": 1, "slots": [{"shaderId": "x", "params": {"zoomParam1": "bad"}}]}
        assert app_module._decode_shared_chain(_encode_chain(chain)) is None


# ---------------------------------------------------------------------------
# Integration tests: publish
# ---------------------------------------------------------------------------


class TestPublishPresetPack:
    def test_publish_happy_path(self, client):
        c, _ = client
        chain = _sample_chain()
        encoded = _encode_chain(chain)
        payload = {
            "name": "Liquid Dreams",
            "description": "Molten chrome into rainbow oil.",
            "author": "tester",
            "chain": encoded,
        }
        resp = c.post("/api/preset-packs", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert "id" in data
        assert data["pack"]["name"] == "Liquid Dreams"
        assert data["pack"]["chain"] == encoded
        assert data["pack"]["play_count"] == 0

    def test_publish_rejects_undecodable_chain(self, client):
        c, _ = client
        payload = {
            "name": "Bad Pack",
            "description": "",
            "chain": "totally-not-a-chain",
        }
        resp = c.post("/api/preset-packs", json=payload)
        assert resp.status_code == 400
        assert "decode" in resp.json()["detail"].lower()

    def test_publish_defaults_author(self, client):
        c, _ = client
        payload = {
            "name": "Anonymous Pack",
            "chain": _encode_chain(_sample_chain()),
        }
        resp = c.post("/api/preset-packs", json=payload)
        assert resp.status_code == 200
        assert resp.json()["pack"]["author"] == "Anonymous"

    def test_publish_strips_whitespace(self, client):
        c, _ = client
        payload = {
            "name": "  Padded  ",
            "description": "  desc  ",
            "author": "  ",
            "chain": _encode_chain(_sample_chain()),
        }
        resp = c.post("/api/preset-packs", json=payload)
        assert resp.status_code == 200
        pack = resp.json()["pack"]
        assert pack["name"] == "Padded"
        assert pack["description"] == "desc"
        assert pack["author"] == "Anonymous"

    def test_publish_rejects_empty_name(self, client):
        c, _ = client
        payload = {"name": "", "chain": _encode_chain(_sample_chain())}
        resp = c.post("/api/preset-packs", json=payload)
        assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Integration tests: list
# ---------------------------------------------------------------------------


class TestListPresetPacks:
    def test_list_empty(self, client):
        c, _ = client
        resp = c.get("/api/preset-packs")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 0
        assert data["packs"] == []

    def test_list_returns_published_packs(self, client):
        c, _ = client
        c.post("/api/preset-packs", json={
            "name": "Pack A",
            "chain": _encode_chain(_sample_chain("a")),
        })
        c.post("/api/preset-packs", json={
            "name": "Pack B",
            "chain": _encode_chain(_sample_chain("b")),
        })

        resp = c.get("/api/preset-packs")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 2
        assert [p["name"] for p in data["packs"]] == ["Pack B", "Pack A"]

    def test_list_limit_offset(self, client):
        c, _ = client
        for i in range(3):
            c.post("/api/preset-packs", json={
                "name": f"Pack {i}",
                "chain": _encode_chain(_sample_chain(f"s{i}")),
            })

        resp = c.get("/api/preset-packs?limit=1&offset=1")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 3
        assert len(data["packs"]) == 1
        assert data["packs"][0]["name"] == "Pack 1"

    def test_list_invalid_limit_returns_422(self, client):
        c, _ = client
        resp = c.get("/api/preset-packs?limit=0")
        assert resp.status_code == 422

    def test_list_sort_by_play_count(self, client):
        c, _ = client
        low = c.post("/api/preset-packs", json={
            "name": "Low Plays",
            "chain": _encode_chain(_sample_chain("low")),
        }).json()["id"]
        high = c.post("/api/preset-packs", json={
            "name": "High Plays",
            "chain": _encode_chain(_sample_chain("high")),
        }).json()["id"]

        c.post(f"/api/preset-packs/{low}/play")
        c.post(f"/api/preset-packs/{high}/play")
        c.post(f"/api/preset-packs/{high}/play")

        resp = c.get("/api/preset-packs?sort_by=play_count")
        assert resp.status_code == 200
        names = [p["name"] for p in resp.json()["packs"]]
        assert names[0] == "High Plays"
        assert names[1] == "Low Plays"


# ---------------------------------------------------------------------------
# Integration tests: fetch one
# ---------------------------------------------------------------------------


class TestGetPresetPack:
    def test_get_existing(self, client):
        c, _ = client
        create_resp = c.post("/api/preset-packs", json={
            "name": "Fetch Me",
            "chain": _encode_chain(_sample_chain()),
        })
        pack_id = create_resp.json()["id"]

        resp = c.get(f"/api/preset-packs/{pack_id}")
        assert resp.status_code == 200
        assert resp.json()["name"] == "Fetch Me"

    def test_get_missing_returns_404(self, client):
        c, _ = client
        resp = c.get(f"/api/preset-packs/{uuid.uuid4()}")
        assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Integration tests: play count
# ---------------------------------------------------------------------------


class TestPlayPresetPack:
    def test_play_increments_count(self, client):
        c, _ = client
        create_resp = c.post("/api/preset-packs", json={
            "name": "Play Me",
            "chain": _encode_chain(_sample_chain()),
        })
        pack_id = create_resp.json()["id"]

        resp = c.post(f"/api/preset-packs/{pack_id}/play")
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["play_count"] == 1
        assert "last_played" in data

        # Fetch confirms persistence
        get_resp = c.get(f"/api/preset-packs/{pack_id}")
        assert get_resp.json()["play_count"] == 1

    def test_play_missing_returns_404(self, client):
        c, _ = client
        resp = c.post(f"/api/preset-packs/{uuid.uuid4()}/play")
        assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Round-trip contract: publish → fetch → decode → deep-equal original
# ---------------------------------------------------------------------------


class TestRoundTripContract:
    def test_published_chain_decodes_to_original(self, client):
        c, _ = client
        original = {
            "v": 1,
            "slots": [
                {"shaderId": "liquid-metal", "params": {"zoomParam1": 0.35, "lightStrength": 1.2}},
                {"shaderId": "liquid-rainbow", "enabled": False, "mode": "parallel"},
                {"shaderId": None},
            ],
        }
        encoded = _encode_chain(original)

        publish_resp = c.post("/api/preset-packs", json={
            "name": "Round Trip",
            "description": "Should survive the wire",
            "author": "contract",
            "chain": encoded,
        })
        assert publish_resp.status_code == 200
        pack_id = publish_resp.json()["id"]

        fetch_resp = c.get(f"/api/preset-packs/{pack_id}")
        assert fetch_resp.status_code == 200
        fetched_encoded = fetch_resp.json()["chain"]

        decoded = _decode_chain(fetched_encoded)
        assert decoded == original
