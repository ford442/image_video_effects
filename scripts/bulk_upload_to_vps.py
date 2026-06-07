#!/usr/bin/env python3
"""
Bulk Upload Script - Migrate local shaders to VPS Storage API
Uploads all .wgsl files with their coordinates to the remote database
"""

import os
import json
import requests
import time
from pathlib import Path

# --- CONFIGURATION ---
# Point this to your live Contabo VPS Storage Manager
API_BASE_URL = "https://storage.noahcohn.com"
API_UPLOAD_URL = f"{API_BASE_URL}/api/shaders"

# Local paths in your repository
SHADERS_DIR = "./public/shaders"
COORDINATES_FILE = "./public/shader_coordinates.json"

def upload_via_api(filename: str, file_path: str, coord_data: dict) -> bool:
    """Upload shader using the REST API endpoint."""
    try:
        with open(file_path, 'r') as f:
            wgsl_code = f.read()
        
        # Create metadata
        shader_id = filename.replace('.wgsl', '')
        display_name = coord_data.get('name', shader_id.replace('_', ' ').replace('-', ' ').title())
        
        # Prepare payload for REST API
        payload = {
            "id": shader_id,
            "name": display_name,
            "wgsl_code": wgsl_code,
            "author": "ford442",
            "description": coord_data.get('reason', 'Migrated from local repository'),
            "tags": coord_data.get('tags', ['migration']),
            "coordinate": coord_data.get('coordinate'),
            "category": coord_data.get('category', 'image'),
            "features": coord_data.get('features', []),
            "format": "wgsl",
            "source": "migration",
        }
        
        # Send to REST API
        response = requests.post(
            API_UPLOAD_URL,
            json=payload,
            headers={'Content-Type': 'application/json'},
            timeout=30
        )
        
        if response.status_code in [200, 201]:
            return True
        else:
            print(f"❌ API Error {response.status_code}: {response.text[:100]}")
            return False
            
    except Exception as e:
        print(f"❌ Upload Error: {e}")
        return False

def main():
    print("=" * 60)
    print("🚀 BULK SHADER UPLOAD TO VPS")
    print("=" * 60)
    print(f"API URL: {API_BASE_URL}")
    print(f"Shaders Dir: {SHADERS_DIR}")
    print(f"Coordinates File: {COORDINATES_FILE}")
    print("=" * 60)
    print()

    # 1. Load the coordinate mappings
    coordinates = {}
    if os.path.exists(COORDINATES_FILE):
        with open(COORDINATES_FILE, 'r') as f:
            coordinates = json.load(f)
        print(f"✅ Loaded {len(coordinates)} coordinate mappings")
    else:
        print(f"⚠️ Warning: Could not find {COORDINATES_FILE}")
        print(f"   Coordinates will be null")

    # 2. Find all WGSL files
    shaders_path = Path(SHADERS_DIR)
    if not shaders_path.exists():
        print(f"❌ Error: Shaders directory not found at {SHADERS_DIR}")
        return

    shader_files = sorted([f for f in shaders_path.glob("*.wgsl")])
    total_files = len(shader_files)
    
    print(f"📦 Found {total_files} .wgsl files to upload")
    print()

    success_count = 0
    fail_count = 0
    failed_files = []

    # 3. Iterate and Upload
    for index, file_path in enumerate(shader_files, 1):
        filename = file_path.name
        shader_id = filename.replace('.wgsl', '')
        
        # Get coordinate data
        coord_data = coordinates.get(shader_id, {})
        if isinstance(coord_data, dict):
            coord = coord_data.get('coordinate', 'N/A')
        else:
            coord = 'N/A'
        
        print(f"[{index:4d}/{total_files}] {filename:50s} (Coord: {str(coord):>6s}) ... ", end="", flush=True)

        try:
            if upload_via_api(filename, str(file_path), coord_data if isinstance(coord_data, dict) else {}):
                print("✅")
                success_count += 1
            else:
                print("❌ Failed")
                fail_count += 1
                failed_files.append(filename)

        except Exception as e:
            print(f"❌ Error: {str(e)[:50]}")
            fail_count += 1
            failed_files.append(filename)
        
        # Small delay to avoid overwhelming the VPS
        time.sleep(0.2)
        
        # Progress update every 50 files
        if index % 50 == 0:
            print(f"\n📊 Progress: {index}/{total_files} | Success: {success_count} | Failed: {fail_count}\n")

    # Final Summary
    print()
    print("=" * 60)
    print("🎉 UPLOAD COMPLETE!")
    print("=" * 60)
    print(f"Total Files:    {total_files}")
    print(f"Successful:     {success_count} ✅")
    print(f"Failed:         {fail_count} ❌")
    print(f"Success Rate:   {(success_count/total_files*100):.1f}%")
    print("=" * 60)
    
    if failed_files:
        print("\n⚠️ Failed files (first 10):")
        for f in failed_files[:10]:
            print(f"   - {f}")
    
    print()
    print("📡 Next steps:")
    print("   1. Verify upload: curl https://storage.noahcohn.com/api/shaders")
    print("   2. Refresh web app to see new shaders")
    print()

if __name__ == "__main__":
    main()
