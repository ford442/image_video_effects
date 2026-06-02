#!/usr/bin/env python3
"""
Force-upload a specific set of *fixed* WGSL shaders to the Storage Manager.

The regular sync (scripts/sync_shaders_to_storage.py) is idempotent: it skips
any shader that is already present on storage.noahcohn.com. That is exactly
what you want for normal runs, but it means a shader that was edited *after*
it was first uploaded will be skipped (it already "exists"), so the fix never
reaches the server.

This script targets that gap. It re-uploads an explicit list of shader IDs,
bypassing both the manifest hash check and the remote existence check, and then
refreshes those entries in .shader_sync_manifest.json so future normal syncs
stay consistent.

It reuses the upload logic and configuration from sync_shaders_to_storage.py.

Usage:
    # Upload the default batch (scripts/shader_fix_list.txt):
    python scripts/upload_shader_fixes.py

    # Upload specific IDs:
    python scripts/upload_shader_fixes.py byte-mosh fractal-ice-palace

    # Upload IDs listed in a custom file (one id per line, '#' comments ok):
    python scripts/upload_shader_fixes.py --ids-file my_fixes.txt

    # Preview without uploading:
    python scripts/upload_shader_fixes.py --dry-run

    # Don't touch the manifest after uploading:
    python scripts/upload_shader_fixes.py --no-manifest-update
"""

import sys
import time
import argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

# Reuse everything from the canonical sync script (its main() is guarded).
sys.path.insert(0, str(Path(__file__).resolve().parent))
from sync_shaders_to_storage import (  # noqa: E402
    load_shader_definitions,
    load_manifest,
    save_manifest,
    file_hash,
    upload_shader,
    SHADERS_DIR,
    DEFAULT_WORKERS,
    API_BASE_URL,
)

DEFAULT_LIST_FILE = Path(__file__).resolve().parent / "shader_fix_list.txt"


def read_id_list(path: Path) -> list:
    """Read shader IDs from a file, ignoring blanks and '#' comments."""
    ids = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            ids.append(line)
    # de-dupe, preserve order
    return list(dict.fromkeys(ids))


def main():
    parser = argparse.ArgumentParser(
        description="Force-re-upload specific fixed shaders to the Storage Manager."
    )
    parser.add_argument(
        "ids",
        nargs="*",
        help="Shader IDs to upload. If omitted, --ids-file (or the default "
        "shader_fix_list.txt) is used.",
    )
    parser.add_argument(
        "--ids-file",
        type=Path,
        default=None,
        help=f"File of shader IDs, one per line (default: {DEFAULT_LIST_FILE.name}).",
    )
    parser.add_argument(
        "--workers", type=int, default=DEFAULT_WORKERS, help="Concurrent uploads."
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Preview the upload set; do not upload."
    )
    parser.add_argument(
        "--no-manifest-update",
        action="store_true",
        help="Do not refresh .shader_sync_manifest.json after uploading.",
    )
    args = parser.parse_args()

    # 1. Resolve the target ID list
    if args.ids:
        target_ids = list(dict.fromkeys(args.ids))
        source = "command line"
    else:
        list_file = args.ids_file or DEFAULT_LIST_FILE
        if not list_file.exists():
            print(f"❌ ID list file not found: {list_file}")
            sys.exit(1)
        target_ids = read_id_list(list_file)
        source = str(list_file)

    if not target_ids:
        print("❌ No shader IDs to upload.")
        sys.exit(1)

    # 2. Load metadata; build the upload set (force = no skip checks)
    definitions = load_shader_definitions()
    manifest = load_manifest()

    to_upload = []
    missing_local = []
    for shader_id in target_ids:
        wgsl_path = SHADERS_DIR / f"{shader_id}.wgsl"
        if not wgsl_path.exists():
            missing_local.append(shader_id)
            continue
        meta = definitions.get(shader_id)
        if meta is None:
            # Fall back to a minimal definition derived from the id.
            meta = {
                "id": shader_id,
                "name": shader_id.replace("-", " ").replace("_", " ").title(),
            }
        to_upload.append((shader_id, meta, wgsl_path))

    print("=" * 60)
    print("Force-upload fixed shaders")
    print(f"API:          {API_BASE_URL}")
    print(f"Source:       {source}")
    print(f"Requested:    {len(target_ids)}")
    print(f"To upload:    {len(to_upload)}")
    print(f"Missing WGSL: {len(missing_local)}")
    print(f"Workers:      {args.workers}")
    print(f"Dry run:      {'Yes' if args.dry_run else 'No'}")
    print("=" * 60)

    if missing_local:
        print("⚠️  No local WGSL file for: " + ", ".join(missing_local))
        print()

    if not to_upload:
        print("Nothing to upload.")
        return

    if args.dry_run:
        for shader_id, _, _ in to_upload:
            print(f"   would upload: {shader_id}")
        print(f"\n(dry run) {len(to_upload)} shader(s) would be force-uploaded.")
        return

    # 3. Upload concurrently (force: every listed shader is uploaded)
    success_count = 0
    fail_count = 0
    failed = []

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(upload_shader, sid, meta, path, False): sid
            for sid, meta, path in to_upload
        }
        for fut in as_completed(futures):
            shader_id, ok, err = fut.result()
            if ok:
                success_count += 1
                print(f"✅  {shader_id}")
                if not args.no_manifest_update:
                    path = SHADERS_DIR / f"{shader_id}.wgsl"
                    manifest[shader_id] = {
                        "hash": file_hash(path),
                        "synced_at": time.time(),
                    }
            else:
                fail_count += 1
                failed.append((shader_id, err))
                print(f"❌  {shader_id}: {err}")

    if not args.no_manifest_update:
        save_manifest(manifest)

    print("=" * 60)
    print(f"Uploaded: {success_count} ✅   Failed: {fail_count} ❌")
    if failed:
        print("\nFailed uploads:")
        for sid, err in failed:
            print(f"   - {sid}: {err}")
        sys.exit(1)
    print("\n🎉  All fixed shaders re-uploaded successfully!")


if __name__ == "__main__":
    main()
