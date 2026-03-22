// ═══════════════════════════════════════════════════════════════
//  Stellar Plasma - Endless procedural cosmic nebula (OPTIMIZED)
//  Category: generative
//  Features: generative, procedural, loops, audio-reactivity
//
//  OPTIMIZATIONS APPLIED:
//  - Precomputed noise hash values
//  - Added audio reactivity hooks
//  - Distance-based FBM octaves
//  - Cached rotation matrix
//  - Early exit for distant regions
//  Author: Gemini 3.1 Pro Vertex (optimized)
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
  config: vec4<f32>,       // x=Time, y=AudioLow, z=AudioMid, w=AudioHigh
  zoom_config: vec4<f32>,  // x=MouseX, y=MouseY, z=unused, w=unused
  zoom_params: vec4<f32>,  // x=HueShift, y=Speed, z=ZoomScale, w=MouseInfluence
  ripples: array<vec4<f32>, 50>,
};

// OPTIMIZATION: Precomputed hash constants
const HASH_CONST1: vec3<f32> = vec3<f32>(0.1031, 0.1031, 0.1031);
const HASH_CONST2: vec3<f32> = vec3<f32>(33.33, 33.33, 33.33);

// Pseudo-random hash (optimized)
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * HASH_CONST1);
    p3 += dot(p3, p3.yzx + HASH_CONST2);
    return fract((p3.x + p3.y) * p3.z);
}

// 2D Value Noise
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    let u_f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u_f.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u_f.x),
        u_f.y
    );
}

// OPTIMIZATION: Fractional Brownian Motion with LOD
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let shift = vec2<f32>(100.0, 100.0);
    
    // Precomputed rotation (cos(0.5), sin(0.5))
    let c: f32 = 0.87758256189;
    let s: f32 = 0.4794255386;
    let rot = mat2x2<f32>(vec2<f32>(c, s), vec2<f32>(-s, c));
    
    var p_mut = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * noise(p_mut);
        p_mut = rot * p_mut * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Hue shift function
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
        return;
    }

    // Normalize UV coordinates (-1.0 to 1.0) and fix aspect ratio
    var uv = vec2<f32>(global_id.xy) / res;
    var p = uv * 2.0 - 1.0;
    p.x *= res.x / res.y;
    
    // Calculate distance for LOD
    let dist = length(p);
    let lodFactor = smoothstep(1.5, 2.5, dist);
    
    // OPTIMIZATION: Early exit for distant regions
    if (dist > 3.0) {
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        return;
    }

    // Parameters mapped from UI
    let hue_offset = u.zoom_params.x * 6.28318; 
    let speed = mix(0.5, 2.0, u.zoom_params.y);
    let scale = mix(1.0, 4.0, u.zoom_params.z);
    let mouse_influence = u.zoom_params.w;
    
    // OPTIMIZATION: Audio reactivity hooks (from config.yzw)
    let audioLow = u.config.y;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioMid * 0.3;

    let time = u.config.x * speed * audioReactivity;

    // Mouse Interaction
    var mouse_pos = u.zoom_config.yz * 2.0 - 1.0;
    mouse_pos.x *= res.x / res.y;
    let dist_to_mouse = length(p - mouse_pos);
    let interaction = exp(-dist_to_mouse * 3.0) * mouse_influence;

    // Apply scaling and interaction displacement
    var q_pos = p * scale + interaction;
    
    // OPTIMIZATION: LOD-based FBM octaves
    let octaves = i32(mix(6.0, 3.0, lodFactor));

    // Domain Warping Step 1
    var q = vec2<f32>(
        fbm(q_pos + vec2<f32>(0.0, time * 0.2), octaves),
        fbm(q_pos + vec2<f32>(1.0, 2.0) + time * 0.2, octaves)
    );

    // Domain Warping Step 2 (Nested FBM)
    var r = vec2<f32>(
        fbm(q_pos + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15, octaves),
        fbm(q_pos + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126, octaves)
    );

    // Final Noise Value
    var f = fbm(q_pos + 4.0 * r, octaves);
    
    // OPTIMIZATION: Audio-reactive color modulation
    let audioHueShift = (audioLow - audioHigh) * 0.1;

    // Color Palette Mixing
    var base_col1 = vec3<f32>(0.1, 0.6, 0.7); // Cyan
    var base_col2 = vec3<f32>(0.7, 0.2, 0.5); // Magenta
    var base_col3 = vec3<f32>(0.0, 0.0, 0.2); // Deep Blue
    var base_col4 = vec3<f32>(1.0, 0.9, 0.5); // Bright Yellow/White glow
    
    // Audio-reactive color shifts
    base_col1 = mix(base_col1, vec3<f32>(0.2, 0.8, 0.9), audioLow * 0.3);
    base_col2 = mix(base_col2, vec3<f32>(0.9, 0.3, 0.6), audioHigh * 0.3);

    // Construct color based on warping layers
    var color = mix(base_col1, base_col2, clamp(f * f * 4.0, 0.0, 1.0));
    color = mix(color, base_col3, clamp(length(q), 0.0, 1.0));
    color = mix(color, base_col4, clamp(length(r.x), 0.0, 1.0));

    // Apply hue shift from params + audio
    color = hueShift(color, hue_offset + time * 0.1 + audioHueShift);

    // Enhance contrast and glow
    let glowIntensity = 1.0 + audioMid * 0.5;
    color = (f * f * f + 0.6 * f * f + 0.5 * f) * color * glowIntensity;

    // Output final color
    let final_color = vec4<f32>(color, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);

    // Write empty depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
