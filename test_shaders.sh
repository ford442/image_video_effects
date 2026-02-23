#!/bin/bash

API_BASE="https://ford442-storage-manager.hf.space"
# For local testing, use:
# API_BASE="http://localhost:7860"

echo "=== Storage Manager Shader Test Script ==="
echo "API: $API_BASE"
echo ""

# Check if we have .wgsl files to upload
echo "Checking for .wgsl files in public/shaders/..."
WGSL_FILES=$(find public/shaders -name "*.wgsl" -type f 2>/dev/null | head -3)

if [ -z "$WGSL_FILES" ]; then
    echo "⚠️  No .wgsl files found in public/shaders/"
    echo "Creating a test shader..."
    
    mkdir -p test_shaders
    cat > test_shaders/test_effect.wgsl << 'EOF'
// Test Generative Shader
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Simple animated gradient
    let color = vec3<f32>(
        sin(uv.x * 3.14159 + time) * 0.5 + 0.5,
        sin(uv.y * 3.14159 + time * 1.5) * 0.5 + 0.5,
        sin((uv.x + uv.y) * 3.14159 + time * 0.5) * 0.5 + 0.5
    );
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
EOF
    WGSL_FILES="test_shaders/test_effect.wgsl"
fi

# Upload shaders
echo ""
echo "=== Uploading Test Shaders ==="

COUNTER=1
for file in $WGSL_FILES; do
    echo "Uploading: $file"
    
    NAME=$(basename "$file" .wgsl | sed 's/-/ /g' | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')
    
    RESPONSE=$(curl -s -X POST "$API_BASE/api/shaders/upload" \
        -F "file=@$file" \
        -F "name=$NAME" \
        -F "description=Auto-uploaded test shader from $file" \
        -F "tags=generative,test,auto-upload" \
        -F "author=ford442")
    
    echo "Response: $RESPONSE"
    
    # Extract shader ID
    SHADER_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ ! -z "$SHADER_ID" ]; then
        echo "✅ Uploaded with ID: $SHADER_ID"
        
        # Rate the shader
        STARS=$((3 + COUNTER % 3))  # Alternate ratings 3, 4, 5
        echo "   Rating: $STARS stars"
        curl -s -X POST "$API_BASE/api/shaders/$SHADER_ID/rate" \
            -F "stars=$STARS" > /dev/null
        
        # Save first ID for later tests
        if [ "$COUNTER" -eq 1 ]; then
            FIRST_ID="$SHADER_ID"
        fi
    else
        echo "❌ Upload failed"
    fi
    
    echo ""
    COUNTER=$((COUNTER + 1))
done

# List all shaders
echo "=== Listing All Shaders ==="
curl -s "$API_BASE/api/shaders?sort_by=rating" | head -500
echo ""

# List by category
echo ""
echo "=== Listing Generative Shaders ==="
curl -s "$API_BASE/api/shaders?category=generative&sort_by=rating" | head -300
echo ""

# Test code fetch if we have an ID
if [ ! -z "$FIRST_ID" ]; then
    echo ""
    echo "=== Fetching Shader Code (ID: $FIRST_ID) ==="
    CODE_RESPONSE=$(curl -s "$API_BASE/api/shaders/$FIRST_ID/code")
    echo "Code preview (first 300 chars):"
    echo "$CODE_RESPONSE" | grep -o '"code":"[^"]*"' | cut -d'"' -f4 | head -c 300
    echo "..."
    
    echo ""
    echo "=== Testing Update ==="
    curl -s -X POST "$API_BASE/api/shaders/$FIRST_ID/update" \
        -F "description=Updated description via test script" \
        -F "tags=generative,updated,tested"
    echo ""
fi

# Health check
echo ""
echo "=== Health Check ==="
curl -s "$API_BASE/api/health" | head -200
echo ""

echo ""
echo "=== Test Complete ==="
echo "Visit: $API_BASE/api/shaders?sort_by=rating"
