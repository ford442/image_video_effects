#!/usr/bin/env python3
"""
Bulk upload shaders via webhook endpoint (fallback method).
Works with current VPS deployment until POST /api/shaders is live.
"""

import json
import requests
from pathlib import Path
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import sys

# Configuration
WEBHOOK_URL = "https://storage.noahcohn.com/webhook/image-effects"
SHADERS_DIR = Path("public/shaders")
COORDINATES_FILE = Path("public/shader_coordinates.json")
MAX_WORKERS = 5


def upload_via_webhook(shader_id: str, meta: dict, wgsl_code: str) -> dict:
    """Upload shader via image-effects webhook."""
    
    # Webhook expects specific payload format
    payload = {
        "action": "save_shader",
        "name": shader_id,
        "id": shader_id,
        "wgsl_code": wgsl_code,
        "metadata": {
            "name": meta.get("name", shader_id),
            "category": meta.get("category", "image"),
            "tags": meta.get("tags", []),
            "features": meta.get("features", []),
            "coordinate": meta.get("coordinate"),
            "source": "bulk_upload_webhook",
            "date": datetime.now().isoformat(),
        }
    }
    
    try:
        resp = requests.post(
            WEBHOOK_URL,
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
    print("=" * 60)
    print("Bulk Shader Upload via Webhook (Fallback)")
    print("=" * 60)
    
    # Load shader coordinates
    if not COORDINATES_FILE.exists():
        print(f"❌ Coordinates file not found: {COORDINATES_FILE}")
        sys.exit(1)
    
    with open(COORDINATES_FILE) as f:
        coordinates = json.load(f)
    
    print(f"📁 Found {len(coordinates)} shaders")
    
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
    
    print(f"📤 Prepared {len(to_upload)} shaders for upload")
    print(f"⚠️  Skipped {len(missing_wgsl)} missing WGSL files")
    
    if len(sys.argv) < 2 or sys.argv[1] != "--yes":
        confirm = input("\nProceed with webhook upload? [y/N]: ")
        if confirm.lower() != "y":
            print("Aborted.")
            sys.exit(0)
    
    # Upload all shaders
    results = {"success": 0, "failed": 0, "errors": []}
    
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(upload_via_webhook, sid, meta, code): sid 
            for sid, meta, code in to_upload
        }
        
        for i, future in enumerate(as_completed(futures), 1):
            result = future.result()
            
            if result["status"] == "success":
                results["success"] += 1
            else:
                results["failed"] += 1
                results["errors"].append(f"{result['id']}: {result.get('error', 'unknown')}")
            
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
        print("\nErrors (first 10):")
        for err in results["errors"][:10]:
            print(f"  - {err}")


if __name__ == "__main__":
    main()
