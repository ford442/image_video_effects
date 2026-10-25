# storage_manager/routes/webhook_proxy.py
"""Server-side signing proxy for storage webhook writes (#1511 bug 2).

The browser used to HMAC-sign uploads with a secret inlined into the JS bundle.
It now POSTs the unsigned payload here; this route signs the raw body with
WEBHOOK_SECRET and forwards it to WEBHOOK_RECEIVER_URL with the same
`X-Hub-Signature-256: sha256=<hex>` header the client used to send.
"""
import hashlib
import hmac

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from .. import config

router = APIRouter()

PROXY_TIMEOUT_SECONDS = 30.0


def sign_body(body: bytes, secret: str) -> str:
    return "sha256=" + hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()


@router.post("/api/webhook-proxy/image-effects")
async def webhook_proxy_image_effects(request: Request):
    secret = config.WEBHOOK_SECRET
    receiver = config.WEBHOOK_RECEIVER_URL
    if not secret or not receiver:
        return JSONResponse(
            status_code=503,
            content={"detail": "Webhook proxy is not configured (WEBHOOK_SECRET / WEBHOOK_RECEIVER_URL)"},
        )

    body = await request.body()
    headers = {
        "Content-Type": "application/json",
        "X-Hub-Signature-256": sign_body(body, secret),
    }
    try:
        async with httpx.AsyncClient(timeout=PROXY_TIMEOUT_SECONDS) as client:
            upstream = await client.post(receiver, content=body, headers=headers)
    except httpx.HTTPError as e:
        return JSONResponse(status_code=502, content={"detail": f"Webhook receiver unreachable: {e}"})

    try:
        payload = upstream.json()
    except ValueError:
        payload = {"detail": upstream.text}
    return JSONResponse(status_code=upstream.status_code, content=payload)
