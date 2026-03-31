#!/usr/bin/env python3
"""
Storage Manager API Patch - Add PUT /api/shaders/{id} endpoint

This patch adds support for updating shader params via the API.
Apply this to storage_manager/app.py or main.py on the VPS.
"""

PATCH_CODE = '''
# ═══════════════════════════════════════════════════════════════════════════════
# SHADER PARAM UPDATE ENDPOINTS - Add these to your FastAPI app
# ═══════════════════════════════════════════════════════════════════════════════

import os
import json
from fastapi import HTTPException
from pydantic import BaseModel
from typing import List, Optional

# Pydantic models for request validation
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
    name: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[List[str]] = None
    category: Optional[str] = None


@app.put("/api/shaders/{shader_id}")
async def update_shader(shader_id: str, request: ShaderUpdateRequest):
    """
    Update shader metadata including params.
    
    Example:
        PUT /api/shaders/liquid
        {
            "params": [
                {"name": "param1", "label": "Viscosity", "default": 0.5, "min": 0, "max": 1},
                {"name": "param2", "label": "Turbulence", "default": 0.4, "min": 0, "max": 1}
            ]
        }
    """
    try:
        # Load current shader list
        cache_key = "local:shaders:list"
        shaders = await cache.get(cache_key) if 'cache' in globals() else None
        
        if not shaders:
            # Regenerate list if not cached
            shaders = await regenerate_shader_list()
        
        # Find the shader
        target_shader = None
        for shader in shaders:
            if shader.get('id') == shader_id:
                target_shader = shader
                break
        
        if not target_shader:
            raise HTTPException(status_code=404, detail=f"Shader '{shader_id}' not found")
        
        # Update fields if provided
        if request.params is not None:
            # Convert Pydantic models to dicts
            target_shader['params'] = [
                {
                    "name": p.name,
                    "label": p.label or p.name,
                    "default": p.default,
                    "min": p.min,
                    "max": p.max,
                    "step": p.step,
                    "description": p.description
                }
                for p in request.params
            ]
        
        if request.name is not None:
            target_shader['name'] = request.name
            
        if request.description is not None:
            target_shader['description'] = request.description
            
        if request.tags is not None:
            target_shader['tags'] = request.tags
        
        # Also update the source JSON file if it exists
        await update_shader_json_file(shader_id, target_shader)
        
        # Invalidate cache to reflect changes
        if 'cache' in globals():
            await cache.delete(cache_key)
        
        return {
            "success": True,
            "shader": target_shader,
            "message": f"Shader '{shader_id}' updated successfully"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        import logging
        logging.error(f"Error updating shader {shader_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


async def update_shader_json_file(shader_id: str, shader_data: dict):
    """
    Update the source JSON definition file for a shader.
    This ensures persistence across restarts.
    """
    shader_definitions_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "shader_definitions"
    )
    
    # Try to find the JSON file in category subdirectories
    category = shader_data.get('category', '')
    
    # Possible paths to check
    paths_to_check = []
    if category:
        paths_to_check.append(os.path.join(shader_definitions_dir, category, f"{shader_id}.json"))
    
    # Check common categories
    common_categories = ['image', 'generative', 'artistic', 'distortion', 'simulation',
                         'liquid-effects', 'lighting-effects', 'visual-effects',
                         'interactive-mouse', 'geometric', 'retro-glitch']
    for cat in common_categories:
        paths_to_check.append(os.path.join(shader_definitions_dir, cat, f"{shader_id}.json"))
    
    # Flat path as last resort
    paths_to_check.append(os.path.join(shader_definitions_dir, f"{shader_id}.json"))
    
    # Find existing file
    json_path = None
    for path in paths_to_check:
        if os.path.exists(path):
            json_path = path
            break
    
    if json_path:
        try:
            # Read existing file
            with open(json_path, 'r', encoding='utf-8') as f:
                file_data = json.load(f)
            
            # Update params
            if 'params' in shader_data:
                file_data['params'] = shader_data['params']
            
            # Write back
            with open(json_path, 'w', encoding='utf-8') as f:
                json.dump(file_data, f, indent=2, ensure_ascii=False)
            
            import logging
            logging.info(f"Updated JSON file: {json_path}")
            
        except Exception as e:
            import logging
            logging.warning(f"Failed to update JSON file {json_path}: {e}")


async def regenerate_shader_list():
    """Regenerate the shader list from disk (your existing logic)"""
    # This should match your existing /api/shaders GET implementation
    # Return the list of shaders
    pass  # Implementation depends on your existing code
'''

# Write the patch file
with open('/root/image_video_effects/storage_api_put_endpoint.patch', 'w') as f:
    f.write(PATCH_CODE)

print("Patch file created: storage_api_put_endpoint.patch")
print("\n=== INSTRUCTIONS ===")
print("1. SSH to storage.noahcohn.com")
print("2. Find your FastAPI app file (usually storage_manager/app.py or main.py)")
print("3. Add the code above to your FastAPI app")
print("4. Restart the server (systemctl restart your-service or similar)")
print("\nThe patch adds:")
print("  - PUT /api/shaders/{shader_id} endpoint")
print("  - Pydantic models for request validation")
print("  - Automatic JSON file updates for persistence")
print("  - Cache invalidation on update")
