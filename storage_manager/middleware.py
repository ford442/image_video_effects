# storage_manager/middleware.py
import time
import asyncio
import ipaddress
import logging
from typing import Dict, Iterable, List, Optional, Sequence, Union
from fastapi import Request
from fastapi.responses import PlainTextResponse
from starlette.middleware.base import BaseHTTPMiddleware

from . import config
from .config import RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW, RATE_LIMIT_PATHS, RATE_LIMIT_IP_HEADER


_log = logging.getLogger("storage_manager.middleware")

_IPAddress = Union[ipaddress.IPv4Address, ipaddress.IPv6Address]
_IPNetwork = Union[ipaddress.IPv4Network, ipaddress.IPv6Network]


def parse_trusted_proxies(value: Union[str, Iterable[str], None]) -> List[_IPNetwork]:
    """Parse "ip[,cidr...]" (or an iterable of those) into networks.

    A bad entry is logged and skipped: failing open (trusting more) is the wrong
    default for a security setting, and failing the whole app over a typo is worse
    than trusting nothing extra.
    """
    if not value:
        return []
    items = value.split(",") if isinstance(value, str) else list(value)
    networks: List[_IPNetwork] = []
    for item in items:
        item = str(item).strip()
        if not item:
            continue
        try:
            networks.append(ipaddress.ip_network(item, strict=False))
        except ValueError:
            _log.warning("ignoring invalid TRUSTED_PROXIES entry %r", item)
    return networks


def _parse_ip(raw: str) -> Optional[_IPAddress]:
    try:
        ip = ipaddress.ip_address(raw.strip())
    except ValueError:
        return None
    # ::ffff:1.2.3.4 and 1.2.3.4 are one client (dual-stack listeners report the former).
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
        return ip.ipv4_mapped
    return ip


def _is_trusted(ip: _IPAddress, trusted: Sequence[_IPNetwork]) -> bool:
    return any(ip.version == net.version and ip in net for net in trusted)


def resolve_client_ip(
    peer: Optional[str],
    forwarded_values: Sequence[str],
    trusted: Sequence[_IPNetwork],
) -> str:
    """Pick the address a rate-limit bucket is keyed on.

    `peer` is the TCP peer. `forwarded_values` are the raw values of every
    RATE_LIMIT_IP_HEADER line. The header is honoured only when the peer is a
    trusted proxy. Each proxy appends the address it received the request from, so the
    list grows to the right and only the entries that trusted proxies wrote are
    reliable: walk it from the right, skip trusted hops, and take the first untrusted
    one. Anything left of that was supplied by the client and is never used.
    Unparseable entries are never used as a key (they would let a client mint
    unbounded buckets); the walk stops there and falls back to the peer.
    """
    peer_ip = _parse_ip(peer) if peer else None
    if peer_ip is None:
        return peer or "unknown"
    if not forwarded_values or not _is_trusted(peer_ip, trusted):
        return str(peer_ip)

    hops = [hop for value in forwarded_values for hop in value.split(",") if hop.strip()]
    for raw in reversed(hops):
        hop = _parse_ip(raw)
        if hop is None:
            return str(peer_ip)
        if not _is_trusted(hop, trusted):
            return str(hop)
    # Every hop is a trusted proxy (internal traffic): the left-most is the origin.
    first = _parse_ip(hops[0]) if hops else None
    return str(first if first is not None else peer_ip)


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, requests: int = RATE_LIMIT_REQUESTS, window: int = RATE_LIMIT_WINDOW, path_prefixes=None):
        super().__init__(app)
        self.requests = requests
        self.window = window
        self.path_prefixes = path_prefixes or RATE_LIMIT_PATHS
        self._trusted_raw: Optional[str] = None
        self._trusted: List[_IPNetwork] = []
        self.counters: Dict[str, List[float]] = {}
        self.lock = asyncio.Lock()

    @property
    def trusted_proxies(self) -> List[_IPNetwork]:
        # Re-read config so a change is picked up; parsed once per distinct value.
        raw = config.TRUSTED_PROXIES
        if raw != self._trusted_raw:
            self._trusted, self._trusted_raw = parse_trusted_proxies(raw), raw
        return self._trusted

    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        # Token issuance + webhook writes always get their own, stricter bucket,
        # regardless of how RATE_LIMIT_PATHS is configured.
        is_webhook = any(path.startswith(prefix) for prefix in config.WEBHOOK_PATH_PREFIXES)
        if not is_webhook and not any(path.startswith(prefix) for prefix in self.path_prefixes):
            return await call_next(request)
        limit = config.WEBHOOK_RATE_LIMIT_REQUESTS if is_webhook else self.requests

        client_ip = resolve_client_ip(
            request.client.host if request.client is not None else None,
            request.headers.getlist(RATE_LIMIT_IP_HEADER),
            self.trusted_proxies,
        )

        key = f"{client_ip}:{request.method}:{'webhook' if is_webhook else 'api'}"
        now = time.time()

        async with self.lock:
            entry = self.counters.get(key)
            if entry is None or entry[1] <= now:
                self.counters[key] = [1, now + self.window]
            else:
                entry[0] += 1
            count, reset = self.counters[key]

        if count > limit:
            retry_after = max(1, int(reset - now))
            return PlainTextResponse(
                "Too many requests",
                status_code=429,
                headers={"Retry-After": str(retry_after)},
            )

        response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(limit)
        response.headers["X-RateLimit-Remaining"] = str(max(0, limit - count))
        response.headers["X-RateLimit-Reset"] = str(int(reset))
        return response


class CrossOriginResourcePolicyMiddleware(BaseHTTPMiddleware):
    """Mark responses as embeddable by cross-origin isolated pages (#1314).

    The app sends COEP so it can share memory with its render worker. With
    `credentialless` the browser already loads no-cors images from this host;
    an explicit CORP header also keeps them working for pages that use
    `require-corp`. Never overrides a route that set its own policy.
    """

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("Cross-Origin-Resource-Policy", "cross-origin")
        return response

