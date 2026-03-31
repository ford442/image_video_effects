# VPS Storage Manager Patch - Shader Param Update Endpoint

## Problem
The storage manager API returns generic 0.5 defaults for all shader params. We need to update it to support real defaults.

## Solution
Add a `PUT /api/shaders/{shader_id}` endpoint that updates shader params in the JSON definition files.

## Files Created

| File | Description |
|------|-------------|
| `storage_api_put_endpoint.patch` | Complete patch with models and endpoint |
| `apply_to_storage_manager.py` | Simple code snippet to add |
| `deploy_patch_to_vps.sh` | Automated deployment script |
| `upload_params_to_api.py` | Client script to upload all 512 shaders |

## Manual Installation (Recommended)

### Step 1: SSH to VPS
```bash
ssh root@storage.noahcohn.com
```

### Step 2: Find Your App File
```bash
find /opt /var /home -name "app.py" -o -name "main.py" 2>/dev/null | grep -E "(storage|api)"
```

Common locations:
- `/opt/storage_manager/app.py`
- `/var/www/storage_manager/app.py`
- `/home/user/storage_manager/main.py`

### Step 3: Add the Endpoint

Add these Pydantic models near your other imports:

```python
from pydantic import BaseModel
from typing import List, Optional

class ShaderParam(BaseModel):
    name: str
    label: Optional[str] = None
    default: float = 0.5
    min: float = 0.0
    max: float = 1.0
    step: Optional[float] = 0.01
    description: Optional[str] = ""

class ShaderUpdateRequest(BaseModel):
    params: Optional[List[ShaderParam]] = None
```

Add this endpoint after your existing `/api/shaders` endpoint:

```python
@app.put("/api/shaders/{shader_id}")
async def update_shader(shader_id: str, request: ShaderUpdateRequest):
    """Update shader parameters"""
    shader_definitions_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "shader_definitions"
    )
    
    # Find JSON file in category subdirectories
    categories = ['image', 'generative', 'artistic', 'distortion', 'simulation',
                  'liquid-effects', 'lighting-effects', 'visual-effects',
                  'interactive-mouse', 'geometric', 'retro-glitch']
    
    json_path = None
    for cat in categories:
        path = os.path.join(shader_definitions_dir, cat, f"{shader_id}.json")
        if os.path.exists(path):
            json_path = path
            break
    
    if not json_path:
        raise HTTPException(status_code=404, detail=f"Shader {shader_id} not found")
    
    # Read, update, write
    with open(json_path, 'r') as f:
        data = json.load(f)
    
    if request.params:
        data['params'] = [p.dict() for p in request.params]
    
    with open(json_path, 'w') as f:
        json.dump(data, f, indent=2)
    
    # Clear cache
    await cache.delete("local:shaders:list")
    
    return {"success": True, "shader_id": shader_id}
```

### Step 4: Restart Service

```bash
# Option 1: systemd
systemctl restart storage_manager

# Option 2: supervisor
supervisorctl restart storage_manager

# Option 3: manual
pkill -f "uvicorn.*app:app"
cd /opt/storage_manager && python3 -m uvicorn app:app --host 0.0.0.0 --port 8000 &
```

### Step 5: Test

```bash
# Test the new endpoint
curl -X PUT "https://storage.noahcohn.com/api/shaders/liquid" \
  -H "Content-Type: application/json" \
  -d '{
    "params": [
      {"name": "param1", "label": "Viscosity", "default": 0.5, "min": 0, "max": 1},
      {"name": "param2", "label": "Turbulence", "default": 0.4, "min": 0, "max": 1}
    ]
  }'

# Verify
curl "https://storage.noahcohn.com/api/shaders/liquid"
```

## Step 6: Upload All 512 Shaders

Once the endpoint is working, run the upload script from this server:

```bash
cd /root/image_video_effects
python3 upload_params_to_api.py
```

This will upload real defaults for all 512 shaders with non-0.5 values.

## Verification

After upload, verify:

```bash
# Should show real defaults, not all 0.5s
curl "https://storage.noahcohn.com/api/shaders/liquid" | jq '.params'
```

Expected output:
```json
[
  {"name": "param1", "label": "Viscosity", "default": 0.5, ...},
  {"name": "param2", "label": "Turbulence", "default": 0.4, ...},
  ...
]
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| 404 on PUT | Check endpoint is registered after `@app` initialization |
| 405 Method Not Allowed | Ensure `@app.put` not `@app.get` |
| Permission denied | Check file permissions on `shader_definitions/` |
| Changes not persisting | Verify JSON files are being written |
| Cache not clearing | Check `cache.delete()` is working |

## Alternative: Direct File Copy

If modifying the API is too complex, you can directly copy the extracted JSON files:

```bash
# On this server
cd /root/image_video_effects
zip -r shader_definitions.zip shader_definitions/

# SCP to VPS
scp shader_definitions.zip root@storage.noahcohn.com:/opt/storage_manager/

# SSH to VPS and extract
ssh root@storage.noahcohn.com "cd /opt/storage_manager && unzip -o shader_definitions.zip"
```

This replaces all JSON files with versions containing real params.
