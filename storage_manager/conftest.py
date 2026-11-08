"""Let `cd storage_manager && python -m pytest` resolve `import storage_manager.*`.

The suites import the package by name, which only works with the repo root on
sys.path (running pytest from the root does that; running it from here did not).
"""
import sys
from pathlib import Path

_ROOT = str(Path(__file__).resolve().parent.parent)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)


# --- real Redis for the Redis-backed tests -----------------------------------
import os
import shutil
import socket
import subprocess
import time

import pytest


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture()
def redis_server():
    """Start a throwaway `redis-server` on a free port and yield the port.

    Skips when the binary is missing, unless STORAGE_REQUIRE_REDIS=1 (set in CI),
    where a missing binary must fail instead of silently dropping coverage.
    """
    binary = shutil.which("redis-server")
    if not binary:
        if os.environ.get("STORAGE_REQUIRE_REDIS") == "1":
            pytest.fail("STORAGE_REQUIRE_REDIS=1 but redis-server is not installed")
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
