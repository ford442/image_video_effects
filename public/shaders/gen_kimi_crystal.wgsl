// ═══════════════════════════════════════════════════════════════
//  Gen Kimi Crystal - Physical Light Transmission with Alpha
//  Category: generative
//  Features: hexagonal grid, crystal growth, icy transmission
//  Animated crystalline structures with physical alpha
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const IOR_ICE: f32 = 1.31;

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

// Fresnel for ice/glass
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);
    
    // ═══════════════════════════════════════════════════════════════
    // Parameters via zoom_params:
    // x: grid density
    // y: crystal purity / transmission
    // z: growth speed
    // w: thickness / depth
    // ═══════════════════════════════════════════════════════════════
    
    let gridDensity = mix(2.0, 5.0, u.zoom_params.x);
    let crystalPurity = mix(0.3, 1.0, u.zoom_params.y);
    let growthSpeed = mix(0.05, 0.3, u.zoom_params.z);
    let crystalThickness = mix(0.1, 1.0, u.zoom_params.w);
    
    // Mouse interaction
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Center and aspect correct
    var p = uv * 2.0 - 1.0;
    p.x *= resolution.x / resolution.y;
    
    // Mouse position in crystal space
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= resolution.x / resolution.y;
    
    // Crystal grid
    let gridScale = gridDensity;
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
    let hexHash = hash(hexId + floor(time * growthSpeed));
    let growthPhase = fract(time * growthSpeed * 0.5 + hexHash * 10.0);
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
    
    // ═══════════════════════════════════════════════════════════════
    // Physical Transmission Calculation
    // ═══════════════════════════════════════════════════════════════
    
    // Crystal mask (1 inside, 0 outside)
    let crystalMask = smoothstep(0.02, -0.02, d);
    
    // Distance from crystal center (for Fresnel)
    let distFromCenter = length(hexLocal) / max(crystalSize, 0.01);
    let cosTheta = 1.0 - distFromCenter * 0.5; // Approximate view angle
    
    // Fresnel for ice
    let F0 = pow((IOR_ICE - 1.0) / (IOR_ICE + 1.0), 2.0);
    let fresnel = fresnelSchlick(max(cosTheta, 0.0), F0);
    
    // Path length through crystal (thicker at center)
    let pathLength = crystalThickness * (1.0 - distFromCenter * 0.3) / crystalPurity;
    
    // Absorption (ice absorbs slightly, more if impure)
    let absorptionCoeff = mix(0.5, 3.0, 1.0 - crystalPurity);
    let absorption = exp(-absorptionCoeff * pathLength * crystalMask);
    
    // Transmission coefficient
    let transmission = absorption * (1.0 - fresnel) * crystalPurity;
    
    // Mix colors based on crystal shape
    var color = bgColor;
    
    // Crystal body with depth layers
    color = mix(color, crystalDeep, crystalMask * 0.5 * (1.0 - distFromCenter * 0.5));
    color = mix(color, crystalBase, crystalMask * interiorPattern * transmission);
    color = mix(color, crystalHighlight, crystalMask * smoothstep(0.0, 0.3, -d) * transmission);
    
    // Edge glow (Fresnel reflection)
    let edgeGlow = smoothstep(0.05, 0.0, abs(d));
    color += goldAccent * edgeGlow * fresnel * 0.8;
    
    // Mouse interaction glow
    color += vec3<f32>(0.5, 0.8, 1.0) * mouseGlow * 0.3 * transmission;
    
    // Sparkles at vertices (specular highlights)
    let vertexDist = sdHexagon(hexLocal, crystalSize * 0.9);
    let sparkle = select(0.0, 1.0, vertexDist > 0.0 && vertexDist < 0.05 && hash(hexId + vec2<f32>(time)) > 0.95);
    color += vec3<f32>(1.0) * sparkle * fresnel;
    
    // Final intensity adjustment
    color = pow(color, vec3<f32>(0.9)) * 1.1;
    
    // Alpha is transmission where crystal exists
    let alpha = mix(1.0, transmission, crystalMask);
    
    textureStore(writeTexture, px, vec4<f32>(color, alpha));
    textureStore(dataTextureA, px, vec4<f32>(color, crystalMask * transmission));
    
    // Depth based on crystal presence
    let depth = crystalMask * 0.5 + 0.5;
    textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
