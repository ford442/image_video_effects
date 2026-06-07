#!/usr/bin/env python3
"""
Bulk upload all local shaders to VPS Storage API.
Uploads 624 shaders from shader_coordinates.json + .wgsl files.
"""

import json
import requests
from pathlib import Path
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import sys

# Configuration
API_BASE = "https://storage.noahcohn.com"
SHADERS_DIR = Path("public/shaders")
COORDINATES_FILE = Path("public/shader_coordinates.json")
MAX_WORKERS = 10  # Max parallel uploads


def upload_shader(shader_id: str, meta: dict, wgsl_code: str) -> dict:
    """Upload a single shader to the VPS API."""
    
    payload = {
        "id": shader_id,
        "name": meta.get("name", shader_id),
        "wgsl_code": wgsl_code,
        "tags": meta.get("tags", []),
        "category": meta.get("category", "image"),
        "features": meta.get("features", []),
        "description": meta.get("reason", ""),
        "coordinate": meta.get("coordinate"),
        "source": "bulk_upload",
        "date": datetime.now().isoformat(),
    }
    
    try:
        resp = requests.post(
            f"{API_BASE}/api/shaders",
            json=payload,
            timeout=30
        )
        if resp.status_code == 200:
            return {"id": shader_id, "status": "success"}
        else:
            return {"id": shader_id, "status": "failed", "error": f"HTTP {resp.status_code}: {resp.text[:100]}"}
    except Exception as e:
        return {"id": shader_id, "status": "error", "error": str(e)}


def main():
    """Main upload routine."""
    print("=" * 60)
    print("Bulk Shader Upload to VPS API")
    print("=" * 60)
    
    # Load shader coordinates
    if not COORDINATES_FILE.exists():
        print(f"❌ Coordinates file not found: {COORDINATES_FILE}")
        sys.exit(1)
    
    with open(COORDINATES_FILE) as f:
        coordinates = json.load(f)
    
    print(f"📁 Found {len(coordinates)} shaders in coordinates file")
    
    # Prepare upload list
    to_upload = []
    missing_wgsl = []
    
    for shader_id, meta in coordinates.items():
        wgsl_path = SHADERS_DIR / f"{shader_id}.wgsl"
        
        if not wgsl_path.exists():
            missing_wgsl.append(shader_id)
            continue
        
        wgsl_code = wgsl_path.read_text()
        to_upload.append((shader_id, meta, wgsl_code))
    
    if missing_wgsl:
        print(f"⚠️  {len(missing_wgsl)} shaders missing .wgsl files (will be skipped)")
        print(f"   Examples: {', '.join(missing_wgsl[:3])}")
    
    print(f"📤 Prepared {len(to_upload)} shaders for upload")
    print()
    
    # Confirm upload
    if len(sys.argv) < 2 or sys.argv[1] != "--yes":
        confirm = input("Proceed with upload? [y/N]: ")
        if confirm.lower() != "y":
            print("Aborted.")
            sys.exit(0)
    
    # Upload all shaders with progress
    results = {"success": 0, "failed": 0, "errors": []}
    
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(upload_shader, sid, meta, code): sid 
            for sid, meta, code in to_upload
        }
        
        for i, future in enumerate(as_completed(futures), 1):
            result = future.result()
            
            if result["status"] == "success":
                results["success"] += 1
            else:
                results["failed"] += 1
                results["errors"].append(f"{result['id']}: {result.get('error', 'unknown')}")
            
            # Progress update every 10 shaders
            if i % 10 == 0 or i == len(to_upload):
                print(f"\r⏳ Progress: {i}/{len(to_upload)} ({results['success']} OK, {results['failed']} failed)", end="", flush=True)
    
    print()
    print()
    print("=" * 60)
    print("Upload Complete!")
    print("=" * 60)
    print(f"✅ Success: {results['success']}")
    print(f"❌ Failed: {results['failed']}")
    
    if results["errors"]:
        print()
        print("Errors (first 10):")
        for err in results["errors"][:10]:
            print(f"  - {err}")
    
    # Verify upload
    print()
    print("Verifying upload...")
    try:
        resp = requests.get(f"{API_BASE}/api/shaders", timeout=30)
        if resp.status_code == 200:
            shaders = resp.json()
            print(f"📊 VPS API now has {len(shaders)} shaders")
        else:
            print(f"⚠️  Could not verify upload count (HTTP {resp.status_code})")
    except Exception as e:
        print(f"⚠️  Could not verify: {e}")


if __name__ == "__main__":
    main()
