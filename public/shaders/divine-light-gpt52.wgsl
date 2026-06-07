// ═══════════════════════════════════════════════════════════════════
//  Divine Light Cathedral gpt52
//  Category: lighting-effects
//  Features: mouse-driven, volumetric, atmospheric, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PHI = 1.61803398874989484820;

fn hash21(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
    return fract(vec2<f32>(n, n * PHI)) - 0.5;
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i).x, hash21(i + vec2<f32>(1.0, 0.0)).x, u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)).x, hash21(i + vec2<f32>(1.0, 1.0)).x, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5;
    var s = 0.0;
    var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * vnoise(q);
        q = q * 2.02;
        a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2)),
                       fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0 * r);
}

fn voronoiF2minusF1(p: vec2<f32>) -> f32 {
    var F1 = 1e9;
    var F2 = 1e9;
    let ip = floor(p);
    for (var i = -1; i <= 1; i = i + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            let n = ip + vec2<f32>(f32(i), f32(j));
            let d = length(p - n - hash21(n));
            let isCloser = f32(d < F1);
            let isSecond = f32(d < F2) * (1.0 - isCloser);
            F2 = mix(F2, F1, isCloser);
            F2 = mix(F2, d, isSecond);
            F1 = mix(F1, d, isCloser);
        }
    }
    return F2 - F1;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let nx = warpedFBM(p + vec2<f32>(0.0, eps), t) - warpedFBM(p - vec2<f32>(0.0, eps), t);
    let ny = warpedFBM(p + vec2<f32>(eps, 0.0), t) - warpedFBM(p - vec2<f32>(eps, 0.0), t);
    return vec2<f32>(nx, -ny) / max(2.0 * eps, 1e-6);
}

fn hgPhase(cosTheta: f32, g: f32) -> f32 {
    let gg = g * g;
    return (1.0 - gg) / max(pow(1.0 + gg - 2.0 * g * cosTheta, 1.5), 1e-6);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    var center = u.zoom_config.yz;
    center = mix(center, vec2<f32>(0.5, 0.5), f32(center.x < 0.0));
    
    let intensity = u.zoom_params.x * 2.2;
    let decay = 0.88 + u.zoom_params.y * 0.11;
    let density = mix(0.6, 1.4, u.zoom_params.z);
    let threshold = u.zoom_params.w;
    let audioBoost = 1.0 + bass * 0.35;
    
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var dir = (center - uv) * vec2<f32>(aspect, 1.0);
    let steps = 48;
    let delta = dir / max(f32(steps), 1.0) * density;
    var accum = vec3<f32>(0.0);
    var weight = 1.0;
    var current = uv;
    let dirLen = length(dir);
    
    for (var i = 0; i < steps; i = i + 1) {
        let sample = textureSampleLevel(readTexture, u_sampler, current, 0.0).rgb;
        let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
        let contrib = select(0.0, 1.0, luma > threshold);
        let stepDir = current - uv;
        let cosTheta = dot(dir, stepDir) / max(dirLen * length(stepDir), 1e-6);
        let phase = hgPhase(cosTheta, 0.3);
        accum = accum + sample * weight * intensity * audioBoost * contrib * phase;
        let dust = warpedFBM(current * resolution * 0.015 + vec2<f32>(time * 0.4, -time * 0.25), time);
        let cell = voronoiF2minusF1(current * 8.0 + time * 0.1);
        accum = accum + vec3<f32>(dust * 0.015 + cell * 0.008) * weight * intensity * audioBoost;
        let flow = curl2D(current * 3.0 + f32(i) * 0.05, time);
        current = current + delta + flow * delta * 0.3;
        weight = weight * decay;
    }
    
    accum = accum * (1.0 / max(f32(steps), 1.0)) * 0.9;
    accum = accum * vec3<f32>(1.1, 1.05, 0.95);
    let dist = length((uv - center) * vec2<f32>(aspect, 1.0));
    let halo = smoothstep(0.5, 0.0, dist) * intensity * 0.35 * audioBoost;
    let finalRGB = original.rgb + accum + vec3<f32>(halo * 1.1, halo, halo * 0.8);
    let effectLuma = dot(accum, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(original.a + effectLuma * 0.5 + halo * 0.3, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalRGB, alpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
