#!/usr/bin/env python3
"""Unit tests for audit_extrabuffer (no pytest required; pytest-compatible)."""

import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from audit_extrabuffer import (  # noqa: E402
    classify_index,
    parse_consts,
    resolve_expr,
    scan_shader,
    strip_comments,
)


def _write(tmp_path: Path, body: str) -> Path:
    p = tmp_path / "t.wgsl"
    p.write_text(body)
    return p


def test_strip_comments_hides_writes():
    src = "// extraBuffer[0] = 1.0;\n/* extraBuffer[1] = 2.0; */\nvar x = 1.0;\n"
    clean = strip_comments(src)
    assert "extraBuffer" not in clean


def test_parse_consts_and_resolve():
    consts = parse_consts("const CLICK_TIME: i32 = 1;\nconst BASE = 133;\n")
    assert consts == {"CLICK_TIME": 1, "BASE": 133}
    assert resolve_expr("CLICK_TIME", consts) == 1
    assert resolve_expr("BASE + 2u", consts) == 135
    assert resolve_expr("idx * 4u + 3u", consts) is None


def test_classify_index_zones():
    assert classify_index(0) == "reserved"
    assert classify_index(4) == "reserved"
    assert classify_index(5) == "fft-zone"
    assert classify_index(132) == "fft-zone"
    assert classify_index(133) == "safe"
    assert classify_index(255) == "safe"
    assert classify_index(256) == "out-of-range"


def test_scan_flags_reserved_and_fft_writes(tmp_path):
    p = _write(tmp_path, """
const CLICK_TIME: i32 = 1;
fn f() {
    extraBuffer[0] = 1.0;        // reserved
    extraBuffer[CLICK_TIME] = 2.0;  // reserved via const
    extraBuffer[10] = 3.0;       // FFT zone
    extraBuffer[133] = 4.0;      // safe
    extraBuffer[140] += 1.0;     // safe compound
    let bass = extraBuffer[6];   // read: allowed
}
""")
    r = scan_shader(p)
    idxs = sorted(v["index"] for v in r["violations"])
    assert idxs == [0, 1, 10]
    assert r["safe_write_count"] == 2
    assert not r["dynamic"]


def test_scan_dynamic_write_not_violation(tmp_path):
    p = _write(tmp_path, "fn f(idx: u32) { extraBuffer[idx * 4u + 3u] = 1.0; }\n")
    r = scan_shader(p)
    assert not r["violations"]
    assert len(r["dynamic"]) == 1


def test_scan_ignores_comment_write(tmp_path):
    p = _write(tmp_path, "// extraBuffer[0] = 1.0;\nfn f() { extraBuffer[133] = 1.0; }\n")
    r = scan_shader(p)
    assert not r["violations"]
    assert r["safe_write_count"] == 1


if __name__ == "__main__":
    import tempfile

    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            if "tmp_path" in fn.__code__.co_varnames:
                with tempfile.TemporaryDirectory() as d:
                    fn(Path(d))
            else:
                fn()
            print(f"PASS {fn.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e}")
    sys.exit(1 if failed else 0)
