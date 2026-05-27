#!/usr/bin/env python3
"""
Sync local WGSL shaders to the static file server at storage.1ink.us.

This script uploads the public/shaders/ directory (or selected .wgsl files)
to the remote server via SFTP so they can be served by Nginx at:
    https://test.1ink.us/image_video_effects/shaders/

Features:
- Incremental sync: skips files that already exist with the same size
- Dry-run support
- Progress reporting

Usage:
    python scripts/sync_shaders_to_1ink.py
    python scripts/sync_shaders_to_1ink.py --dry-run
    python scripts/sync_shaders_to_1ink.py --host storage.1ink.us --remote-path files/image-effects/shaders
"""

import os
import sys
import argparse
from pathlib import Path

try:
    import paramiko
except ImportError:
    print("❌ paramiko is required. Install it with: pip install paramiko")
    sys.exit(1)

# --- Configuration ---
DEFAULT_HOST = os.environ.get("SHADER_SYNC_HOST", "1ink.us")
DEFAULT_PORT = int(os.environ.get("SHADER_SYNC_PORT", "22"))
DEFAULT_USER = os.environ.get("SHADER_SYNC_USER", "ford442")
DEFAULT_REMOTE_PATH = os.environ.get("SHADER_SYNC_REMOTE_PATH", "test.1ink.us/image_video_effects/shaders")
LOCAL_SHADERS_DIR = Path("public/shaders")


def upload_file(sftp, local_path: Path, remote_path: str, dry_run: bool = False) -> bool:
    """Upload a single file if it doesn't exist or has a different size."""
    try:
        remote_stat = sftp.stat(remote_path)
        local_size = local_path.stat().st_size
        if remote_stat.st_size == local_size:
            return True  # Already up to date
    except FileNotFoundError:
        pass  # File doesn't exist remotely, proceed with upload
    except Exception as e:
        print(f"   ⚠️  Could not stat remote {remote_path}: {e}")

    if dry_run:
        print(f"   [DRY-RUN] Would upload: {local_path} -> {remote_path}")
        return True

    try:
        # Ensure parent directory exists (recursive mkdir)
        remote_dir = "/".join(remote_path.split("/")[:-1])
        parts = remote_dir.split("/")
        for i in range(1, len(parts) + 1):
            part_path = "/".join(parts[:i])
            if not part_path:
                continue
            try:
                sftp.mkdir(part_path)
            except IOError:
                pass  # Directory may already exist

        sftp.put(str(local_path), remote_path)
        return True
    except Exception as e:
        print(f"   ❌ Failed to upload {local_path.name}: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Sync local WGSL shaders to storage.1ink.us via SFTP"
    )
    parser.add_argument(
        "--host",
        default=DEFAULT_HOST,
        help=f"SFTP host (default: {DEFAULT_HOST})",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help=f"SFTP port (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--user",
        default=DEFAULT_USER,
        help=f"SFTP username (default: {DEFAULT_USER})",
    )
    parser.add_argument(
        "--remote-path",
        default=DEFAULT_REMOTE_PATH,
        help=f"Remote directory path (default: {DEFAULT_REMOTE_PATH})",
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("SHADER_SYNC_PASSWORD"),
        help="SFTP password (or set SHADER_SYNC_PASSWORD env var)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would be uploaded without making changes",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-upload all files even if they appear unchanged",
    )
    args = parser.parse_args()

    if not LOCAL_SHADERS_DIR.exists():
        print(f"❌ Local shaders directory not found: {LOCAL_SHADERS_DIR}")
        sys.exit(1)

    shader_files = sorted(LOCAL_SHADERS_DIR.glob("*.wgsl"))
    if not shader_files:
        print(f"⚠️  No .wgsl files found in {LOCAL_SHADERS_DIR}")
        sys.exit(0)

    print("=" * 60)
    print("🚀  Shader Sync to storage.1ink.us")
    print("=" * 60)
    print(f"Host:        {args.host}:{args.port}")
    print(f"User:        {args.user}")
    print(f"Remote path: {args.remote_path}")
    print(f"Local dir:   {LOCAL_SHADERS_DIR}")
    print(f"Files:       {len(shader_files)}")
    print(f"Dry run:     {'Yes' if args.dry_run else 'No'}")
    print("=" * 60)
    print()

    if args.dry_run:
        print("🔍  Dry run — no files will be modified.\n")

    # Prompt for password if not provided
    password = args.password
    if not password and not args.dry_run:
        import getpass
        password = getpass.getpass(f"Enter password for {args.user}@{args.host}: ")

    transport = None
    sftp = None
    uploaded = 0
    skipped = 0
    failed = 0

    try:
        if not args.dry_run:
            print(f"Connecting to {args.host}:{args.port}...")
            transport = paramiko.Transport((args.host, args.port))
            transport.connect(username=args.user, password=password)
            sftp = paramiko.SFTPClient.from_transport(transport)
            print("Connected!\n")

        for i, local_path in enumerate(shader_files, 1):
            remote_file_path = f"{args.remote_path}/{local_path.name}"
            print(f"[{i:4d}/{len(shader_files)}] {local_path.name:50s} ... ", end="", flush=True)

            if args.force:
                # Force re-upload: pretend remote doesn't exist
                if args.dry_run:
                    print("[DRY-RUN] would force-upload")
                    uploaded += 1
                else:
                    try:
                        sftp.put(str(local_path), remote_file_path)
                        print("✅ forced")
                        uploaded += 1
                    except Exception as e:
                        print(f"❌ {e}")
                        failed += 1
                continue

            if args.dry_run:
                print("[DRY-RUN] would check/upload")
                uploaded += 1
                continue

            if upload_file(sftp, local_path, remote_file_path, dry_run=False):
                # Distinguish between actual upload and skip based on whether
                # the file already existed with same size — heuristic: check
                # if we can get the remote mtime after put (it will be newer).
                try:
                    rstat = sftp.stat(remote_file_path)
                    lstat = local_path.stat()
                    # If remote size matches local, assume it was already there
                    if rstat.st_size == lstat.st_size and rstat.st_mtime >= lstat.st_mtime:
                        print("⏭️  up to date")
                        skipped += 1
                    else:
                        print("✅ uploaded")
                        uploaded += 1
                except Exception:
                    print("✅ uploaded")
                    uploaded += 1
            else:
                print("❌ failed")
                failed += 1

        print()
        print("=" * 60)
        print("📊  Sync Complete")
        print("=" * 60)
        print(f"Total files:   {len(shader_files)}")
        print(f"Uploaded:      {uploaded} ✅")
        print(f"Up to date:    {skipped} ⏭️")
        print(f"Failed:        {failed} ❌")
        print("=" * 60)

    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)
    finally:
        if sftp:
            sftp.close()
        if transport:
            transport.close()


if __name__ == "__main__":
    main()
