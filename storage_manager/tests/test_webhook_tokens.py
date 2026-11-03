"""Server-issued upload tokens: POST /upload-token + POST /image-effects.

Covers the happy path, expiry, replay, wrong action/name, tampering, an unset
secret (503), disallowed origins, rate limiting, the body cap, payload
dispatch, and the Redis-backed single-use store (real redis-server when the
binary exists, otherwise skipped).
"""

from __future__ import annotations

import base64
import json
import logging
import os
import shutil
import socket
import subprocess
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from storage_manager import config, state
from storage_manager.app import app
from storage_manager.routes import webhook
from storage_manager.state import clear_cache_for_type as _real_clear_cache_for_type

SECRET = "unit-test-secret-" + "x" * 32
ORIGIN = "https://test.1ink.us"
ACTIONS = (
    "save_shader",
    "save_metadata",
    "save_output",
    "save_video_config",
    "upload_texture",
    "upload_audio",
)
PNG_B64 = base64.b64encode(b"\x89PNG\r\n\x1a\nfake").decode()


class FakeBlob:
    def __init__(self, bucket: "FakeBucket", path: str) -> None:
        self.bucket, self.path = bucket, path

    def exists(self) -> bool:
        return self.path in self.bucket.objects

    def download_as_text(self) -> str:
        data = self.bucket.objects[self.path][0]
        return data.decode() if isinstance(data, bytes) else data

    def upload_from_string(self, data, content_type=None) -> None:
        self.bucket.objects[self.path] = (data, content_type)


class FakeBucket:
    def __init__(self) -> None:
        self.objects: dict = {}

    def blob(self, path: str) -> FakeBlob:
        return FakeBlob(self, path)

    def text(self, path: str) -> str:
        data = self.objects[path][0]
        return data.decode() if isinstance(data, bytes) else data


@pytest.fixture(autouse=True)
def webhook_env(monkeypatch):
    monkeypatch.setattr(config, "WEBHOOK_SIGNING_SECRET", SECRET)
    monkeypatch.setattr(config, "WEBHOOK_RATE_LIMIT_REQUESTS", 10_000)
    monkeypatch.setattr(config, "WEBHOOK_EXTRA_ORIGINS", [])
    monkeypatch.setattr(config, "REDIS_URL", None)
    monkeypatch.setattr(config, "REDIS_HOST", None)
    # test_sync_endpoints patches `storage_manager.app.clear_cache_for_type`; the
    # app module's proxy __delattr__ then deletes it from `state` for good, so
    # restore it here instead of depending on test order.
    monkeypatch.setattr(state, "clear_cache_for_type", _real_clear_cache_for_type, raising=False)
    bucket = FakeBucket()
    monkeypatch.setattr(state, "bucket", bucket)
    monkeypatch.setattr(state, "io_executor", ThreadPoolExecutor(max_workers=2))
    monkeypatch.setattr(state, "RESOURCE_LOCKS", {})
    webhook._reset_store()
    yield bucket
    webhook._reset_store()


@pytest.fixture()
def bucket(webhook_env) -> FakeBucket:
    return webhook_env


@pytest.fixture()
def client() -> TestClient:
    # Own client IP per test so the app-wide rate-limit counters never interfere.
    c = TestClient(app)
    c.headers.update({"Origin": ORIGIN, "X-Forwarded-For": f"10.{uuid.uuid4().int % 250}.{uuid.uuid4().int % 250}.1-{uuid.uuid4().hex}"})
    return c


def mint(client: TestClient, action="save_shader", name="my-preset", prefix="", **kw):
    return client.post(f"{prefix}/upload-token", json={"action": action, "name": name}, **kw)


def write(client: TestClient, token: str, action="save_shader", name="my-preset", data=None, prefix="", **kw):
    body = {"action": action, "name": name, "data": data if data is not None else {"wgsl_code": "@compute fn main() {}"}}
    return client.post(
        f"{prefix}/image-effects", json=body, headers={"Authorization": f"Bearer {token}"}, **kw
    )


def token_for(client, action="save_shader", name="my-preset") -> str:
    response = mint(client, action, name)
    assert response.status_code == 200, response.text
    return response.json()["token"]


# --- happy path -------------------------------------------------------------

@pytest.mark.parametrize("prefix", ["", "/webhook"])
def test_round_trip_saves_a_shader(client, bucket, prefix):
    issued = mint(client, prefix=prefix)
    assert issued.status_code == 200
    body = issued.json()
    assert body["expires_in"] == 60
    assert body["expires_at"].endswith("Z")
    assert issued.headers["cache-control"] == "no-store"

    response = write(client, body["token"], prefix=prefix)
    assert response.status_code == 200, response.text
    assert response.json() == {
        "status": "success",
        "message": "Shader saved as my-preset",
        "files": ["image-effects/shaders/my-preset.wgsl"],
    }
    assert bucket.text("image-effects/shaders/my-preset.wgsl") == "@compute fn main() {}"
    # Registered in the existing shader library (same index as /api/shaders/upload).
    assert bucket.text("shaders/my-preset.wgsl") == "@compute fn main() {}"
    index = json.loads(bucket.text("shaders/_shaders.json"))
    assert [s["id"] for s in index] == ["my-preset"]
    assert index[0]["filename"] == "my-preset.wgsl"


def test_resaving_a_shader_keeps_its_ratings(client, bucket):
    write(client, token_for(client))
    index = json.loads(bucket.text("shaders/_shaders.json"))
    index[0]["stars"], index[0]["rating_count"] = 4.5, 7
    bucket.objects["shaders/_shaders.json"] = (json.dumps(index), "application/json")

    assert write(client, token_for(client), data={"wgsl_code": "// v2"}).status_code == 200
    index = json.loads(bucket.text("shaders/_shaders.json"))
    assert len(index) == 1 and index[0]["stars"] == 4.5 and index[0]["rating_count"] == 7
    assert bucket.text("shaders/my-preset.wgsl") == "// v2"


@pytest.mark.parametrize(
    "action,name,data,expected_file",
    [
        ("save_metadata", "cfg", {"type": "effect_config", "x": 1}, "image-effects/metadata/cfg.json"),
        ("save_video_config", "clip.json", {"type": "video_config"}, "image-effects/video-configs/clip.json"),
        ("save_output", "shot", {"image_data": "data:image/png;base64," + PNG_B64}, "image-effects/outputs/shot.png"),
        ("upload_texture", "My Photo (1).PNG", {"texture_data": PNG_B64, "file_name": "My Photo (1).PNG"}, "image-effects/textures/My-Photo-1.png"),
        ("upload_audio", "loop.wav", {"file_data": base64.b64encode(b"RIFF").decode(), "file_name": "loop.wav"}, "image-effects/audio/loop.wav"),
    ],
)
def test_every_action_dispatches(client, bucket, action, name, data, expected_file):
    response = write(client, token_for(client, action, name), action=action, name=name, data=data)
    assert response.status_code == 200, response.text
    assert response.json()["files"] == [expected_file]
    assert expected_file in bucket.objects


def test_all_six_documented_actions_are_allow_listed():
    assert set(webhook.ALLOWED_ACTIONS) == set(ACTIONS)


def test_bad_payloads_are_400_not_500(client):
    assert write(client, token_for(client), data={}).status_code == 400  # no wgsl_code
    t = token_for(client, "save_output", "x")
    assert write(client, t, action="save_output", name="x", data={"image_data": ""}).status_code == 400


def test_names_cannot_escape_the_storage_prefix(client, bucket):
    name = "../../etc/passwd"
    response = write(client, token_for(client, "save_metadata", name), action="save_metadata", name=name, data={"a": 1})
    assert response.status_code == 200
    (path,) = response.json()["files"]
    assert path == "image-effects/metadata/passwd.json"
    assert ".." not in path
    # A name with nothing usable is refused rather than written to a bare ".json".
    assert write(client, token_for(client, "save_metadata", "..."), action="save_metadata", name="...", data={}).status_code == 400


# --- expiry / replay --------------------------------------------------------

def test_expired_token_is_401(client, bucket, monkeypatch):
    token = token_for(client)
    real = time.time()
    monkeypatch.setattr(webhook, "_now", lambda: real + config.WEBHOOK_TOKEN_TTL_SECONDS + 1)
    response = write(client, token)
    assert response.status_code == 401
    assert response.json()["error"] == "token_expired"
    assert response.headers["www-authenticate"].startswith("Bearer")
    assert not bucket.objects


def test_token_valid_until_the_last_second(client, monkeypatch):
    token = token_for(client)
    real = time.time()
    monkeypatch.setattr(webhook, "_now", lambda: real + config.WEBHOOK_TOKEN_TTL_SECONDS - 2)
    assert write(client, token).status_code == 200


def test_replayed_token_is_401(client, bucket):
    token = token_for(client)
    assert write(client, token).status_code == 200
    bucket.objects.clear()
    replay = write(client, token)
    assert replay.status_code == 401
    assert replay.json()["error"] == "token_already_used"
    assert not bucket.objects, "a replay must not write anything"


# --- scope / tampering ------------------------------------------------------

def test_wrong_action_or_name_is_403_and_does_not_burn_the_token(client, bucket):
    token = token_for(client, "save_shader", "my-preset")
    other_action = write(client, token, action="save_metadata", data={"a": 1})
    other_name = write(client, token, name="someone-elses")
    assert other_action.status_code == 403 and other_action.json()["error"] == "token_mismatch"
    assert other_name.status_code == 403 and other_name.json()["error"] == "token_mismatch"
    assert not bucket.objects
    assert write(client, token).status_code == 200  # the legitimate use still works


def test_tampered_tokens_are_refused(client, bucket):
    version, expiry, nonce, sig = token_for(client).split(".")
    flipped = sig[:-1] + ("A" if sig[-1] != "A" else "B")
    forged_expiry = str(int(expiry) + 3600)
    for tampered in (
        f"{version}.{expiry}.{nonce}.{flipped}",
        f"{version}.{forged_expiry}.{nonce}.{sig}",
        f"{version}.{expiry}.{nonce}x.{sig}",
        f"{version}.{expiry}.{nonce}.",
    ):
        response = write(client, tampered)
        assert response.status_code in (401, 403), tampered
    assert not bucket.objects


def test_garbage_and_missing_credentials_are_401(client):
    assert client.post("/image-effects", json={"action": "save_shader", "name": "a"}).status_code == 401
    for header in ("Bearer", "Bearer not-a-token", "Basic abc", "Bearer v1.1.2"):
        response = client.post(
            "/image-effects", json={"action": "save_shader", "name": "a"}, headers={"Authorization": header}
        )
        assert response.status_code == 401, header
        assert response.json()["status"] == "error"


def test_token_signed_with_another_secret_is_rejected(client, monkeypatch):
    token = token_for(client)
    monkeypatch.setattr(config, "WEBHOOK_SIGNING_SECRET", "rotated-secret-" + "y" * 32)
    assert write(client, token).status_code == 403


def test_signature_is_compared_in_constant_time(client, monkeypatch):
    calls = []
    real = webhook.hmac.compare_digest
    monkeypatch.setattr(webhook.hmac, "compare_digest", lambda a, b: calls.append(1) or real(a, b))
    write(client, token_for(client))
    assert calls


def test_invalid_requests_to_upload_token(client):
    assert mint(client, action="delete_everything").status_code == 400
    assert mint(client, action="").status_code == 400
    assert mint(client, name="").status_code == 400
    assert mint(client, name="x" * 257).status_code == 400
    assert mint(client, name="bad\nname").status_code == 400
    assert client.post("/upload-token", json=["save_shader"]).status_code == 400
    assert client.post("/upload-token", content=b"{nope").status_code == 400
    assert client.post("/upload-token", json={"action": "save_shader", "name": 5}).status_code == 400


# --- missing secret / origin / limits ---------------------------------------

@pytest.mark.parametrize("secret", ["", "too-short"])
def test_unset_or_weak_secret_is_503(client, monkeypatch, secret):
    monkeypatch.setattr(config, "WEBHOOK_SIGNING_SECRET", secret)
    for prefix in ("", "/webhook"):
        issued = mint(client, prefix=prefix)
        assert issued.status_code == 503
        assert issued.json()["error"] == "webhook_unavailable"
        assert write(client, "v1.1.n.s", prefix=prefix).status_code == 503


def test_startup_warns_when_the_secret_is_unset(monkeypatch, caplog):
    monkeypatch.setattr(config, "WEBHOOK_SIGNING_SECRET", "")
    with caplog.at_level(logging.WARNING, logger="storage_manager.webhook"):
        webhook.log_startup_status()
    assert "WEBHOOK_SIGNING_SECRET is unset" in caplog.text
    caplog.clear()
    monkeypatch.setattr(config, "WEBHOOK_SIGNING_SECRET", SECRET)
    with caplog.at_level(logging.WARNING, logger="storage_manager.webhook"):
        webhook.log_startup_status()
    assert caplog.text == ""


@pytest.mark.parametrize("origin", ["https://evil.example", "http://test.1ink.us", "https://test.1ink.us.evil.example", None])
def test_disallowed_origin_is_403_on_both_routes(client, origin):
    token = token_for(client)
    headers = {"Origin": origin} if origin else {}
    # TestClient merges default headers; override or drop Origin explicitly.
    fresh = TestClient(app)
    fresh.headers.update({"X-Forwarded-For": client.headers["X-Forwarded-For"], **headers})
    issued = mint(fresh)
    assert issued.status_code == 403 and issued.json()["error"] == "origin_not_allowed"
    assert write(fresh, token).status_code == 403
    # The refusal did not consume the token.
    assert write(client, token).status_code == 200


def test_wildcard_cors_entry_does_not_open_the_token_routes(client):
    assert "*" in config.ALLOWED_ORIGINS  # CORS stays open; the token routes do not follow it
    fresh = TestClient(app)
    fresh.headers.update({"Origin": "https://anywhere.example", "X-Forwarded-For": client.headers["X-Forwarded-For"]})
    assert mint(fresh).status_code == 403


def test_extra_origin_from_env_is_honoured(client, monkeypatch):
    monkeypatch.setattr(config, "WEBHOOK_EXTRA_ORIGINS", ["https://studio.example"])
    fresh = TestClient(app)
    fresh.headers.update({"Origin": "https://studio.example/", "X-Forwarded-For": client.headers["X-Forwarded-For"]})
    assert mint(fresh).status_code == 200


def test_webhook_routes_have_their_own_rate_limit(client, monkeypatch):
    monkeypatch.setattr(config, "WEBHOOK_RATE_LIMIT_REQUESTS", 3)
    statuses = [mint(client).status_code for _ in range(5)]
    assert statuses == [200, 200, 200, 429, 429]
    # The generic /api bucket is untouched by webhook traffic.
    assert client.get("/api/health").status_code != 429


def test_oversized_body_is_413(client, monkeypatch):
    monkeypatch.setattr(config, "WEBHOOK_MAX_BODY_BYTES", 2048)
    token = token_for(client)
    response = write(client, token, data={"wgsl_code": "x" * 5000})
    assert response.status_code == 413
    assert write(client, token, data={"wgsl_code": "x"}).status_code == 200  # token not burned


def test_missing_bucket_is_503(client, monkeypatch):
    monkeypatch.setattr(state, "bucket", None)
    response = write(client, token_for(client))
    assert response.status_code == 503 and response.json()["error"] == "storage_unavailable"


def test_failed_write_is_500_without_leaking_internals(client, bucket, monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("gcs exploded with " + SECRET)

    monkeypatch.setattr(FakeBlob, "upload_from_string", boom)
    response = write(client, token_for(client))
    assert response.status_code == 500
    assert SECRET not in response.text and "exploded" not in response.text


# --- secrets never leak -----------------------------------------------------

def test_secret_and_tokens_never_appear_in_responses_or_logs(client, bucket, caplog, capfd):
    with caplog.at_level(logging.DEBUG):
        issued = mint(client)
        token = issued.json()["token"]
        responses = [issued, write(client, token), write(client, token), write(client, "v1.1.2.3"), mint(client, action="nope")]
    out, err = capfd.readouterr()
    sig = token.split(".")[-1]
    # Only the /upload-token response may carry the token; nothing may carry the secret.
    carried_elsewhere = "\n".join(r.text + json.dumps(dict(r.headers)) for r in responses[1:]) + caplog.text + out + err
    assert SECRET not in carried_elsewhere + issued.text + json.dumps(dict(issued.headers))
    assert token not in carried_elsewhere
    assert sig not in carried_elsewhere


# --- nonce stores -----------------------------------------------------------

@pytest.mark.asyncio
async def test_memory_store_is_single_use_and_forgets_after_ttl(monkeypatch):
    store = webhook._MemoryNonceStore()
    assert await store.consume("n1", 60) is True
    assert await store.consume("n1", 60) is False
    base = time.time()
    monkeypatch.setattr(webhook, "_now", lambda: base + 120)
    assert await store.consume("n1", 60) is True  # purged after its window


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture()
def redis_server():
    binary = shutil.which("redis-server")
    if not binary:
        pytest.skip("redis-server is not installed")
    port = _free_port()
    proc = subprocess.Popen(
        [binary, "--port", str(port), "--bind", "127.0.0.1", "--save", "", "--appendonly", "no"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        import redis

        probe = redis.Redis(port=port)
        for _ in range(50):
            try:
                probe.ping()
                break
            except redis.ConnectionError:
                time.sleep(0.1)
        else:
            pytest.fail("redis-server did not start")
        yield port
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def test_redis_backed_single_use_across_workers(client, bucket, monkeypatch, redis_server):
    monkeypatch.setattr(config, "REDIS_URL", f"redis://127.0.0.1:{redis_server}/0")
    webhook._reset_store()
    token = token_for(client)
    assert write(client, token).status_code == 200
    assert webhook._get_store().kind == "redis"

    # A second worker = a second store instance on the same Redis: still a replay.
    webhook._reset_store()
    replay = write(client, token)
    assert replay.status_code == 401 and replay.json()["error"] == "token_already_used"

    import redis

    # Nonces live in their own logical DB (config.WEBHOOK_REDIS_DB), not the cache's.
    nonce_db = redis.Redis(port=redis_server, db=config.WEBHOOK_REDIS_DB)
    keys = nonce_db.keys("storage_manager:webhook_nonce:*")
    assert len(keys) == 1
    assert 0 < nonce_db.ttl(keys[0]) <= config.WEBHOOK_TOKEN_TTL_SECONDS + webhook.NONCE_GRACE_SECONDS
    assert redis.Redis(port=redis_server, db=0).keys("storage_manager:webhook_nonce:*") == []


def test_redis_nonces_survive_a_cache_flush(bucket, monkeypatch, redis_server):
    """Regression: saving a shader runs `clear_cache_for_type`, which with a Redis
    cache is FLUSHDB. Found by the live uvicorn run: a replayed save_shader token
    was accepted because the flush had erased its nonce."""
    import redis

    url = f"redis://127.0.0.1:{redis_server}/0"
    monkeypatch.setattr(config, "REDIS_URL", url)
    monkeypatch.setattr(state, "REDIS_URL", url)
    monkeypatch.setattr(state, "cache", state._create_cache_backend())  # the production Redis cache backend
    webhook._reset_store()

    redis.Redis(port=redis_server, db=0).set("response-cache-entry", "1")
    # One event loop for the whole test, like uvicorn (a bare TestClient makes one per request).
    with TestClient(app, headers={"Origin": ORIGIN, "X-Forwarded-For": f"flush-{uuid.uuid4().hex}"}) as c:
        token = token_for(c)
        assert write(c, token).status_code == 200  # save_shader -> clear_cache_for_type -> FLUSHDB on db 0
        assert redis.Redis(port=redis_server, db=0).get("response-cache-entry") is None, "the flush really happened"

        replay = write(c, token)
        assert replay.status_code == 401 and replay.json()["error"] == "token_already_used"


def test_nonce_db_may_not_share_the_cache_db(client, bucket, monkeypatch, redis_server):
    monkeypatch.setattr(config, "REDIS_URL", f"redis://127.0.0.1:{redis_server}/3")
    monkeypatch.setattr(config, "WEBHOOK_REDIS_DB", 3)
    webhook._reset_store()
    response = write(client, token_for(client))
    assert response.status_code == 503 and response.json()["error"] == "token_store_unavailable"
    assert not bucket.objects


def test_redis_down_fails_closed(client, bucket, monkeypatch):
    monkeypatch.setattr(config, "REDIS_URL", f"redis://127.0.0.1:{_free_port()}/0")  # nothing listening
    webhook._reset_store()
    response = write(client, token_for(client))
    assert response.status_code == 503
    assert response.json()["error"] == "token_store_unavailable"
    assert not bucket.objects
