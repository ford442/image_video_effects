#!/usr/bin/env python3
"""
Apply this code to storage_manager/app.py on the VPS

Find the FastAPI app instance (usually `app = FastAPI()`) and add these
endpoints after your existing /api/shaders endpoint.
"""

# Add these imports at the top if not already present:
# from pydantic import BaseModel
# from typing import List, Optional

# Add these Pydantic models:
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

# Add this endpoint:
@app.put("/api/shaders/{shader_id}")
async def update_shader(shader_id: str, request: ShaderUpdateRequest):
    """Update shader params"""
    shader_definitions_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "shader_definitions"
    )
    
    # Find the shader JSON file
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
