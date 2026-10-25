"""Webhook signing proxy (#1511 bug 2): the HMAC is computed server-side."""

import hashlib
import hmac

import httpx
import pytest
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.testclient import TestClient

from storage_manager import config
from storage_manager.routes import webhook_proxy

SECRET = "test-secret"
RECEIVER = "https://receiver.example/webhook/image-effects"
BODY = b'{"action":"save_shader","name":"a","data":{"x":1},"timestamp":"2026-10-25T00:00:00.000Z"}'


def _app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=config.ALLOWED_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(webhook_proxy.router)
    return app


@pytest.fixture
def configured(monkeypatch):
    monkeypatch.setattr(config, "WEBHOOK_SECRET", SECRET)
    monkeypatch.setattr(config, "WEBHOOK_RECEIVER_URL", RECEIVER)


@pytest.fixture
def receiver(monkeypatch):
    """Route the proxy's httpx client to an in-process mock receiver."""
    seen = []
    response = {"status": 200, "json": {"status": "success", "files": ["image-effects/shaders/a.wgsl"]}}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(response["status"], json=response["json"])

    real_client = httpx.AsyncClient

    def client_factory(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return real_client(*args, **kwargs)

    monkeypatch.setattr(webhook_proxy.httpx, "AsyncClient", client_factory)
    return seen, response


def _post(body: bytes = BODY):
    return TestClient(_app()).post(
        "/api/webhook-proxy/image-effects",
        content=body,
        headers={"Content-Type": "application/json", "Origin": "http://localhost:3000"},
    )


def test_signs_raw_body_and_forwards(configured, receiver):
    seen, _ = receiver
    res = _post()
    assert res.status_code == 200
    assert res.json() == {"status": "success", "files": ["image-effects/shaders/a.wgsl"]}
    assert len(seen) == 1
    forwarded = seen[0]
    assert str(forwarded.url) == RECEIVER
    assert forwarded.content == BODY
    expected = "sha256=" + hmac.new(SECRET.encode(), BODY, hashlib.sha256).hexdigest()
    assert forwarded.headers["X-Hub-Signature-256"] == expected
    assert forwarded.headers["Content-Type"] == "application/json"
    assert res.headers.get("access-control-allow-origin") is not None


@pytest.mark.parametrize("secret,url", [("", RECEIVER), (SECRET, ""), ("", "")])
def test_missing_env_is_503(monkeypatch, receiver, secret, url):
    monkeypatch.setattr(config, "WEBHOOK_SECRET", secret)
    monkeypatch.setattr(config, "WEBHOOK_RECEIVER_URL", url)
    seen, _ = receiver
    res = _post()
    assert res.status_code == 503
    assert seen == []


def test_receiver_4xx_passthrough(configured, receiver):
    _, response = receiver
    response["status"] = 401
    response["json"] = {"error": "bad signature"}
    res = _post()
    assert res.status_code == 401
    assert res.json() == {"error": "bad signature"}
