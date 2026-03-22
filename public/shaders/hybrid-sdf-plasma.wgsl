// ═══════════════════════════════════════════════════════════════════
//  Hybrid SDF Plasma Field
//  Category: generative
//  Features: hybrid, raymarching, sdf, plasma-noise, palette-cycling
//  Chunks From: gen-xeno-botanical-synth-flora.wgsl (sdSphere, sdSmoothUnion, fbm3, palette)
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Raymarched SDF scene with plasma noise displacement and
//           dynamic palette-based coloring
// ═══════════════════════════════════════════════════════════════════

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

// ═══ CHUNK 1: hash3 (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

// ═══ CHUNK 2: noise3 (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - 2.0 * f);
    return mix(
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), f2.x),
            mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), f2.x), f2.y),
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), f2.x),
            mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), f2.x), f2.y),
        f2.z);
}

// ═══ CHUNK 3: fbm3 (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn fbm3(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        f += w * noise3(pos);
        pos *= 2.0;
        w *= 0.5;
    }
    return f;
}

// ═══ CHUNK 4: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ═══ CHUNK 5: sdSphere (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

// ═══ CHUNK 6: sdSmoothUnion (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn sdSmoothUnion(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// ═══ HYBRID LOGIC: SDF Scene with Plasma Displacement ═══
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p: vec3<f32>, time: f32, plasmaScale: f32) -> f32 {
    // Plasma noise displacement
    let plasma = fbm3(p * plasmaScale + time * 0.3);
    
    // Sphere field with displacement
    var d = 1000.0;
    for (var i: i32 = 0; i < 4; i++) {
        let fi = f32(i);
        let offset = vec3<f32>(
            sin(time * 0.5 + fi * 1.5) * 1.5,
            cos(time * 0.3 + fi * 1.2) * 1.0,
            sin(time * 0.4 + fi * 0.8) * 1.5
        );
        let sphere = sdSphere(p + offset, 0.6 + plasma * 0.3);
        d = sdSmoothUnion(d, sphere, 0.5);
    }
    
    return d;
}

fn calcNormal(p: vec3<f32>, time: f32, plasmaScale: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize(
        e.xyy * map(p + e.xyy, time, plasmaScale) +
        e.yyx * map(p + e.yyx, time, plasmaScale) +
        e.yxy * map(p + e.yxy, time, plasmaScale) +
        e.xxx * map(p + e.xxx, time, plasmaScale)
    );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let time = u.config.x;
    
    // Parameters
    let plasmaScale = mix(0.5, 3.0, u.zoom_params.x);      // x: Plasma detail
    let colorCycleSpeed = mix(0.1, 1.0, u.zoom_params.y);  // y: Color cycling
    let glowStrength = u.zoom_params.z * 2.0;              // z: Glow intensity
    let marchSteps = i32(mix(30.0, 80.0, u.zoom_params.w)); // w: Raymarch quality
    
    // UV setup
    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    
    // Camera
    var ro = vec3<f32>(0.0, 0.0, -4.0);
    ro.xy = rot2(time * 0.2) * ro.xy;
    var rd = normalize(vec3<f32>(uv, 1.0));
    rd.xz = rot2(time * 0.1) * rd.xz;
    
    // Raymarch
    var t = 0.0;
    var p = ro;
    var hit = false;
    for (var i: i32 = 0; i < marchSteps; i++) {
        p = ro + rd * t;
        let d = map(p, time, plasmaScale);
        if (d < 0.01) {
            hit = true;
            break;
        }
        if (t > 20.0) { break; }
        t += d * 0.7;
    }
    
    // Coloring
    var color = vec3<f32>(0.02, 0.02, 0.05);
    var alpha = 0.3;
    
    if (hit) {
        let n = calcNormal(p, time, plasmaScale);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = clamp(dot(n, l), 0.0, 1.0);
        
        // Palette coloring based on position and time
        let t_param = p.y * 0.2 + time * colorCycleSpeed;
        let baseColor = palette(t_param, 
            vec3<f32>(0.5), 
            vec3<f32>(0.5), 
            vec3<f32>(1.0, 1.0, 0.5), 
            vec3<f32>(0.8, 0.9, 0.3)
        );
        
        color = baseColor * (0.3 + diff * 0.7);
        
        // Glow based on plasma
        let plasma = fbm3(p * plasmaScale + time * 0.3);
        color += vec3<f32>(0.3, 0.6, 1.0) * plasma * glowStrength;
        
        alpha = mix(0.7, 1.0, diff);
    }
    
    // Fog
    color = mix(color, vec3<f32>(0.02, 0.02, 0.05), 1.0 - exp(-0.1 * t));
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(1.0 - t / 20.0, 0.0, 0.0, 0.0));
}
