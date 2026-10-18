#!/usr/bin/env python3
"""
migrate_to_prelude.py — replace a pasted binding header with `#include "_prelude.wgsl"`.

The 13 `@group(0) @binding(0..12)` declarations and `struct Uniforms` are
removed and one include goes where the first of them was. Nothing else in the
file changes: binding 13, @group(1), helpers and banners stay byte-for-byte, and
`Upgraded:` dates are not touched (this is infrastructure, not an upgrade).

Every rewrite is proven before it is written. A file that fails any check is
left untouched and the run exits 1:
  V1  code tokens outside the header are identical
  V2  every comment survives except the header's own (struct field comments,
      labels like "COPY PASTE THIS HEADER"); banner lines are byte-identical
  V3  the expanded module declares exactly what the original declared
  V4  bindgroup_checker's verdict and audit_extrabuffer's findings are unchanged
      (extraBuffer lines compared through the rewrite's line map)
  V5  (--naga) naga-wasm's verdict and first error line are unchanged

When it writes, it also drops migrated ids from src/contracts/prelude_migration.json
`pending` and remaps their line numbers in the extraBuffer triage baselines.

Usage:
  python3 scripts/migrate_to_prelude.py --files public/shaders/foo.wgsl   # the fix CI prints
  python3 scripts/migrate_to_prelude.py --ids foo bar
  python3 scripts/migrate_to_prelude.py --category geometric --category image [--orphans]
  python3 scripts/migrate_to_prelude.py --all --dry-run
  python3 scripts/migrate_to_prelude.py --init-tracker
Options: --dry-run, --report PATH, --naga, --verbose
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import prelude_header as ph  # noqa: E402
from audit_extrabuffer import scan_shader  # noqa: E402
from bindgroup_checker import parse_shader_source  # noqa: E402
from wgsl_include import expand_wgsl_includes  # noqa: E402

PROJECT_ROOT = ph.PROJECT_ROOT
SHADERS_DIR = ph.SHADERS_DIR
DEFINITIONS_DIR = PROJECT_ROOT / "shader_definitions"
TRACKER_PATH = PROJECT_ROOT / "src" / "contracts" / "prelude_migration.json"
BASELINES = [
    (PROJECT_ROOT / "reports" / "extrabuffer_write_audit_baseline.json", ("triaged_dynamic", "entries")),
    (PROJECT_ROOT / "reports" / "extrabuffer_dynamic_index_baseline.json", ("entries",)),
]
TRIAGE_MD_SCRIPT = PROJECT_ROOT / "scripts" / "generate-extrabuffer-triage-md.mjs"
NAGA_HELPER = PROJECT_ROOT / "scripts" / "lib" / "naga_validate_stdin.mjs"

FIX_COMMAND = "python3 scripts/migrate_to_prelude.py --files {path}"

REASONS = {
    "eligible": "Canonical header; migrates mechanically. Waiting for its category wave, or run the fix command.",
    "struct-field-order": (
        "struct Uniforms lists its fields in a different order (config, zoom_params, zoom_config, ...). "
        "That is a different memory layout: u.zoom_params actually reads the engine's zoom_config. "
        "Fixing it changes rendering, so it needs its own reviewed change, not this codemod."
    ),
    "struct-extra-fields": (
        "struct Uniforms declares fields the engine does not write, which shifts `ripples` and reads "
        "data laid out for other fields. Fixing it changes rendering."
    ),
    "struct-mismatch": "struct Uniforms differs from the contract (src/contracts/uniforms_layout.json).",
    "renamed-binding": (
        "A canonical binding is declared under a different name. Migrating means renaming its uses "
        "in the body to the canonical name first."
    ),
    "binding-type": "A canonical binding is declared with a different type or access mode.",
    "missing-decl": "Part of the canonical header is missing.",
    "duplicate-decl": "A canonical declaration appears more than once.",
    "scan-error": "The file could not be split into top-level declarations (unbalanced brackets?).",
}

V4_KEYS = [
    "status",
    "shader_type",
    "missing_bindings",
    "wrong_type_bindings",
    "has_binding_13_plus",
    "texture_store_targets",
    "uniforms_struct",
    "workgroup_sizes",
    "workgroup_size_valid",
    "reserved_extrabuffer_writes",
    "errors",
    "warnings",
]


# ── selection ───────────────────────────────────────────────────────────────


def category_map() -> dict[str, set[str]]:
    """WGSL file stem → categories, from shader_definitions/<category>/*.json."""
    stems: dict[str, set[str]] = {}
    for json_path in sorted(DEFINITIONS_DIR.glob("*/*.json")):
        category = json_path.parent.name
        try:
            data = json.loads(json_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict):
            continue
        refs = set()
        for key in ("id", "url", "nextShader", "prevShader"):
            if isinstance(data.get(key), str):
                refs.add(Path(data[key]).stem)
        multipass = data.get("multipass") if isinstance(data.get("multipass"), dict) else {}
        for key in ("nextShader", "prevShader"):
            if isinstance(multipass.get(key), str):
                refs.add(Path(multipass[key]).stem)
        for p in multipass.get("passes") or []:
            if isinstance(p, dict):
                for key in ("file", "url", "id", "shader"):
                    if isinstance(p.get(key), str):
                        refs.add(Path(p[key]).stem)
        graph = multipass.get("graph") if isinstance(multipass.get("graph"), dict) else {}
        for node in graph.get("nodes") or []:
            if isinstance(node, dict) and isinstance(node.get("entry"), str):
                refs.add(node["entry"])
        for stem in refs:
            stems.setdefault(stem, set()).add(category)
    return stems


def catalog_files() -> list[Path]:
    return sorted(p for p in SHADERS_DIR.glob("*.wgsl") if not p.name.startswith("_"))


def resolve_file(arg: str) -> Path:
    p = Path(arg)
    if not p.is_absolute():
        p = (Path.cwd() / p) if (Path.cwd() / p).exists() else (PROJECT_ROOT / p)
    p = p.resolve()
    if p.parent != SHADERS_DIR.resolve() or p.suffix != ".wgsl":
        raise SystemExit(f"❌ {arg}: not a .wgsl file directly under public/shaders/")
    if not p.exists():
        raise SystemExit(f"❌ {arg}: no such file")
    return p


def select(args) -> list[Path]:
    chosen: list[Path] = []
    if args.all:
        chosen.extend(catalog_files())
    if args.files:
        chosen.extend(resolve_file(f) for f in args.files)
    if args.ids:
        chosen.extend(resolve_file(str(SHADERS_DIR / f"{i}.wgsl")) for i in args.ids)
    if args.category or args.orphans:
        stems = category_map()
        wanted = set(args.category or [])
        known = {c for cats in stems.values() for c in cats}
        unknown = wanted - known
        if unknown:
            raise SystemExit(f"❌ unknown category: {', '.join(sorted(unknown))} (known: {', '.join(sorted(known))})")
        for p in catalog_files():
            cats = stems.get(p.stem, set())
            if cats & wanted or (args.orphans and not cats):
                chosen.append(p)
    seen, out = set(), []
    for p in chosen:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return sorted(out)


# ── checks ──────────────────────────────────────────────────────────────────


def _strip_locations(value):
    if isinstance(value, dict):
        return {k: _strip_locations(v) for k, v in value.items() if not k.startswith("line")}
    if isinstance(value, list):
        return [_strip_locations(v) for v in value]
    if isinstance(value, str):
        return re.sub(r"\b(line|L)\s*\d+|:\d+(:\d+)?\b", "<loc>", value)
    return value


def verify_gates(path: Path, old: str, rw: ph.Rewrite) -> list[str]:
    """V4: the gates that read raw or expanded text reach the same verdict."""
    failures = []
    before = parse_shader_source(old, str(path))
    after = parse_shader_source(rw.text, str(path))
    for key in V4_KEYS:
        if _strip_locations(before.get(key)) != _strip_locations(after.get(key)):
            failures.append(f"V4 bindgroup_checker `{key}` changed: {before.get(key)!r} -> {after.get(key)!r}")

    a, b = scan_shader(path, old), scan_shader(path, rw.text)
    for kind in ("violations", "dynamic", "out_of_range"):
        mapped = []
        for e in a[kind]:
            new_line = rw.linemap.get(e["line"])
            if new_line is None:
                failures.append(f"V4 extraBuffer write at line {e['line']} has no line after the rewrite")
                continue
            mapped.append((e["expr"], e["op"], e.get("index"), new_line))
        actual = [(e["expr"], e["op"], e.get("index"), e["line"]) for e in b[kind]]
        if sorted(mapped, key=repr) != sorted(actual, key=repr):
            failures.append(f"V4 audit_extrabuffer `{kind}` findings changed")
    if a["safe_write_count"] != b["safe_write_count"]:
        failures.append("V4 audit_extrabuffer safe write count changed")
    return failures


def run_naga(pairs: dict[str, tuple[str, str]]) -> dict[str, list[str]]:
    """V5: naga verdict before vs after, per id. Returns failures keyed by id."""
    if not shutil.which("node"):
        raise SystemExit("❌ --naga needs node on PATH")
    payload = []
    for sid, (old, new_expanded) in pairs.items():
        payload.append({"key": f"{sid}\0old", "source": old})
        payload.append({"key": f"{sid}\0new", "source": new_expanded})
    proc = subprocess.run(
        ["node", str(NAGA_HELPER)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        cwd=PROJECT_ROOT,
        check=True,
    )
    verdicts = json.loads(proc.stdout)
    out: dict[str, list[str]] = {}
    for sid in pairs:
        before, after = verdicts[f"{sid}\0old"], verdicts[f"{sid}\0new"]
        if before != after:
            out[sid] = [f"V5 naga verdict changed: {before} -> {after}"]
    return out


# ── side files ──────────────────────────────────────────────────────────────


def load_tracker() -> dict | None:
    if not TRACKER_PATH.exists():
        return None
    return json.loads(TRACKER_PATH.read_text(encoding="utf-8"))


def save_tracker(data: dict) -> None:
    data["pending"] = dict(sorted(data["pending"].items()))
    TRACKER_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def remap_baselines(linemaps: dict[str, dict[int, int | None]]) -> list[Path]:
    """Rewrite triaged extraBuffer line numbers for migrated files. Returns files changed."""
    changed = []
    for path, section in BASELINES:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        data = json.loads(text)
        block = data
        for key in section:
            block = block.get(key) if isinstance(block, dict) else None
        if not isinstance(block, list):
            continue
        dirty = False
        for entry in block:
            linemap = linemaps.get(entry.get("file"))
            if linemap is None or entry.get("line") is None:
                continue
            new_line = linemap.get(int(entry["line"]))
            if new_line is None:
                raise SystemExit(f"❌ {path.name}: {entry['file']}:{entry['line']} has no line after the rewrite")
            if new_line != entry["line"]:
                entry["line"] = new_line
                dirty = True
        if dirty:
            path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
            changed.append(path)
    return changed


def init_tracker(ref: dict, prelude_text: str) -> int:
    existing = load_tracker() or {}
    pending: dict[str, str] = {}
    mixed = []
    for path in catalog_files():
        cls = ph.classify(path.read_text(encoding="utf-8"), ref)
        if cls.status == "migratable":
            pending[path.stem] = "eligible"
        elif cls.status == "refused":
            pending[path.stem] = cls.reason
        elif cls.status == "mixed":
            mixed.append(f"{path.name}: {cls.detail}")
    if mixed:
        print("❌ files both include the prelude and paste declarations:\n  " + "\n  ".join(mixed), file=sys.stderr)
        return 1
    data = {
        "version": 1,
        "description": existing.get(
            "description",
            "Catalog shaders that still paste the binding header instead of `#include \"_prelude.wgsl\"`. "
            "Two-way ratchet enforced by scripts/check_prelude_migration.py: a shader not listed here must not "
            "paste the header, a listed one must still paste it, and the list may only shrink. "
            "scripts/migrate_to_prelude.py removes ids as it migrates them. #1313 Track A.",
        ),
        "library": ph.PRELUDE_NAME,
        "fixCommand": FIX_COMMAND,
        "reasons": REASONS,
        "promptSources": existing.get("promptSources", []),
        "pending": pending,
    }
    save_tracker(data)
    counts = Counter(pending.values())
    print(f"Wrote {TRACKER_PATH.relative_to(PROJECT_ROOT)}: {len(pending)} pending " + str(dict(counts)))
    return 0


# ── main ────────────────────────────────────────────────────────────────────


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--files", nargs="+", help="shader files under public/shaders/")
    parser.add_argument("--ids", nargs="+", help="shader ids (public/shaders/<id>.wgsl)")
    parser.add_argument("--category", action="append", help="every file a shader_definitions/<category> entry references")
    parser.add_argument("--orphans", action="store_true", help="catalog files no definition references")
    parser.add_argument("--all", action="store_true", help="every non-_ file in public/shaders")
    parser.add_argument("--dry-run", action="store_true", help="prove the rewrites, write nothing")
    parser.add_argument("--report", help="write a JSON report (line maps, removed comments)")
    parser.add_argument("--naga", action="store_true", help="also compare naga-wasm verdicts (V5)")
    parser.add_argument("--init-tracker", action="store_true", help="(re)generate src/contracts/prelude_migration.json")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    prelude_text = ph.PRELUDE_PATH.read_text(encoding="utf-8")
    ref = ph.prelude_reference(prelude_text)

    if args.init_tracker:
        return init_tracker(ref, prelude_text)

    explicit = bool(args.files or args.ids)
    files = select(args)
    if not files:
        parser.error("nothing selected — pass --files, --ids, --category, --orphans or --all")

    results = []
    rewrites: dict[Path, ph.Rewrite] = {}
    for path in files:
        rel = str(path.relative_to(PROJECT_ROOT))
        entry = {"id": path.stem, "file": rel}
        if path.name.startswith("_") and not explicit:
            entry.update(status="skipped", reason="library")
            results.append(entry)
            continue
        old = path.read_text(encoding="utf-8")
        cls = ph.classify(old, ref)
        if cls.status == "already-includes":
            entry.update(status="skipped", reason="already-includes")
        elif cls.status == "no-header":
            entry.update(status="skipped", reason="no-header")
        elif cls.status == "mixed":
            entry.update(status="error", reason="mixed", detail=cls.detail)
        elif cls.status == "refused":
            entry.update(status="refused", reason=cls.reason, detail=cls.detail)
        else:
            rw = ph.rewrite(old, cls)
            failures = ph.verify(old, rw.text, cls, rw, prelude_text) + verify_gates(path, old, rw)
            if failures:
                entry.update(status="error", reason="verification", failures=failures)
            else:
                entry.update(
                    status="ok",
                    includeLine=rw.include_line,
                    relocatedComment=rw.relocated_comment,
                    removedComments=rw.removed_comments,
                    linemap={str(k): v for k, v in rw.linemap.items()},
                )
                rewrites[path] = rw
        results.append(entry)

    if args.naga and rewrites:
        pairs = {}
        for path, rw in rewrites.items():
            expanded = expand_wgsl_includes(rw.text, lambda n: prelude_text if n == ph.PRELUDE_NAME else None, path.name)
            pairs[path.stem] = (path.read_text(encoding="utf-8"), expanded)
        naga_failures = run_naga(pairs)
        for entry in results:
            if entry["id"] in naga_failures and entry["status"] == "ok":
                entry.update(status="error", reason="verification", failures=naga_failures[entry["id"]])
                rewrites.pop(SHADERS_DIR / f"{entry['id']}.wgsl", None)

    if not args.dry_run and rewrites:
        for path, rw in rewrites.items():
            path.write_text(rw.text, encoding="utf-8")
        tracker = load_tracker()
        if tracker is not None:
            for path in rewrites:
                tracker["pending"].pop(path.stem, None)
            save_tracker(tracker)
        linemaps = {str(p.relative_to(PROJECT_ROOT)): rw.linemap for p, rw in rewrites.items()}
        changed = remap_baselines(linemaps)
        if changed and shutil.which("node") and TRIAGE_MD_SCRIPT.exists():
            subprocess.run(["node", str(TRIAGE_MD_SCRIPT)], cwd=PROJECT_ROOT, check=True, capture_output=True)
        for p in changed:
            print(f"   remapped extraBuffer triage lines in {p.relative_to(PROJECT_ROOT)}")

    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        summary = Counter(r["status"] for r in results)
        report_path.write_text(
            json.dumps({"dryRun": args.dry_run, "summary": dict(summary), "files": results}, indent=2) + "\n",
            encoding="utf-8",
        )

    summary = Counter(r["status"] for r in results)
    reasons = Counter(r["reason"] for r in results if r["status"] == "refused")
    verb = "would migrate" if args.dry_run else "migrated"
    print(
        f"prelude migration: {verb} {summary['ok']}, refused {summary['refused']}"
        + (f" ({', '.join(f'{k} {v}' for k, v in sorted(reasons.items()))})" if reasons else "")
        + f", skipped {summary['skipped']}, errors {summary['error']}"
    )
    failed = False
    for r in results:
        if r["status"] == "error":
            failed = True
            print(f"❌ {r['file']}: {r.get('detail') or '; '.join(r.get('failures', []))}", file=sys.stderr)
        elif r["status"] == "refused" and (explicit or args.verbose):
            if explicit:
                failed = True
            print(
                f"{'❌' if explicit else '⚠️ '} {r['file']}: not migrated ({r['reason']}): {r['detail']}\n"
                f"   {REASONS.get(r['reason'], '')}",
                file=sys.stderr,
            )
        elif args.verbose and r["status"] == "ok":
            print(f"✅ {r['file']} (include at line {r['includeLine']})")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
