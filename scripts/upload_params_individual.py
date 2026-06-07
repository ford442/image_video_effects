#!/usr/bin/env python3
"""
Upload shader params individually using PUT /api/shaders/{id}
"""

import json
import requests
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from time import sleep

API_BASE = "https://storage.noahcohn.com"
INPUT_FILE = "/root/image_video_effects/reports/shader_params_extracted.json"
MAX_WORKERS = 10  # Parallel uploads

def load_params():
    with open(INPUT_FILE, 'r') as f:
        return json.load(f)

def format_for_api(shader_id, data):
    """Convert extracted format to API format"""
    params = data.get('params', [])
    if not params:
        return None
    
    # Only upload if has real (non-0.5) defaults
    valid_params = [p for p in params if isinstance(p, dict)]
    has_real = any(p.get('default', 0.5) != 0.5 for p in valid_params)
    if not has_real:
        return None
    
    return {
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
            for i, p in enumerate(valid_params)
        ]
    }

def upload_shader(shader_id, payload):
    """Upload params for single shader via PUT"""
    url = f"{API_BASE}/api/shaders/{shader_id}"
    try:
        response = requests.put(url, json=payload, timeout=15)
        if response.status_code == 200:
            return {"success": True, "id": shader_id}
        else:
            return {"success": False, "id": shader_id, "error": f"HTTP {response.status_code}"}
    except Exception as e:
        return {"success": False, "id": shader_id, "error": str(e)}

def main():
    print("Loading extracted params...")
    data = load_params()
    
    # Prepare upload list
    shaders_to_upload = {}
    for shader_id, shader_data in data.items():
        formatted = format_for_api(shader_id, shader_data)
        if formatted:
            shaders_to_upload[shader_id] = formatted
    
    total = len(shaders_to_upload)
    print(f"Found {total} shaders with real defaults")
    
    if total == 0:
        print("Nothing to upload!")
        return
    
    # Upload in parallel
    success_count = 0
    fail_count = 0
    failed_shaders = []
    
    print(f"\nUploading {total} shaders (parallel={MAX_WORKERS})...")
    
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_id = {
            executor.submit(upload_shader, sid, payload): sid 
            for sid, payload in shaders_to_upload.items()
        }
        
        for i, future in enumerate(as_completed(future_to_id)):
            result = future.result()
            
            if result['success']:
                success_count += 1
            else:
                fail_count += 1
                failed_shaders.append((result['id'], result.get('error')))
            
            if (i + 1) % 50 == 0 or (i + 1) == total:
                print(f"  Progress: {i+1}/{total} | ✓ {success_count} | ✗ {fail_count}")
    
    print(f"\n{'='*60}")
    print(f"UPLOAD COMPLETE")
    print(f"{'='*60}")
    print(f"Success: {success_count}")
    print(f"Failed: {fail_count}")
    
    # Save failed list
    if failed_shaders:
        with open('/root/image_video_effects/reports/failed_uploads.json', 'w') as f:
            json.dump([s for s, _ in failed_shaders], f, indent=2)
        print(f"\nFailed list saved to failed_uploads.json ({len(failed_shaders)} items)")
    
    # Verify
    print("\nVerifying uploads...")
    test_shaders = ['liquid', 'neon-pulse', 'chromatic-folds', 'reaction-diffusion']
    for shader_id in test_shaders:
        try:
            resp = requests.get(f"{API_BASE}/api/shaders/{shader_id}", timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                params = data.get('params', [])
                defaults = [p.get('default', 0.5) for p in params[:4]]
                has_real = any(d != 0.5 for d in defaults)
                status = "✓" if has_real else "✗"
                print(f"  {status} {shader_id}: {defaults}")
            else:
                print(f"  ✗ {shader_id}: HTTP {resp.status_code}")
        except Exception as e:
            print(f"  ✗ {shader_id}: {e}")

if __name__ == "__main__":
    main()
