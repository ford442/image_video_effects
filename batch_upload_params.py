#!/usr/bin/env python3
"""
Batch upload shader params to storage API using POST /api/shaders/batch
"""

import json
import requests
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

API_BASE = "https://storage.noahcohn.com"
INPUT_FILE = "/root/image_video_effects/shader_params_extracted.json"
BATCH_SIZE = 50  # Upload 50 shaders per batch request

def load_params():
    with open(INPUT_FILE, 'r') as f:
        return json.load(f)

def format_for_api(shader_id, data):
    """Convert extracted format to API format"""
    params = data.get('params', [])
    if not params:
        return None
    
    # Filter out params with only 0.5 defaults (no real tuning)
    has_real_defaults = any(p.get('default', 0.5) != 0.5 for p in params if isinstance(p, dict))
    if not has_real_defaults:
        return None
    
    return {
        "id": shader_id,
        "params": [
            {
                "name": p.get('id', f"param{i}"),
                "label": p.get('name', f"Parameter {i+1}"),
                "default": p.get('default', 0.5),
                "min": p.get('min', 0.0),
                "max": p.get('max', 1.0),
                "step": p.get('step', 0.01),
                "description": p.get('description', '')
            }
            for i, p in enumerate(params) if isinstance(p, dict)
        ]
    }

def upload_batch(batch):
    """Upload a batch of shaders using the batch endpoint"""
    url = f"{API_BASE}/api/shaders/batch"
    try:
        response = requests.post(url, json=batch, timeout=60)
        if response.status_code == 200:
            return {"success": True, "count": len(batch)}
        else:
            return {"success": False, "error": f"HTTP {response.status_code}", "count": len(batch)}
    except Exception as e:
        return {"success": False, "error": str(e), "count": len(batch)}

def main():
    print("Loading extracted params...")
    data = load_params()
    
    # Format all shaders
    shaders_to_upload = []
    for shader_id, shader_data in data.items():
        formatted = format_for_api(shader_id, shader_data)
        if formatted:
            shaders_to_upload.append(formatted)
    
    total = len(shaders_to_upload)
    print(f"Found {total} shaders with real defaults to upload")
    
    if total == 0:
        print("Nothing to upload!")
        return
    
    # Create batches
    batches = [shaders_to_upload[i:i+BATCH_SIZE] for i in range(0, total, BATCH_SIZE)]
    print(f"Created {len(batches)} batches of {BATCH_SIZE}")
    
    # Upload batches
    success_count = 0
    fail_count = 0
    
    print("\nUploading batches...")
    for i, batch in enumerate(batches):
        result = upload_batch(batch)
        if result['success']:
            success_count += result['count']
            print(f"  Batch {i+1}/{len(batches)}: ✓ {result['count']} shaders")
        else:
            fail_count += result['count']
            print(f"  Batch {i+1}/{len(batches)}: ✗ {result['error']}")
    
    print(f"\n{'='*60}")
    print(f"UPLOAD COMPLETE")
    print(f"{'='*60}")
    print(f"Total: {total}")
    print(f"Success: {success_count}")
    print(f"Failed: {fail_count}")
    
    # Test a few shaders
    print("\nVerifying uploads...")
    test_shaders = ['liquid', 'neon-pulse', 'chromatic-folds']
    for shader_id in test_shaders:
        try:
            resp = requests.get(f"{API_BASE}/api/shaders/{shader_id}", timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                params = data.get('params', [])
                if params and any(p.get('default', 0.5) != 0.5 for p in params):
                    print(f"  ✓ {shader_id}: has real defaults")
                else:
                    print(f"  ✗ {shader_id}: still generic defaults")
            else:
                print(f"  ✗ {shader_id}: HTTP {resp.status_code}")
        except Exception as e:
            print(f"  ✗ {shader_id}: {e}")

if __name__ == "__main__":
    main()
