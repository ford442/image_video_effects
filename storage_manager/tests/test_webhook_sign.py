"""Server-side webhook signing: the HMAC secret never ships in the client bundle."""

import hashlib
import hmac
import json
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI
from fastapi.testclient import TestClient

from storage_manager import config
from storage_manager.routes import webhook_sign


def _client(monkeypatch, secret="s3cret"):
    monkeypatch.setattr(config, "STORAGE_WEBHOOK_SECRET", secret)
    monkeypatch.setattr(config, "WEBHOOK_SIGN_ALLOWED_ORIGINS", ["https://test.1ink.us"])
    app = FastAPI()
    app.include_router(webhook_sign.router)
    return TestClient(app)


def _payload(action="save_shader", ts=None):
    ts = ts or datetime.now(timezone.utc)
    return json.dumps({
        "action": action,
        "name": "preset",
        "data": {"x": 1},
        "timestamp": ts.isoformat().replace("+00:00", "Z"),
    })


def test_signs_a_fresh_allowed_payload(monkeypatch):
    payload = _payload()
    r = _client(monkeypatch).post("/api/storage/sign-webhook", json={"payload": payload},
                                  headers={"Origin": "https://test.1ink.us"})
    assert r.status_code == 200
    want = "sha256=" + hmac.new(b"s3cret", payload.encode(), hashlib.sha256).hexdigest()
    assert r.json() == {"signature": want}


def test_rejects_unknown_action(monkeypatch):
    r = _client(monkeypatch).post("/api/storage/sign-webhook", json={"payload": _payload("delete_all")})
    assert r.status_code == 400


def test_rejects_stale_timestamp(monkeypatch):
    old = datetime.now(timezone.utc) - timedelta(hours=1)
    r = _client(monkeypatch).post("/api/storage/sign-webhook", json={"payload": _payload(ts=old)})
    assert r.status_code == 400


def test_rejects_foreign_origin(monkeypatch):
    r = _client(monkeypatch).post("/api/storage/sign-webhook", json={"payload": _payload()},
                                  headers={"Origin": "https://evil.example"})
    assert r.status_code == 403


def test_unconfigured_secret_is_503(monkeypatch):
    r = _client(monkeypatch, secret="").post("/api/storage/sign-webhook", json={"payload": _payload()})
    assert r.status_code == 503
