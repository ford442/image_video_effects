"""Rate-limit client identification and TRUSTED_PROXIES.

X-Forwarded-For is client-controlled. It may only be believed when the TCP peer is
a proxy we trust, and then only the right-most hop that is not itself a trusted proxy.
"""

from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from storage_manager import config
from storage_manager.middleware import RateLimitMiddleware, parse_trusted_proxies, resolve_client_ip

LOOPBACK = parse_trusted_proxies("127.0.0.1,::1")
NET = parse_trusted_proxies("10.0.0.0/8, 192.0.2.7")


# --- parse_trusted_proxies --------------------------------------------------

def test_parse_accepts_ips_cidrs_and_blanks():
    nets = parse_trusted_proxies(" 127.0.0.1 , 10.0.0.0/8,, ::1 ")
    assert [str(n) for n in nets] == ["127.0.0.1/32", "10.0.0.0/8", "::1/128"]
    assert parse_trusted_proxies("") == [] and parse_trusted_proxies(None) == []
    assert [str(n) for n in parse_trusted_proxies(["172.16.0.0/12"])] == ["172.16.0.0/12"]


def test_parse_skips_bad_entries_instead_of_trusting_more(caplog):
    nets = parse_trusted_proxies("not-an-ip,10.0.0.1,10.0.0.0/99")
    assert [str(n) for n in nets] == ["10.0.0.1/32"]
    assert "invalid TRUSTED_PROXIES entry" in caplog.text


# --- resolve_client_ip ------------------------------------------------------

def test_header_ignored_when_peer_is_not_trusted():
    # A direct client choosing its own bucket: the whole point of the fix.
    assert resolve_client_ip("203.0.113.9", ["1.2.3.4"], LOOPBACK) == "203.0.113.9"
    assert resolve_client_ip("203.0.113.9", ["1.2.3.4, 5.6.7.8"], NET) == "203.0.113.9"


def test_header_ignored_when_no_proxy_is_trusted():
    assert resolve_client_ip("127.0.0.1", ["1.2.3.4"], []) == "127.0.0.1"


def test_trusted_peer_uses_the_header():
    assert resolve_client_ip("127.0.0.1", ["198.51.100.4"], LOOPBACK) == "198.51.100.4"
    assert resolve_client_ip("::1", ["198.51.100.4"], LOOPBACK) == "198.51.100.4"


def test_rightmost_untrusted_hop_wins_over_spoofed_left_entries():
    # client sent "X-Forwarded-For: 6.6.6.6"; nginx (trusted) appended the real peer 198.51.100.4.
    assert resolve_client_ip("127.0.0.1", ["6.6.6.6, 198.51.100.4"], LOOPBACK) == "198.51.100.4"


def test_trusted_hops_are_skipped_from_the_right():
    # real client -> edge proxy 10.0.0.5 -> inner proxy 10.0.0.9 (peer)
    assert resolve_client_ip("10.0.0.9", ["6.6.6.6, 198.51.100.4, 10.0.0.5"], NET) == "198.51.100.4"


def test_multiple_header_lines_are_one_chain():
    assert resolve_client_ip("10.0.0.9", ["6.6.6.6", "198.51.100.4, 10.0.0.5"], NET) == "198.51.100.4"


def test_all_hops_trusted_falls_back_to_leftmost():
    assert resolve_client_ip("10.0.0.9", ["10.1.1.1, 10.0.0.5"], NET) == "10.1.1.1"


def test_garbage_header_never_becomes_a_bucket_key():
    for bad in ["garbage", "198.51.100.4, <script>", "unknown", "1.2.3.4:8080"]:
        assert resolve_client_ip("127.0.0.1", [bad], LOOPBACK) == "127.0.0.1", bad


def test_missing_header_or_peer():
    assert resolve_client_ip("127.0.0.1", [], LOOPBACK) == "127.0.0.1"
    assert resolve_client_ip(None, ["1.2.3.4"], LOOPBACK) == "unknown"
    assert resolve_client_ip("testclient", ["1.2.3.4"], LOOPBACK) == "testclient"  # non-IP peer: header ignored


def test_ipv4_mapped_ipv6_matches_the_ipv4_proxy_and_client():
    assert resolve_client_ip("::ffff:127.0.0.1", ["::ffff:198.51.100.4"], LOOPBACK) == "198.51.100.4"


def test_ipv6_clients_are_keyed_normalised():
    assert resolve_client_ip("127.0.0.1", ["2001:DB8:0:0:0:0:0:1"], LOOPBACK) == "2001:db8::1"


# --- through the real middleware -------------------------------------------

def _limited_app(limit: int = 3) -> FastAPI:
    app = FastAPI()
    app.add_middleware(RateLimitMiddleware, requests=limit, window=60, path_prefixes=["/api"])

    @app.get("/api/ping")
    async def ping():
        return {"ok": True}

    return app


def _statuses(client: TestClient, n: int, **headers) -> list:
    return [client.get("/api/ping", headers=headers).status_code for _ in range(n)]


@pytest.fixture()
def trust(monkeypatch):
    def _set(value: str):
        monkeypatch.setattr(config, "TRUSTED_PROXIES", value)
    return _set


def test_spoofing_the_header_from_an_untrusted_peer_does_not_dodge_the_limit(trust):
    trust("127.0.0.1,::1")
    client = TestClient(_limited_app(), client=("203.0.113.9", 1))
    codes = [client.get("/api/ping", headers={"X-Forwarded-For": f"9.9.9.{i}"}).status_code for i in range(5)]
    assert codes == [200, 200, 200, 429, 429]


def test_default_trusts_loopback_and_buckets_per_forwarded_client(trust):
    assert config.TRUSTED_PROXIES == "127.0.0.1,::1"  # the documented default
    client = TestClient(_limited_app(), client=("127.0.0.1", 1))
    assert _statuses(client, 4, **{"X-Forwarded-For": "198.51.100.1"}) == [200, 200, 200, 429]
    # a different real client behind the same proxy has its own bucket
    assert _statuses(client, 1, **{"X-Forwarded-For": "198.51.100.2"}) == [200]


def test_client_cannot_prepend_its_way_out_of_a_bucket_behind_a_trusted_proxy(trust):
    trust("127.0.0.1")
    client = TestClient(_limited_app(), client=("127.0.0.1", 1))
    # The proxy appends the real peer (198.51.100.1); the client varies what it put to the left.
    codes = [client.get("/api/ping", headers={"X-Forwarded-For": f"7.7.7.{i}, 198.51.100.1"}).status_code for i in range(5)]
    assert codes == [200, 200, 200, 429, 429]


def test_empty_setting_trusts_nobody(trust):
    trust("")
    client = TestClient(_limited_app(), client=("127.0.0.1", 1))
    codes = [client.get("/api/ping", headers={"X-Forwarded-For": f"9.9.9.{i}"}).status_code for i in range(5)]
    assert codes == [200, 200, 200, 429, 429]


def test_cidr_setting_is_honoured_and_picked_up_without_rebuilding_the_app(trust):
    app = _limited_app()
    client = TestClient(app, client=("10.1.2.3", 1))
    trust("")  # not trusted yet: header ignored
    assert _statuses(client, 4, **{"X-Forwarded-For": "198.51.100.1"}) == [200, 200, 200, 429]
    trust("10.0.0.0/8")
    assert _statuses(client, 1, **{"X-Forwarded-For": "198.51.100.1"}) == [200]
