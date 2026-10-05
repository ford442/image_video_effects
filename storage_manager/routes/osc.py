# storage_manager/routes/osc.py
"""UDP OSC → WebSocket relay for VJ Studio (opt-in, ``OSC_RELAY_ENABLED=1``).

Browsers cannot receive UDP. This route listens for OSC datagrams on
``OSC_UDP_HOST:OSC_UDP_PORT`` and forwards each one, byte-for-byte, as a binary
frame to every client connected to ``/osc/ws``. Decoding and routing happen in
the browser (``src/services/osc``), so no OSC library is needed here.

The UDP listener starts with the first WebSocket client and stops with the last.
"""
import asyncio
import logging
from typing import Optional, Set
from urllib.parse import urlparse

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status

from .. import config

router = APIRouter()
log = logging.getLogger(__name__)

MAX_DATAGRAM = 65_507
_LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1", "[::1]"}


class OscRelay:
    """Fan-out of raw OSC datagrams to WebSocket clients."""

    def __init__(self) -> None:
        self.clients: Set[WebSocket] = set()
        self.transport: Optional[asyncio.DatagramTransport] = None
        self._lock = asyncio.Lock()

    def datagram_received(self, data: bytes, addr=None) -> None:
        if not data or len(data) > MAX_DATAGRAM or len(data) % 4:
            return  # not a valid OSC packet; drop before it reaches a browser
        for ws in list(self.clients):
            asyncio.ensure_future(self._send(ws, data))

    async def _send(self, ws: WebSocket, data: bytes) -> None:
        try:
            await ws.send_bytes(data)
        except Exception:
            self.clients.discard(ws)

    async def add(self, ws: WebSocket) -> None:
        async with self._lock:
            self.clients.add(ws)
            if self.transport is None:
                loop = asyncio.get_running_loop()
                self.transport, _ = await loop.create_datagram_endpoint(
                    lambda: _Protocol(self),
                    local_addr=(config.OSC_UDP_HOST, config.OSC_UDP_PORT),
                )
                log.info("OSC relay listening on udp://%s:%s", config.OSC_UDP_HOST, config.OSC_UDP_PORT)

    async def remove(self, ws: WebSocket) -> None:
        async with self._lock:
            self.clients.discard(ws)
            if not self.clients and self.transport is not None:
                self.transport.close()
                self.transport = None
                log.info("OSC relay stopped (no clients)")


class _Protocol(asyncio.DatagramProtocol):
    def __init__(self, relay: OscRelay) -> None:
        self.relay = relay

    def datagram_received(self, data: bytes, addr) -> None:
        self.relay.datagram_received(data, addr)


relay = OscRelay()


def origin_allowed(origin: Optional[str]) -> bool:
    """Non-browser clients send no Origin; browsers must be local or allow-listed."""
    if not origin:
        return True
    host = urlparse(origin).hostname or ""
    if host in _LOCAL_HOSTS:
        return True
    allowed = [o for o in config.ALLOWED_ORIGINS if o != "*"] + list(config.OSC_ALLOWED_ORIGINS)
    return origin in allowed


@router.websocket("/osc/ws")
async def osc_ws(websocket: WebSocket):
    if not config.OSC_RELAY_ENABLED:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="OSC relay disabled")
        return
    if not origin_allowed(websocket.headers.get("origin")):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="origin not allowed")
        return
    await websocket.accept()
    try:
        await relay.add(websocket)
    except OSError as e:
        log.error("OSC relay could not bind udp://%s:%s: %s", config.OSC_UDP_HOST, config.OSC_UDP_PORT, e)
        await websocket.close(code=status.WS_1011_INTERNAL_ERROR, reason="UDP bind failed")
        return
    try:
        while True:
            # Inbound frames are ignored (browser → desk sending is future work);
            # receiving keeps the socket alive and surfaces disconnects.
            message = await websocket.receive()
            if message.get("type") == "websocket.disconnect":
                break
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        await relay.remove(websocket)
