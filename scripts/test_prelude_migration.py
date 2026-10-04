#!/usr/bin/env python3
"""Unit tests for the prelude migration codemod (no pytest required; pytest-compatible)."""

import json
import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

import migrate_to_prelude as mig  # noqa: E402
import prelude_header as ph  # noqa: E402
import wgsl_include  # noqa: E402

FIXTURES = _SCRIPTS / "fixtures" / "prelude_migration"
PRELUDE = ph.PRELUDE_PATH.read_text(encoding="utf-8")
REF = ph.prelude_reference(PRELUDE)


def _read(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def _migrate(src: str):
    cls = ph.classify(src, REF)
    assert cls.status == "migratable", (cls.status, cls.reason, cls.detail)
    return cls, ph.rewrite(src, cls)


def test_fast_strip_comments_matches_the_include_expander():
    samples = [p.read_text(encoding="utf-8") for p in sorted(ph.SHADERS_DIR.glob("*.wgsl"))]
    samples += [
        "a//*b\n/* x /* y */ z */w",
        "/*/ */ q",
        "unterminated /* a\n b",
        "// end",
        "*/ stray",
        "/**/x",
        "a/*b*/c//d\ne",
    ]
    for text in samples:
        assert ph.strip_comments(text) == wgsl_include.strip_comments(text)


def test_fixture_rewrites_match_expected_and_prove_equivalent():
    cases = sorted(FIXTURES.glob("case_*.wgsl"))
    assert len(cases) >= 12
    for path in cases:
        src = path.read_text(encoding="utf-8")
        cls, rw = _migrate(src)
        expected = (FIXTURES / "expected" / path.name).read_text(encoding="utf-8")
        assert rw.text == expected, f"{path.name}: output changed from expected/"
        failures = ph.verify(src, rw.text, cls, rw, PRELUDE) + mig.verify_gates(path, src, rw)
        assert failures == [], f"{path.name}: {failures}"
        assert rw.text.count(ph.INCLUDE_LINE) == 1


def test_rewrite_is_idempotent():
    for path in sorted((FIXTURES / "expected").glob("case_*.wgsl")):
        assert ph.classify(path.read_text(encoding="utf-8"), REF).status == "already-includes", path.name


def test_refusals_carry_specific_reasons():
    expected = {
        "refuse_struct_order.wgsl": "struct-field-order",
        "refuse_renamed.wgsl": "renamed-binding",
        "refuse_extra_field.wgsl": "struct-extra-fields",
        "refuse_access.wgsl": "binding-type",
    }
    for name, reason in expected.items():
        cls = ph.classify(_read(name), REF)
        assert (cls.status, cls.reason) == ("refused", reason), (name, cls.status, cls.reason)
        assert reason in mig.REASONS


def test_skip_and_mixed():
    assert ph.classify(_read("skip_included.wgsl"), REF).status == "already-includes"
    mixed = ph.classify(_read("error_mixed.wgsl"), REF)
    assert mixed.status == "mixed"
    assert "@binding(0)" in mixed.detail
    assert ph.pastes_header(_read("error_mixed.wgsl"))
    assert not ph.pastes_header(_read("skip_included.wgsl"))


def test_banner_and_body_comments_survive():
    _, rw = _migrate(_read("case_canonical.wgsl"))
    assert "//  Upgraded: 2026-09-27" in rw.text
    assert "// keep this comment: it explains the sample" in rw.text
    assert "// ─── helpers ───" in rw.text
    assert "ClickCount" not in rw.text  # stale struct field comment goes with the struct
    assert "// zoom_params: x=Swirl, y=Radius, z=Glow, w=Grain" in rw.text


def test_copy_paste_banner_goes_with_the_header():
    _, rw = _migrate(_read("case_copy_paste_banner.wgsl"))
    assert "COPY PASTE" not in rw.text
    assert "// -----" not in rw.text
    assert "fn early(x: f32)" in rw.text


def test_verify_catches_a_corrupted_rewrite():
    src = _read("case_canonical.wgsl")
    cls, rw = _migrate(src)

    body_changed = rw.text.replace("clamp(x, 0.0, 1.0)", "clamp(x, 0.0, 2.0)")
    assert any(f.startswith("V1") for f in ph.verify(src, body_changed, cls, rw, PRELUDE))

    comment_lost = rw.text.replace("  // keep this comment: it explains the sample\n", "")
    assert any(f.startswith("V2") for f in ph.verify(src, comment_lost, cls, rw, PRELUDE))

    banner_edited = rw.text.replace("Upgraded: 2026-09-27", "Upgraded: 2026-10-04")
    assert any("Upgraded:" in f for f in ph.verify(src, banner_edited, cls, rw, PRELUDE))

    include_dropped = rw.text.replace(ph.INCLUDE_LINE + "\n", "")
    assert any(f.startswith("V3") for f in ph.verify(src, include_dropped, cls, rw, PRELUDE))


def test_verify_gates_catches_a_wrong_line_map():
    path = FIXTURES / "case_extrabuffer.wgsl"
    src = path.read_text(encoding="utf-8")
    cls, rw = _migrate(src)
    assert mig.verify_gates(path, src, rw) == []
    write_line = next(i for i, l in enumerate(src.split("\n"), start=1) if "extraBuffer[SLOT_BASE" in l)
    rw.linemap[write_line] += 1
    assert any("audit_extrabuffer" in f for f in mig.verify_gates(path, src, rw))


def _sandbox(tmp_path: Path):
    """Point the CLI at a throwaway tree (public/shaders, contracts, reports)."""
    shaders = tmp_path / "public" / "shaders"
    shaders.mkdir(parents=True)
    (tmp_path / "src" / "contracts").mkdir(parents=True)
    (tmp_path / "reports").mkdir()
    (tmp_path / "shader_definitions" / "image").mkdir(parents=True)
    saved = {k: getattr(mig, k) for k in ("PROJECT_ROOT", "SHADERS_DIR", "TRACKER_PATH", "BASELINES", "TRIAGE_MD_SCRIPT", "DEFINITIONS_DIR")}
    mig.PROJECT_ROOT = tmp_path
    mig.SHADERS_DIR = shaders
    mig.DEFINITIONS_DIR = tmp_path / "shader_definitions"
    mig.TRACKER_PATH = tmp_path / "src" / "contracts" / "prelude_migration.json"
    mig.BASELINES = [
        (tmp_path / "reports" / "extrabuffer_write_audit_baseline.json", ("triaged_dynamic", "entries")),
        (tmp_path / "reports" / "extrabuffer_dynamic_index_baseline.json", ("entries",)),
    ]
    mig.TRIAGE_MD_SCRIPT = tmp_path / "missing.mjs"
    return shaders, saved


def _restore(saved):
    for k, v in saved.items():
        setattr(mig, k, v)


def test_cli_writes_updates_tracker_and_remaps_baselines(tmp_path):
    shaders, saved = _sandbox(tmp_path)
    try:
        src = _read("case_extrabuffer.wgsl")
        (shaders / "zz-buffer.wgsl").write_text(src, encoding="utf-8")
        (shaders / "zz-other.wgsl").write_text(_read("refuse_renamed.wgsl"), encoding="utf-8")
        old_line = next(i for i, l in enumerate(src.split("\n"), start=1) if "extraBuffer[SLOT_BASE" in l)
        entry = {"file": "public/shaders/zz-buffer.wgsl", "line": old_line, "expr": "SLOT_BASE + gid.x % 4u"}
        mig.BASELINES[0][0].write_text(json.dumps({"triaged_dynamic": {"entries": [dict(entry)]}}, indent=2) + "\n")
        mig.BASELINES[1][0].write_text(json.dumps({"entries": [dict(entry)]}, indent=2) + "\n")

        assert mig.main(["--init-tracker"]) == 0
        tracker = json.loads(mig.TRACKER_PATH.read_text())
        assert tracker["pending"] == {"zz-buffer": "eligible", "zz-other": "renamed-binding"}

        assert mig.main(["--files", str(shaders / "zz-buffer.wgsl")]) == 0
        new = (shaders / "zz-buffer.wgsl").read_text()
        assert ph.INCLUDE_LINE in new
        new_line = next(i for i, l in enumerate(new.split("\n"), start=1) if "extraBuffer[SLOT_BASE" in l)
        assert new_line < old_line
        assert json.loads(mig.TRACKER_PATH.read_text())["pending"] == {"zz-other": "renamed-binding"}
        assert json.loads(mig.BASELINES[0][0].read_text())["triaged_dynamic"]["entries"][0]["line"] == new_line
        assert json.loads(mig.BASELINES[1][0].read_text())["entries"][0]["line"] == new_line

        # Asking for a refused file by name fails, naming the reason; a second run is a no-op.
        assert mig.main(["--files", str(shaders / "zz-other.wgsl")]) == 1
        assert mig.main(["--files", str(shaders / "zz-buffer.wgsl")]) == 0
        assert (shaders / "zz-buffer.wgsl").read_text() == new
    finally:
        _restore(saved)


def test_dry_run_writes_nothing(tmp_path):
    shaders, saved = _sandbox(tmp_path)
    try:
        src = _read("case_canonical.wgsl")
        (shaders / "zz-dry.wgsl").write_text(src, encoding="utf-8")
        assert mig.main(["--files", str(shaders / "zz-dry.wgsl"), "--dry-run"]) == 0
        assert (shaders / "zz-dry.wgsl").read_text() == src
    finally:
        _restore(saved)


def test_category_map_follows_urls_and_graph_entries():
    stems = mig.category_map()
    assert "simulation" in stems.get("gray-scott-step", set())  # graph entry, not the definition id
    assert "image" in stems.get("aerogel-smoke", set())


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
