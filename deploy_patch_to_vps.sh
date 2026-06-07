#!/bin/bash
# Deploy shader param update endpoint to VPS storage manager

VPS_HOST="storage.noahcohn.com"
VPS_USER="root"  # Change to your VPS username
APP_DIR="/path/to/storage_manager"  # Change to actual path

echo "=== Deploying Shader API Patch to VPS ==="
echo "Host: $VPS_HOST"
echo "App dir: $APP_DIR"
echo ""

# SSH to VPS and apply patch
ssh $VPS_USER@$VPS_HOST << 'EOF'
    APP_FILE="/opt/storage_manager/app.py"  # Adjust path as needed
    
    # Backup original
    cp $APP_FILE ${APP_FILE}.backup.$(date +%Y%m%d_%H%M%S)
    
    # Check if endpoint already exists
    if grep -q "@app.put\(\"/api/shaders/{shader_id}\"" $APP_FILE; then
        echo "PUT endpoint already exists!"
        exit 0
    fi
    
    # Add Pydantic import if missing
    if ! grep -q "from pydantic import BaseModel" $APP_FILE; then
        sed -i '1s/^/from pydantic import BaseModel\nfrom typing import List, Optional\n\n/' $APP_FILE
    fi
    
    # Create temp file with endpoint code
    cat >> /tmp/endpoint_code.py << 'ENDPOINT'

# ═══════════════════════════════════════════════════════════════════
# SHADER PARAM UPDATE ENDPOINT
# ═══════════════════════════════════════════════════════════════════

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

@app.put("/api/shaders/{shader_id}")
async def update_shader(shader_id: str, request: ShaderUpdateRequest):
    """Update shader parameters"""
    import os
    import json
    
    shader_definitions_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "shader_definitions"
    )
    
    # Find JSON file
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
    
    # Update file
    with open(json_path, 'r') as f:
        data = json.load(f)
    
    if request.params:
        data['params'] = [p.dict() for p in request.params]
    
    with open(json_path, 'w') as f:
        json.dump(data, f, indent=2)
    
    # Clear cache
    await cache.delete("local:shaders:list")
    
    return {"success": True, "shader_id": shader_id}

# ═══════════════════════════════════════════════════════════════════
ENDPOINT
    
    # Append to app file
    cat /tmp/endpoint_code.py >> $APP_FILE
    
    # Restart service (adjust command as needed)
    systemctl restart storage_manager || supervisorctl restart storage_manager || pkill -f "uvicorn.*app:app"
    
    echo "Patch applied successfully!"
    echo "Endpoint added: PUT /api/shaders/{shader_id}"
EOF

echo ""
echo "=== Deployment Complete ==="
echo "Test with: curl -X PUT https://$VPS_HOST/api/shaders/liquid -H 'Content-Type: application/json' -d '{"params": [{"name":"param1","label":"Viscosity","default":0.5,"min":0,"max":1}]}'"
