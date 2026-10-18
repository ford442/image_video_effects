"""OSC → WebSocket relay (VJ Studio). Uses loopback UDP on an ephemeral port only."""

import socket

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from storage_manager import config
from storage_manager.routes import osc


def _app() -> FastAPI:
    app = FastAPI()
    app.include_router(osc.router)
    return app


@pytest.fixture
def relay_on(monkeypatch):
    monkeypatch.setattr(config, "OSC_RELAY_ENABLED", True)
    monkeypatch.setattr(config, "OSC_UDP_HOST", "127.0.0.1")
    monkeypatch.setattr(config, "OSC_UDP_PORT", 0)  # ephemeral
    yield


# "/pixelocity/slot/1/param/x" ,f 0.5
PACKET = (
    b"/pixelocity/slot/1/param/x\x00\x00"
    b",f\x00\x00"
    b"\x3f\x00\x00\x00"
)


def test_disabled_by_default(monkeypatch):
    monkeypatch.setattr(config, "OSC_RELAY_ENABLED", False)
    with pytest.raises(WebSocketDisconnect) as exc:
        with TestClient(_app()).websocket_connect("/osc/ws") as ws:
            ws.receive_bytes()
    assert exc.value.code == 1008


def test_rejects_foreign_origin(relay_on):
    with pytest.raises(WebSocketDisconnect) as exc:
        with TestClient(_app()).websocket_connect("/osc/ws", headers={"origin": "https://evil.example"}) as ws:
            ws.receive_bytes()
    assert exc.value.code == 1008


@pytest.mark.parametrize("origin", ["http://localhost:3000", "http://127.0.0.1:4173", "https://test.1ink.us"])
def test_origin_allowed(origin):
    assert osc.origin_allowed(origin)


def test_forwards_datagrams_verbatim_and_stops_listener(relay_on):
    with TestClient(_app()).websocket_connect("/osc/ws", headers={"origin": "http://localhost:3000"}) as ws:
        assert osc.relay.transport is not None
        host, port = osc.relay.transport.get_extra_info("sockname")[:2]
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.sendto(b"bad", (host, port))  # not a multiple of 4: dropped
            s.sendto(PACKET, (host, port))
        assert ws.receive_bytes() == PACKET
    assert osc.relay.transport is None
    assert not osc.relay.clients


def test_drops_malformed_sizes():
    sent = []

    class FakeWs:
        async def send_bytes(self, data):
            sent.append(data)

    r = osc.OscRelay()
    r.clients.add(FakeWs())
    r.datagram_received(b"")
    r.datagram_received(b"abc")
    r.datagram_received(b"x" * (osc.MAX_DATAGRAM + 1))
    assert sent == []
