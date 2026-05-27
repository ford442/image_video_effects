#!/usr/bin/env python3
"""
project_deploy_template.py

Copy this file into your project as `deploy.py` (or deploy_contabo.py).
Customize the constants at the top for your project.

Usage:
  1. Build your project:  npm run build   (or python build, etc.)
  2. python deploy.py

This script contacts https://storage.noahcohn.com (your Contabo storage manager)
to upload each file in the build directory.

The actual upload to storage.1ink.us happens server-side using credentials
that live ONLY in the Contabo VPS .env file — no passwords in this repo.

Requirements:
  pip install requests
"""

import os
import sys
from pathlib import Path
import requests
from typing import Optional

# ============================================================
# PER-PROJECT CONFIGURATION - EDIT THESE
# ============================================================
PROJECT_NAME: str = "image_video_effects"
BUILD_DIR: str = "build"
CONTABO_BASE_URL: str = "https://storage.noahcohn.com"

# Optional deploy token (recommended for security).
# Set via environment: export DEPLOY_TOKEN="your_long_token_from_vps_env"
# Or hardcode here only for quick local testing (never commit a real token).
DEPLOY_TOKEN: Optional[str] = "6de44dca5425348f2e2ef9456fc820bfe56a5ace68bddeb6da4a1c2a9d9cadc0"
# ============================================================


def upload_single_file(local_path: Path, rel_path: str) -> bool:
    """Upload one file to the deploy endpoint."""
    url = f"{CONTABO_BASE_URL}/api/deploy/{PROJECT_NAME}/file"
    headers = {}
    if DEPLOY_TOKEN:
        headers["X-Deploy-Token"] = DEPLOY_TOKEN

    try:
        with open(local_path, "rb") as f:
            response = requests.post(
                url,
                files={"file": (local_path.name, f, "application/octet-stream")},
                data={"rel_path": rel_path},
                headers=headers,
                timeout=120,
            )

        if response.status_code == 200:
            print(f"  ✓ {rel_path}")
            return True
        else:
            print(f"  ✗ {rel_path} -> {response.status_code}: {response.text[:200]}")
            return False
    except Exception as exc:
        print(f"  ✗ {rel_path} -> Exception: {exc}")
        return False


def main():
    print(f"\n=== Deploying '{PROJECT_NAME}' via Contabo -> storage.1ink.us ===\n")

    build_path = Path(BUILD_DIR)
    if not build_path.exists() or not build_path.is_dir():
        print(f"ERROR: Build directory '{BUILD_DIR}/' does not exist.")
        print("Please run your build command first (e.g. `npm run build`).")
        sys.exit(1)

    try:
        health = requests.get(f"{CONTABO_BASE_URL}/api/deploy/health", timeout=10)
        if health.status_code == 200:
            print(f"Contabo deploy service: {health.json().get('status', 'unknown')}")
        else:
            print("Warning: Could not reach Contabo deploy health endpoint.")
    except Exception:
        print("Warning: Could not contact storage.noahcohn.com (continuing anyway).")

    print(f"\nUploading files from {BUILD_DIR}/ ...\n")

    uploaded = 0
    failed = 0

    for root, dirs, files in os.walk(build_path):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "__pycache__")]
        for filename in sorted(files):
            local_file = Path(root) / filename
            rel_path = str(local_file.relative_to(build_path))
            if upload_single_file(local_file, rel_path):
                uploaded += 1
            else:
                failed += 1

    print(f"\n=== Deployment complete ===")
    print(f"  Uploaded: {uploaded}")
    print(f"  Failed:   {failed}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
