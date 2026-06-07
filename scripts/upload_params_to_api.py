#!/usr/bin/env python3
"""
Upload extracted shader params to storage manager API
"""

import json
import requests
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from time import sleep

# Configuration
API_BASE_URL = "https://storage.noahcohn.com"
INPUT_FILE = "/root/image_video_effects/reports/shader_params_extracted.json"
BATCH_SIZE = 50  # Process in batches to avoid overwhelming API
MAX_WORKERS = 5  # Parallel uploads

def load_extracted_params():
    """Load the extracted shader params from JSON file"""
    with open(INPUT_FILE, 'r') as f:
        return json.load(f)

def upload_shader_params(shader_id: str, data: dict) -> dict:
    """Upload params for a single shader to the API"""
    url = f"{API_BASE_URL}/api/shaders/{shader_id}"
    
    # Format params for API
    params = data.get('params', [])
    
    # Convert to API format
    api_params = []
    for p in params:
        api_params.append({
            "name": p.get('id', f"param{len(api_params)+1}"),
            "label": p.get('name', f"Parameter {len(api_params)+1}"),
            "default": p.get('default', 0.5),
            "min": p.get('min', 0.0),
            "max": p.get('max', 1.0),
            "description": p.get('description', '')
        })
    
    payload = {"params": api_params}
    
    try:
        response = requests.put(url, json=payload, timeout=30)
        if response.status_code == 200:
            return {"success": True, "shader_id": shader_id}
        else:
            return {"success": False, "shader_id": shader_id, "error": f"HTTP {response.status_code}"}
    except Exception as e:
        return {"success": False, "shader_id": shader_id, "error": str(e)}

def main():
    # Load extracted data
    print("Loading extracted shader params...")
    shaders = load_extracted_params()
    total = len(shaders)
    print(f"Found {total} shaders with params")
    
    # Filter to only shaders with non-trivial params
    shaders_to_upload = {}
    for shader_id, data in shaders.items():
        params = data.get('params', [])
        if not params or len(params) == 0:
            continue
        # Ensure params are dicts not strings
        valid_params = [p for p in params if isinstance(p, dict)]
        # Skip if all defaults are 0.5
        has_real_defaults = any(p.get('default', 0.5) != 0.5 for p in valid_params)
        if has_real_defaults and len(valid_params) > 0:
            shaders_to_upload[shader_id] = {"category": data.get("category", ""), "params": valid_params}
    
    upload_count = len(shaders_to_upload)
    print(f"Shaders with real defaults to upload: {upload_count}")
    
    if upload_count == 0:
        print("No shaders need uploading!")
        return
    
    # Upload in parallel
    success_count = 0
    fail_count = 0
    failed_shaders = []
    
    print(f"\nUploading {upload_count} shaders to API...")
    
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_shader = {
            executor.submit(upload_shader_params, shader_id, data): shader_id 
            for shader_id, data in shaders_to_upload.items()
        }
        
        for i, future in enumerate(as_completed(future_to_shader)):
            result = future.result()
            shader_id = result['shader_id']
            
            if result['success']:
                success_count += 1
            else:
                fail_count += 1
                failed_shaders.append((shader_id, result.get('error')))
            
            # Progress report every 50 shaders
            if (i + 1) % 50 == 0 or (i + 1) == upload_count:
                print(f"  Progress: {i+1}/{upload_count} | Success: {success_count} | Failed: {fail_count}")
    
    # Summary
    print(f"\n{'='*60}")
    print(f"UPLOAD COMPLETE")
    print(f"{'='*60}")
    print(f"Total processed: {upload_count}")
    print(f"Success: {success_count}")
    print(f"Failed: {fail_count}")
    
    if failed_shaders:
        print(f"\nFailed shaders:")
        for shader_id, error in failed_shaders[:10]:  # Show first 10
            print(f"  - {shader_id}: {error}")
        if len(failed_shaders) > 10:
            print(f"  ... and {len(failed_shaders) - 10} more")
    
    # Save failed list for retry
    if failed_shaders:
        with open('/root/image_video_effects/reports/failed_uploads.json', 'w') as f:
            json.dump([s for s, _ in failed_shaders], f, indent=2)
        print(f"\nFailed list saved to failed_uploads.json")

if __name__ == "__main__":
    main()
