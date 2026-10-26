# storage_manager/routes/webhook_sign.py
"""Server-side signing for the image-effects storage webhook.

The HMAC secret used to be inlined into the client bundle (REACT_APP_WEBHOOK_SECRET),
so anyone could read it from the JS and forge uploads. It now lives only here, in the
``STORAGE_WEBHOOK_SECRET`` environment variable. The browser posts the exact payload
it is about to send; this route checks it and returns the ``X-Hub-Signature-256``
value, so the webhook receiver keeps verifying signatures unchanged.

A signature is only issued for an allow-listed action with a fresh timestamp, so a
captured one stops being useful after ``WEBHOOK_SIGN_MAX_AGE_SECONDS``.
"""
import hashlib
import hmac
import json
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from .. import config

router = APIRouter()

ALLOWED_ACTIONS = {
    "save_shader",
    "save_metadata",
    "save_output",
    "save_video_config",
    "upload_texture",
    "upload_audio",
}


class SignRequest(BaseModel):
    payload: str


def sign_payload(payload: str, secret: str) -> str:
    digest = hmac.new(secret.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()
    return f"sha256={digest}"


def _parse_timestamp(value: object) -> datetime:
    if not isinstance(value, str):
        raise ValueError("timestamp must be an ISO string")
    ts = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return ts


def validate_payload(payload: str, now: datetime) -> None:
    """Raise HTTPException unless ``payload`` is a webhook body we are willing to sign."""
    if len(payload) > config.WEBHOOK_SIGN_MAX_BYTES:
        raise HTTPException(status_code=413, detail="Payload too large to sign")
    try:
        body = json.loads(payload)
    except ValueError:
        raise HTTPException(status_code=400, detail="Payload is not JSON")
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="Payload must be a JSON object")
    if body.get("action") not in ALLOWED_ACTIONS:
        raise HTTPException(status_code=400, detail="Action not allowed")
    if not isinstance(body.get("name"), str) or not body["name"]:
        raise HTTPException(status_code=400, detail="Payload needs a name")
    try:
        ts = _parse_timestamp(body.get("timestamp"))
    except ValueError:
        raise HTTPException(status_code=400, detail="Payload needs an ISO timestamp")
    age = abs((now - ts).total_seconds())
    if age > config.WEBHOOK_SIGN_MAX_AGE_SECONDS:
        raise HTTPException(status_code=400, detail="Payload timestamp is stale")


@router.post("/api/storage/sign-webhook")
async def sign_webhook(req: SignRequest, request: Request):
    secret = config.STORAGE_WEBHOOK_SECRET
    if not secret:
        raise HTTPException(status_code=503, detail="Webhook signing is not configured")
    origin = request.headers.get("origin")
    if origin is not None and origin not in config.WEBHOOK_SIGN_ALLOWED_ORIGINS:
        raise HTTPException(status_code=403, detail="Origin not allowed")
    validate_payload(req.payload, datetime.now(timezone.utc))
    return {"signature": sign_payload(req.payload, secret)}
