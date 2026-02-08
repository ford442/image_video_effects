@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Kimi Crystal - Growing Crystal Formations
// Animated crystalline structures that grow and refract light

fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rotate(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Signed distance to hexagon
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    let q = abs(p);
    let h = vec2<f32>(dot(k.xy, q), q.y);
    return length(max(h - vec2<f32>(k.z * r, r * 0.5), vec2<f32>(0.0))) + min(max(h.x - k.z * r, h.y - r * 0.5), 0.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);
    
    // Mouse interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Center and aspect correct
    var p = uv * 2.0 - 1.0;
    p.x *= resolution.x / resolution.y;
    
    // Mouse position in crystal space
    let mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= resolution.x / resolution.y;
    
    // Crystal grid
    let gridScale = 3.0;
    var gridUV = p * gridScale;
    
    // Hexagonal grid
    let hexSize = 0.5;
    let hexSpacing = vec2<f32>(1.732, 2.0) * hexSize;
    
    // Calculate hex grid coordinates
    let hexUV = vec2<f32>(gridUV.x / hexSpacing.x, gridUV.y / hexSpacing.y);
    let hexId = floor(hexUV);
    let hexFract = fract(hexUV);
    
    // Offset every other row
    var offset = vec2<f32>(0.0);
    if (i32(hexId.y) % 2 == 1) {
        offset.x = 0.5;
    }
    
    // Local hex coordinate
    var hexLocal = hexFract - vec2<f32>(0.5);
    if (i32(hexId.y) % 2 == 1) {
        hexLocal.x -= 0.5;
    }
    
    // Animated crystal growth
    let hexHash = hash(hexId + floor(time * 0.2));
    let growthPhase = fract(time * 0.1 + hexHash * 10.0);
    let crystalSize = smoothstep(0.0, 0.8, growthPhase) * hexSize * 0.8;
    
    // Mouse influence on nearby crystals
    let mouseHex = mousePos * gridScale / hexSpacing;
    let distToMouseHex = length(hexUV + offset - mouseHex);
    let mouseGlow = smoothstep(2.0, 0.0, distToMouseHex) * mouseDown;
    
    // Rotate crystal based on time and mouse
    let rotation = time * 0.2 + hexHash * 6.28 + mouseGlow * 2.0;
    hexLocal = rotate(hexLocal, rotation);
    
    // Distance to crystal edge
    let d = sdHexagon(hexLocal, crystalSize);
    
    // Crystal interior pattern
    let interiorPattern = sin(length(hexLocal) * 20.0 - time * 2.0) * 0.5 + 0.5;
    
    // Color palette - icy blues and warm gold accents
    let bgColor = vec3<f32>(0.02, 0.03, 0.05);
    let crystalBase = vec3<f32>(0.4, 0.7, 0.9);      // Ice blue
    let crystalHighlight = vec3<f32>(0.8, 0.95, 1.0); // White highlight
    let crystalDeep = vec3<f32>(0.1, 0.3, 0.6);      // Deep blue
    let goldAccent = vec3<f32>(1.0, 0.8, 0.3);       // Gold
    
    // Mix colors based on crystal shape
    var color = bgColor;
    
    // Crystal body
    let crystalMask = smoothstep(0.02, -0.02, d);
    color = mix(color, crystalDeep, crystalMask * 0.5);
    color = mix(color, crystalBase, crystalMask * interiorPattern);
    color = mix(color, crystalHighlight, crystalMask * smoothstep(0.0, 0.3, -d));
    
    // Edge glow
    let edgeGlow = smoothstep(0.05, 0.0, abs(d));
    color += goldAccent * edgeGlow * 0.5;
    
    // Mouse interaction glow
    color += vec3<f32>(0.5, 0.8, 1.0) * mouseGlow * 0.3;
    
    // Sparkles at vertices
    let vertexDist = sdHexagon(hexLocal, crystalSize * 0.9);
    let sparkle = select(0.0, 1.0, vertexDist > 0.0 && vertexDist < 0.05 && hash(hexId + vec2<f32>(time)) > 0.95);
    color += vec3<f32>(1.0) * sparkle;
    
    // Final intensity adjustment
    color = pow(color, vec3<f32>(0.9)) * 1.1;
    
    textureStore(writeTexture, px, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, px, vec4<f32>(color, crystalMask, 0.0, 1.0));
}
