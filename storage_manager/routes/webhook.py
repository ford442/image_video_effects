# storage_manager/routes/webhook.py
"""Server-issued upload tokens + webhook writes (docs/STORAGE_API.md).

The browser never holds a signing secret:

  POST /upload-token   {action, name}            -> {token, expires_at}
  POST /image-effects  Authorization: Bearer <t> -> performs the write

A token is ``v1.<expiry>.<nonce>.<sig>`` where ``sig`` is
HMAC-SHA256(WEBHOOK_SIGNING_SECRET, "action|name|expiry|nonce"). It is valid
for one ``action`` + ``name``, for WEBHOOK_TOKEN_TTL_SECONDS, and once
(the nonce is recorded in Redis when REDIS_* is set, else in this process).

What a token is *not*: proof of who the caller is. Anyone who can send an
allowed ``Origin`` header can ask for one; the controls are the origin check,
the dedicated rate-limit bucket, the short scoped lifetime, the action
allow-list, name sanitising and the body-size cap.

Secrets, tokens and signatures are never logged or returned.
"""
import base64
import binascii
import hashlib
import hmac
import json
import logging
import re
import secrets
import time
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple
from urllib.parse import urlparse, urlunparse

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from .. import config, state, utils

ALLOWED_ACTIONS = (
    "save_shader",
    "save_metadata",
    "save_output",
    "save_video_config",
    "upload_texture",
    "upload_audio",
)
MAX_NAME_LENGTH = 256
MAX_SHADER_BYTES = 1024 * 1024
TOKEN_VERSION = "v1"
# A consumed nonce is remembered a little past the token's expiry so a replay
# right at the boundary (clock skew between workers) is still rejected.
NONCE_GRACE_SECONDS = 5

_TEXTURE_EXTS = {"png", "jpg", "jpeg", "webp", "gif", "bmp"}
_AUDIO_EXTS = {"mp3", "wav", "ogg", "flac", "m4a", "aac", "opus"}
_MIME_EXT = {
    "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif", "image/bmp": "bmp",
    "audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/wav": "wav", "audio/x-wav": "wav", "audio/ogg": "ogg",
    "audio/flac": "flac", "audio/mp4": "m4a", "audio/aac": "aac",
}
_EXT_MIME = {
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "gif": "image/gif",
    "bmp": "image/bmp", "mp3": "audio/mpeg", "wav": "audio/wav", "ogg": "audio/ogg", "flac": "audio/flac",
    "m4a": "audio/mp4", "aac": "audio/aac", "opus": "audio/ogg",
}

_logger = logging.getLogger("storage_manager.webhook")

router = APIRouter()


# --- helpers ---------------------------------------------------------------

def _now() -> float:
    return time.time()


def _error(status: int, code: str, message: str, headers: Optional[Dict[str, str]] = None) -> JSONResponse:
    return JSONResponse(
        {"status": "error", "error": code, "message": message},
        status_code=status,
        headers=headers,
    )


def _unauthorized(code: str, message: str) -> JSONResponse:
    return _error(401, code, message, {"WWW-Authenticate": 'Bearer realm="image-effects"'})


def secret_configured() -> bool:
    return len(config.WEBHOOK_SIGNING_SECRET or "") >= config.WEBHOOK_SECRET_MIN_LENGTH


def log_startup_status() -> None:
    """Called from the app lifespan: say clearly why the routes will 503."""
    if secret_configured():
        return
    reason = "unset" if not config.WEBHOOK_SIGNING_SECRET else f"shorter than {config.WEBHOOK_SECRET_MIN_LENGTH} characters"
    _logger.warning(
        "WEBHOOK_SIGNING_SECRET is %s: POST /upload-token and POST /image-effects will return 503 "
        "until it is set (generate one with: openssl rand -hex 32).",
        reason,
    )


def _allowed_origins() -> set:
    explicit = {o.rstrip("/") for o in config.ALLOWED_ORIGINS if o and o != "*"}
    return explicit | {o.rstrip("/") for o in config.WEBHOOK_EXTRA_ORIGINS}


def _origin_ok(request: Request) -> bool:
    """CORS allows "*", so the token routes enforce the explicit list instead.

    A missing Origin is refused: browsers always send one on a cross-origin
    POST. (Non-browser callers can forge it, so this is hygiene, not auth.)
    """
    origin = request.headers.get("origin", "").rstrip("/")
    return bool(origin) and origin in _allowed_origins()


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _sign(action: str, name: str, expiry: int, nonce: str) -> str:
    message = f"{action}|{name}|{expiry}|{nonce}".encode("utf-8")
    digest = hmac.new(config.WEBHOOK_SIGNING_SECRET.encode("utf-8"), message, hashlib.sha256).digest()
    return _b64url(digest)


def issue_token(action: str, name: str) -> Tuple[str, int]:
    expiry = int(_now()) + config.WEBHOOK_TOKEN_TTL_SECONDS
    nonce = secrets.token_urlsafe(16)
    return f"{TOKEN_VERSION}.{expiry}.{nonce}.{_sign(action, name, expiry, nonce)}", expiry


def _parse_token(token: str) -> Optional[Tuple[int, str, str]]:
    parts = token.split(".")
    if len(parts) != 4 or parts[0] != TOKEN_VERSION or not parts[1].isdigit() or not parts[2] or not parts[3]:
        return None
    return int(parts[1]), parts[2], parts[3]


def _valid_name(name: Any) -> bool:
    return (
        isinstance(name, str)
        and 0 < len(name) <= MAX_NAME_LENGTH
        and not any(ord(ch) < 32 or ord(ch) == 127 for ch in name)
    )


async def _read_json_body(request: Request) -> Tuple[Optional[Dict[str, Any]], Optional[JSONResponse]]:
    limit = config.WEBHOOK_MAX_BODY_BYTES
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > limit:
        return None, _error(413, "payload_too_large", "Request body is too large")
    chunks, size = [], 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > limit:
            return None, _error(413, "payload_too_large", "Request body is too large")
        chunks.append(chunk)
    try:
        body = json.loads(b"".join(chunks) or b"null")
    except (ValueError, UnicodeDecodeError):
        return None, _error(400, "invalid_request", "Body must be a JSON object")
    if not isinstance(body, dict):
        return None, _error(400, "invalid_request", "Body must be a JSON object")
    return body, None


def _check_action_name(body: Dict[str, Any]) -> Optional[JSONResponse]:
    if body.get("action") not in ALLOWED_ACTIONS:
        return _error(400, "unsupported_action", f"action must be one of: {', '.join(ALLOWED_ACTIONS)}")
    if not _valid_name(body.get("name")):
        return _error(400, "invalid_name", f"name must be 1-{MAX_NAME_LENGTH} characters with no control characters")
    return None


# --- single-use nonce store ------------------------------------------------

class _MemoryNonceStore:
    """In-process TTL map. Correct for one worker only; use Redis for more."""

    kind = "memory"

    def __init__(self) -> None:
        self._seen: Dict[str, float] = {}
        self._next_purge = 0.0

    async def consume(self, nonce: str, ttl: int) -> bool:
        now = _now()
        if now >= self._next_purge:
            self._seen = {n: exp for n, exp in self._seen.items() if exp > now}
            self._next_purge = now + 30
        if nonce in self._seen:  # no await between check and set => atomic on the event loop
            return False
        self._seen[nonce] = now + ttl
        return True


class _RedisNonceStore:
    kind = "redis"

    def __init__(self, client: Any) -> None:
        self._client = client

    async def consume(self, nonce: str, ttl: int) -> bool:
        # SET NX EX is atomic: exactly one caller wins the nonce.
        return bool(await self._client.set(f"storage_manager:webhook_nonce:{nonce}", "1", nx=True, ex=max(1, ttl)))


class NonceStoreUnavailable(Exception):
    pass


_store: Any = None
_warned_workers = False


def _redis_configured() -> bool:
    return bool(config.REDIS_URL or config.REDIS_HOST)


def _cache_redis_db() -> int:
    """The logical DB the aiocache response cache uses (and may FLUSHDB)."""
    if config.REDIS_URL:
        path = urlparse(config.REDIS_URL).path.lstrip("/")
        return int(path) if path.isdigit() else 0
    return config.REDIS_DB


def _make_redis_client() -> Any:
    try:
        import redis.asyncio as aioredis
    except ImportError as exc:  # pragma: no cover - redis is in requirements.txt
        raise NonceStoreUnavailable("redis package is not installed") from exc
    db = config.WEBHOOK_REDIS_DB
    if db == _cache_redis_db():
        # The cache is flushed wholesale on every shader save (see config.py).
        raise NonceStoreUnavailable("WEBHOOK_REDIS_DB must differ from the cache's Redis DB")
    if config.REDIS_URL:
        parsed = urlparse(config.REDIS_URL)
        return aioredis.Redis.from_url(urlunparse(parsed._replace(path=f"/{db}")))
    return aioredis.Redis(host=config.REDIS_HOST, port=config.REDIS_PORT, db=db, password=config.REDIS_PASSWORD)


def _get_store() -> Any:
    """Redis when REDIS_* is set (and then fail closed), else in-process."""
    global _store, _warned_workers
    if _store is None:
        if _redis_configured():
            _store = _RedisNonceStore(_make_redis_client())
        else:
            _store = _MemoryNonceStore()
            if not _warned_workers:
                _warned_workers = True
                _logger.warning(
                    "Webhook upload tokens use an in-process single-use store (REDIS_URL/REDIS_HOST unset). "
                    "Run exactly one worker, or set REDIS_URL, otherwise a token can be replayed once per worker."
                )
    return _store


def _reset_store() -> None:
    """Test hook."""
    global _store
    _store = None


# --- storage dispatch ------------------------------------------------------

def _slug(name: str, strip_ext: Tuple[str, ...] = ()) -> str:
    base = name.replace("\\", "/").rsplit("/", 1)[-1]
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", base).strip(".-_")
    for ext in strip_ext:
        if stem.lower().endswith("." + ext):
            stem = stem[: -(len(ext) + 1)]
            break
    return stem[:100].strip(".-_")


def _decode_b64(value: Any) -> bytes:
    if not isinstance(value, str) or not value:
        raise ValueError("missing base64 data")
    if value.startswith("data:") and "," in value:
        value = value.split(",", 1)[1]
    try:
        return base64.b64decode(value, validate=False)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("data is not valid base64") from exc


def _ext_for(data: Dict[str, Any], allowed: set, default: str) -> str:
    file_name = data.get("file_name") if isinstance(data.get("file_name"), str) else ""
    if "." in file_name:
        ext = file_name.rsplit(".", 1)[-1].lower()
        if ext in allowed:
            return ext
    mime = data.get("file_type") if isinstance(data.get("file_type"), str) else ""
    ext = _MIME_EXT.get(mime.lower())
    return ext if ext in allowed else default


class _BadPayload(Exception):
    pass


async def _put(path: str, payload: Any, content_type: str) -> None:
    blob = state.bucket.blob(path)
    await state.run_io(blob.upload_from_string, payload, content_type=content_type)


async def _register_shader(shader_id: str, wgsl: str, name: str, metadata: Dict[str, Any]) -> None:
    """Same index entry as POST /api/shaders/upload, so it appears in /api/shaders."""
    cfg = config.STORAGE_MAP["shader"]
    tags = metadata.get("tags")
    meta = {
        "id": shader_id,
        "name": metadata.get("name") if isinstance(metadata.get("name"), str) else name,
        "author": metadata.get("author") if isinstance(metadata.get("author"), str) else "webhook",
        "date": datetime.now().strftime("%Y-%m-%d"),
        "type": "shader",
        "description": metadata.get("description") if isinstance(metadata.get("description"), str) else "",
        "tags": [t for t in tags if isinstance(t, str)] if isinstance(tags, list) else [],
        "filename": f"{shader_id}.wgsl",
        "coordinate": metadata.get("coordinate") if isinstance(metadata.get("coordinate"), int) else None,
        "stars": 0.0,
        "rating_count": 0,
        "play_count": 0,
        "thumbnail": None,
        "thumbnail_url": None,
    }
    async with state.get_resource_lock("shader"):
        await _put(f"{cfg['folder']}{shader_id}.wgsl", wgsl, "text/plain")
        index = await state.run_io(utils._read_json_sync, cfg["index"])
        if not isinstance(index, list):
            index = []
        previous = next((s for s in index if isinstance(s, dict) and s.get("id") == shader_id), None)
        if previous:  # keep ratings/plays/thumbnail when a shader is re-saved
            for key in ("stars", "rating_count", "play_count", "thumbnail", "thumbnail_url"):
                if key in previous:
                    meta[key] = previous[key]
        index = [s for s in index if not (isinstance(s, dict) and s.get("id") == shader_id)]
        index.insert(0, meta)
        await state.run_io(utils._write_json_sync, cfg["index"], index)
    await state.clear_cache_for_type("shader")


async def _dispatch(action: str, name: str, body: Dict[str, Any]) -> Tuple[str, list]:
    data = body.get("data")
    data = data if isinstance(data, dict) else {}
    root = "image-effects"

    if action == "save_shader":
        wgsl = data.get("wgsl_code", body.get("wgsl_code"))
        if not isinstance(wgsl, str) or not wgsl.strip():
            raise _BadPayload("save_shader needs data.wgsl_code")
        if len(wgsl.encode("utf-8")) > MAX_SHADER_BYTES:
            raise _BadPayload("shader is larger than 1 MiB")
        shader_id = _slug(name, ("wgsl",))
        if not shader_id:
            raise _BadPayload("name has no usable characters")
        metadata = {**(body.get("metadata") if isinstance(body.get("metadata"), dict) else {}), **data}
        metadata.pop("wgsl_code", None)
        path = f"{root}/shaders/{shader_id}.wgsl"
        await _put(path, wgsl, "text/plain")
        await _register_shader(shader_id, wgsl, name, metadata)
        return f"Shader saved as {shader_id}", [path]

    if action in ("save_metadata", "save_video_config"):
        stem = _slug(name, ("json",))
        if not stem:
            raise _BadPayload("name has no usable characters")
        folder = "metadata" if action == "save_metadata" else "video-configs"
        path = f"{root}/{folder}/{stem}.json"
        await _put(path, json.dumps(data), "application/json")
        return "Saved", [path]

    if action == "save_output":
        stem = _slug(name, ("png",))
        if not stem:
            raise _BadPayload("name has no usable characters")
        raw = data.get("image_data")
        payload = _decode_b64(raw)
        mime = "image/jpeg" if isinstance(raw, str) and raw.startswith("data:image/jpeg") else "image/png"
        path = f"{root}/outputs/{stem}.{'jpg' if mime == 'image/jpeg' else 'png'}"
        await _put(path, payload, mime)
        return "Output saved", [path]

    # upload_texture / upload_audio
    allowed, default, folder = (_TEXTURE_EXTS, "png", "textures") if action == "upload_texture" else (_AUDIO_EXTS, "mp3", "audio")
    ext = _ext_for(data, allowed, default)
    stem = _slug(name, tuple(allowed))
    if not stem:
        raise _BadPayload("name has no usable characters")
    payload = _decode_b64(data.get("texture_data") if data.get("texture_data") else data.get("file_data"))
    path = f"{root}/{folder}/{stem}.{ext}"
    await _put(path, payload, _EXT_MIME.get(ext, "application/octet-stream"))
    return "Uploaded", [path]


# --- routes ----------------------------------------------------------------

def _gate(request: Request) -> Optional[JSONResponse]:
    if not secret_configured():
        return _error(503, "webhook_unavailable", "Upload tokens are not configured on this server")
    if not _origin_ok(request):
        return _error(403, "origin_not_allowed", "Origin is not allowed")
    return None


@router.post("/upload-token")
async def create_upload_token(request: Request):
    refused = _gate(request)
    if refused:
        return refused
    body, bad = await _read_json_body(request)
    if bad:
        return bad
    refused = _check_action_name(body)
    if refused:
        return refused
    token, expiry = issue_token(body["action"], body["name"])
    state._log_event("webhook_token_issued", action=body["action"])
    return JSONResponse(
        {
            "token": token,
            "expires_at": datetime.fromtimestamp(expiry, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "expires_in": config.WEBHOOK_TOKEN_TTL_SECONDS,
        },
        headers={"Cache-Control": "no-store"},
    )


@router.post("/image-effects")
async def image_effects(request: Request):
    refused = _gate(request)
    if refused:
        return refused

    scheme, _, credential = request.headers.get("authorization", "").partition(" ")
    credential = credential.strip()
    if scheme.lower() != "bearer" or not credential:
        return _unauthorized("missing_token", "Authorization: Bearer <upload token> is required")
    parsed = _parse_token(credential)
    if parsed is None:
        return _unauthorized("invalid_token", "Malformed upload token")
    expiry, nonce, signature = parsed

    body, bad = await _read_json_body(request)
    if bad:
        return bad
    refused = _check_action_name(body)
    if refused:
        return refused
    action, name = body["action"], body["name"]

    # Signature first (covers action, name and expiry): a wrong action/name or a
    # tampered token is refused without burning the real token's nonce.
    expected = _sign(action, name, expiry, nonce)
    if not hmac.compare_digest(expected.encode("ascii"), signature.encode("utf-8", "replace")):
        state._log_event("webhook_token_rejected", reason="signature", action=action)
        return _error(403, "token_mismatch", "Token was not issued for this action and name")
    remaining = expiry - _now()
    if remaining <= 0:
        state._log_event("webhook_token_rejected", reason="expired", action=action)
        return _unauthorized("token_expired", "Upload token has expired; request a new one")
    try:
        fresh = await _get_store().consume(nonce, int(remaining) + NONCE_GRACE_SECONDS)
    except NonceStoreUnavailable as exc:
        _logger.error("webhook nonce store unavailable: %s", exc)
        return _error(503, "token_store_unavailable", "Upload token store is unavailable")
    except Exception:
        # Redis configured but unreachable: fail closed, never skip replay protection.
        _logger.exception("webhook nonce store failed")
        return _error(503, "token_store_unavailable", "Upload token store is unavailable")
    if not fresh:
        state._log_event("webhook_token_rejected", reason="replayed", action=action)
        return _unauthorized("token_already_used", "Upload token was already used; request a new one")

    if state.bucket is None:
        return _error(503, "storage_unavailable", "Storage backend is not connected")
    try:
        message, files = await _dispatch(action, name, body)
    except (_BadPayload, ValueError) as exc:
        return _error(400, "invalid_payload", "Payload is invalid")
    except Exception:
        _logger.exception("webhook write failed (action=%s)", action)
        return _error(500, "write_failed", "Storage write failed")
    state._log_event("webhook_write", action=action, files=files)
    return {"status": "success", "message": message, "files": files}


# Same handlers under /webhook/*, matching the client's default STORAGE_VPS_URL
# (https://<host>/webhook) and the legacy bulk-upload script.
prefixed_router = APIRouter(prefix="/webhook")
prefixed_router.add_api_route("/upload-token", create_upload_token, methods=["POST"])
prefixed_router.add_api_route("/image-effects", image_effects, methods=["POST"])
