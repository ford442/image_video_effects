#!/usr/bin/env python3
"""Offline upload-plan model + formatter shared by deploy.py and deploy_app_only.py.

Used by the ``--dry-run`` flag. Nothing here touches the network, the
credential loader, or any file on disk other than reading the build tree.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Callable, Iterable, Iterator, Optional

REASON_NEW = "new"
REASON_HASH_CHANGED = "hash-changed"
REASON_ALWAYS = "always"


@dataclass
class PlanEntry:
    path: str  # relative to the build directory
    size: int
    reason: str


@dataclass
class DeployPlan:
    script: str
    local_dir: str
    remote_root: str
    manifest_file: str
    manifest_entries: int
    fresh: bool = False
    uploads: list[PlanEntry] = field(default_factory=list)
    unchanged: list[str] = field(default_factory=list)
    skipped_dirs: list[str] = field(default_factory=list)
    deletions: list[str] = field(default_factory=list)
    protected_kept: list[str] = field(default_factory=list)
    # False => this script has no remote-delete step at all.
    deletes_supported: bool = True
    notes: list[str] = field(default_factory=list)

    @property
    def upload_bytes(self) -> int:
        return sum(e.size for e in self.uploads)


def walk_build(local_dir: str, skip_dirs: Iterable[str] = ()) -> Iterator[tuple[str, str]]:
    """Yield ``(relative_path, absolute_path)`` for every file, sorted, like the real walkers.

    ``skip_dirs`` matches directory *names* at any depth, mirroring
    deploy_app_only.upload_directory.
    """
    skip = set(skip_dirs)
    for root, dirs, files in os.walk(local_dir):
        dirs[:] = sorted(d for d in dirs if d not in skip)
        for name in sorted(files):
            full = os.path.join(root, name)
            yield os.path.relpath(full, local_dir), full


def build_plan(
    *,
    script: str,
    local_dir: str,
    remote_root: str,
    manifest_file: str,
    manifest: dict,
    reason_for: Callable[[str, dict], Optional[str]],
    skip_dirs: Iterable[str] = (),
    fresh: bool = False,
) -> DeployPlan:
    """Classify every build file with the script's own ``reason_for`` decision function."""
    plan = DeployPlan(
        script=script,
        local_dir=local_dir,
        remote_root=remote_root,
        manifest_file=manifest_file,
        manifest_entries=len(manifest),
        fresh=fresh,
    )
    effective = {} if fresh else manifest
    for rel, full in walk_build(local_dir, skip_dirs):
        reason = reason_for(full, effective)
        if reason is None:
            plan.unchanged.append(rel)
        else:
            plan.uploads.append(PlanEntry(rel, os.path.getsize(full), reason))
    plan.skipped_dirs = sorted(
        d for d in skip_dirs if os.path.isdir(os.path.join(local_dir, d))
    )
    return plan


def human_size(n: int) -> str:
    size = float(n)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if size < 1024 or unit == "GiB":
            return f"{int(size)} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{n} B"  # pragma: no cover


def format_plan(plan: DeployPlan, *, max_unchanged: int = 0) -> str:
    out: list[str] = []
    add = out.append
    add(f"DRY RUN — {plan.script} (no network connection opened, nothing written)")
    add(f"  Destination root : {plan.remote_root}")
    add(f"  Local build dir  : {plan.local_dir}")
    add(
        f"  Manifest         : {plan.manifest_file} "
        f"({plan.manifest_entries} tracked files; read-only)"
        + ("  [--fresh: treated as empty]" if plan.fresh else "")
    )
    if plan.skipped_dirs:
        add("  Skipped dirs     : " + ", ".join(d + "/" for d in plan.skipped_dirs))
    add("")
    add(f"Files to upload ({len(plan.uploads)}):")
    if plan.uploads:
        width = max(len(e.path) for e in plan.uploads)
        for e in plan.uploads:
            add(f"  {e.path.ljust(width)}  {human_size(e.size):>10}  {e.reason}")
    else:
        add("  (none)")
    add("")
    if plan.deletes_supported:
        add(f"Remote files to delete ({len(plan.deletions)}):")
        if plan.deletions:
            for rel in plan.deletions:
                add(f"  {rel}")
        else:
            add("  (none)")
        for rel in plan.protected_kept:
            add(f"  protected, never removed: {rel}")
    else:
        add("Remote files to delete: n/a (this script never deletes remote files)")
    if max_unchanged:
        add("")
        add(f"Unchanged / skipped ({len(plan.unchanged)}):")
        for rel in plan.unchanged[:max_unchanged]:
            add(f"  {rel}")
        if len(plan.unchanged) > max_unchanged:
            add(f"  … {len(plan.unchanged) - max_unchanged} more")
    add("")
    by_reason: dict[str, int] = {}
    for e in plan.uploads:
        by_reason[e.reason] = by_reason.get(e.reason, 0) + 1
    breakdown = ", ".join(f"{n} {r}" for r, n in sorted(by_reason.items())) or "none"
    add("Totals:")
    add(
        f"  upload  : {len(plan.uploads)} files, {human_size(plan.upload_bytes)} "
        f"({plan.upload_bytes} bytes) — {breakdown}"
    )
    add(f"  skip    : {len(plan.unchanged)} files unchanged")
    add(f"  delete  : {len(plan.deletions)} remote files" if plan.deletes_supported else "  delete  : n/a")
    for note in plan.notes:
        add(f"  note    : {note}")
    return "\n".join(out)
