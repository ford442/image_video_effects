#!/usr/bin/env python3
"""
Sync local WGSL shaders to the Contabo VPS Storage Manager.

This script scans shader_definitions/ for metadata, checks which shaders are
missing from storage.noahcohn.com, and uploads them via the REST API.

Features:
- Idempotent: skips shaders already present (unless --force)
- Resumable: saves progress to .shader_sync_manifest.json
- Concurrent: uploads up to N shaders in parallel
- Retry: exponential backoff on transient failures
- Preserves IDs: uploads use the original kebab-case shader ID

Usage:
    python scripts/sync_shaders_to_storage.py
    python scripts/sync_shaders_to_storage.py --force          # re-upload all
    python scripts/sync_shaders_to_storage.py --dry-run        # preview only
    python scripts/sync_shaders_to_storage.py --workers 10     # increase concurrency
"""

import os
import sys
import json
import time
import hashlib
import argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Optional, Tuple

import requests

# ── Configuration ────────────────────────────────────────────────────────────

API_BASE_URL = os.environ.get("STORAGE_API_URL", "https://storage.noahcohn.com")
UPLOAD_ENDPOINT = f"{API_BASE_URL}/api/shaders/upload"
CHECK_ENDPOINT = f"{API_BASE_URL}/api/shaders"  # GET /api/shaders/{id}

SHADER_DEFINITIONS_DIR = Path("shader_definitions")
SHADERS_DIR = Path("public/shaders")
MANIFEST_FILE = Path(".shader_sync_manifest.json")

DEFAULT_WORKERS = 5
DEFAULT_BATCH_SIZE = 50
RETRY_ATTEMPTS = 3
RETRY_BACKOFF = 2.0  # seconds
UPLOAD_TIMEOUT = 60  # seconds

# ── Helpers ──────────────────────────────────────────────────────────────────


def load_shader_definitions() -> Dict[str, dict]:
    """Scan shader_definitions/*/*.json and return a dict keyed by shader id."""
    shaders = {}
    if not SHADER_DEFINITIONS_DIR.exists():
        print(f"❌ Shader definitions directory not found: {SHADER_DEFINITIONS_DIR}")
        sys.exit(1)

    for json_file in SHADER_DEFINITIONS_DIR.rglob("*.json"):
        try:
            with open(json_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            shader_id = data.get("id")
            if not shader_id:
                continue
            shaders[shader_id] = data
        except (json.JSONDecodeError, OSError) as e:
            print(f"⚠️  Skipping {json_file}: {e}")

    return shaders


def load_manifest() -> dict:
    """Load the local sync manifest for resume support."""
    if MANIFEST_FILE.exists():
        try:
            with open(MANIFEST_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def save_manifest(manifest: dict):
    """Save the sync manifest atomically."""
    tmp = MANIFEST_FILE.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    tmp.replace(MANIFEST_FILE)


def file_hash(path: Path) -> str:
    """Return MD5 hash of file contents."""
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def check_shader_exists(shader_id: str) -> bool:
    """Query the storage manager to see if a shader already exists."""
    try:
        resp = requests.get(
            f"{CHECK_ENDPOINT}/{shader_id}",
            timeout=10,
            headers={"Accept": "application/json"},
        )
        return resp.status_code == 200
    except requests.RequestException:
        return False


def upload_shader(
    shader_id: str,
    meta: dict,
    wgsl_path: Path,
    dry_run: bool = False,
) -> Tuple[str, bool, Optional[str]]:
    """Upload a single shader to the storage manager.

    Returns (shader_id, success, error_message).
    """
    if dry_run:
        return shader_id, True, None

    tags = meta.get("tags", []) or []
    features = meta.get("features", []) or []
    all_tags = list(dict.fromkeys(tags + features))  # dedupe, preserve order

    name = meta.get("name", shader_id.replace("-", " ").replace("_", " ").title())
    description = meta.get("description", "")
    category = meta.get("category", "")
    if category and category not in all_tags:
        all_tags.insert(0, category)

    form_data = {
        "name": name,
        "description": description,
        "tags": ",".join(all_tags),
        "author": "ford442",
        "shader_id": shader_id,
    }

    for attempt in range(1, RETRY_ATTEMPTS + 1):
        try:
            with open(wgsl_path, "rb") as f:
                files = {"file": (f"{shader_id}.wgsl", f, "text/plain")}
                resp = requests.post(
                    UPLOAD_ENDPOINT,
                    data=form_data,
                    files=files,
                    timeout=UPLOAD_TIMEOUT,
                )

            if resp.status_code in (200, 201):
                return shader_id, True, None
            else:
                err = f"HTTP {resp.status_code}: {resp.text[:200]}"
                if attempt == RETRY_ATTEMPTS:
                    return shader_id, False, err
                time.sleep(RETRY_BACKOFF * attempt)

        except requests.RequestException as e:
            if attempt == RETRY_ATTEMPTS:
                return shader_id, False, str(e)
            time.sleep(RETRY_BACKOFF * attempt)

    return shader_id, False, "Max retries exceeded"


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    global API_BASE_URL, UPLOAD_ENDPOINT, CHECK_ENDPOINT

    parser = argparse.ArgumentParser(
        description="Sync local WGSL shaders to the VPS Storage Manager"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-upload shaders even if they already exist on the server",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would be uploaded without making any requests",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=DEFAULT_WORKERS,
        help=f"Number of concurrent upload workers (default: {DEFAULT_WORKERS})",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=DEFAULT_BATCH_SIZE,
        help=f"Save manifest every N uploads (default: {DEFAULT_BATCH_SIZE})",
    )
    parser.add_argument(
        "--api-url",
        default=API_BASE_URL,
        help=f"Storage manager base URL (default: {API_BASE_URL})",
    )
    args = parser.parse_args()

    API_BASE_URL = args.api_url.rstrip("/")
    UPLOAD_ENDPOINT = f"{API_BASE_URL}/api/shaders/upload"
    CHECK_ENDPOINT = f"{API_BASE_URL}/api/shaders"

    print("=" * 60)
    print("🚀  Shader Sync to Storage Manager")
    print("=" * 60)
    print(f"API URL:     {API_BASE_URL}")
    print(f"Workers:     {args.workers}")
    print(f"Batch size:  {args.batch_size}")
    print(f"Dry run:     {'Yes' if args.dry_run else 'No'}")
    print(f"Force:       {'Yes' if args.force else 'No'}")
    print("=" * 60)
    print()

    # 1. Load local shader definitions
    shaders = load_shader_definitions()
    print(f"📁  Found {len(shaders)} shader definitions")

    # 2. Load manifest
    manifest = load_manifest()
    print(f"📋  Loaded manifest with {len(manifest)} tracked shaders")

    # 3. Determine what needs uploading
    to_upload: List[Tuple[str, dict, Path]] = []
    skipped = 0
    missing_local = 0

    for shader_id, meta in shaders.items():
        wgsl_path = SHADERS_DIR / f"{shader_id}.wgsl"
        if not wgsl_path.exists():
            missing_local += 1
            continue

        local_hash = file_hash(wgsl_path)

        # Check manifest first (fast local check)
        if not args.force and shader_id in manifest:
            if manifest[shader_id].get("hash") == local_hash:
                skipped += 1
                continue

        # Check remote (if not forcing and not in manifest, and not dry-run)
        if not args.dry_run and not args.force and shader_id not in manifest:
            if check_shader_exists(shader_id):
                manifest[shader_id] = {"hash": local_hash, "synced_at": time.time()}
                skipped += 1
                continue

        to_upload.append((shader_id, meta, wgsl_path))

    print(f"⏭️   Skipped (already synced): {skipped}")
    print(f"📤  To upload: {len(to_upload)}")
    if missing_local:
        print(f"⚠️   Missing local WGSL files: {missing_local}")
    print()

    if not to_upload:
        print("✅  All shaders are already synced!")
        save_manifest(manifest)
        return

    if args.dry_run:
        print("🔍  Dry run — would upload the following shaders:")
        for shader_id, meta, _ in to_upload[:20]:
            print(f"   - {shader_id}")
        if len(to_upload) > 20:
            print(f"   ... and {len(to_upload) - 20} more")
        return

    # 4. Upload with concurrency
    success_count = 0
    fail_count = 0
    failed_shaders = []

    print("📤  Starting uploads...\n")

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(upload_shader, sid, meta, path, args.dry_run): (sid, meta, path)
            for sid, meta, path in to_upload
        }

        for i, future in enumerate(as_completed(futures), 1):
            sid, meta, path = futures[future]
            _, ok, err = future.result()

            if ok:
                success_count += 1
                manifest[sid] = {
                    "hash": file_hash(path),
                    "synced_at": time.time(),
                }
                print(f"  ✅ [{i}/{len(to_upload)}] {sid}")
            else:
                fail_count += 1
                failed_shaders.append((sid, err))
                print(f"  ❌ [{i}/{len(to_upload)}] {sid} — {err}")

            # Save manifest every batch
            if i % args.batch_size == 0:
                save_manifest(manifest)
                print(f"     💾 Manifest saved ({i} processed)")

    # Final manifest save
    save_manifest(manifest)

    # Summary
    print()
    print("=" * 60)
    print("📊  Sync Complete")
    print("=" * 60)
    print(f"Total definitions: {len(shaders)}")
    print(f"Already synced:    {skipped}")
    print(f"Uploaded:          {success_count} ✅")
    print(f"Failed:            {fail_count} ❌")
    print(f"Missing local:     {missing_local}")
    print("=" * 60)

    if failed_shaders:
        print("\n⚠️  Failed uploads (first 20):")
        for sid, err in failed_shaders[:20]:
            print(f"   - {sid}: {err}")

    if fail_count == 0:
        print("\n🎉  All shaders synced successfully!")
    else:
        print(f"\n⚠️  {fail_count} shader(s) failed. Re-run to retry.")
        sys.exit(1)


if __name__ == "__main__":
    main()
