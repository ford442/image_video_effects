// ═══════════════════════════════════════════════════════════════════
//  elastic-chromatic-explosion
//  Category: advanced-hybrid
//  Features: chromatic-lag, prism-explosion, mouse-driven, temporal
//  Complexity: High
//  Chunks From: elastic-chromatic.wgsl, mouse-chromatic-explosion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Elastic chromatic lag meets prismatic explosion. Red and blue
//  channels trail behind with temporal EMA while the mouse acts as
//  a chromatic prism. Ripples launch spectral shockwaves that
//  interact with the elastic lag to create persistent rainbow trails.
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

fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    let baseLagR = u.zoom_params.x;
    let baseLagB = u.zoom_params.y;
    let prismStrength = mix(0.02, 0.12, u.zoom_params.z);
    let saturationBoost = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Distance from mouse for influence
    let dist = distance((uv - mousePos) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    let influence = smoothstep(0.5, 0.0, dist) * mouseDown;

    // Effective lag with mouse influence (mouse slows time)
    let lagR = clamp(baseLagR + influence, 0.0, 0.99);
    let lagB = clamp(baseLagB + influence * 0.5, 0.0, 0.99);

    // Read history
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Prism displacement from mouse
    let rUV = prismDisplace(uv, mousePos, -1.0, prismStrength);
    let gUV = prismDisplace(uv, mousePos, 0.0, prismStrength);
    let bUV = prismDisplace(uv, mousePos, 1.0, prismStrength);

    // Ripple chromatic shockwaves
    let rippleCount = min(u32(u.config.y), 50u);
    var rOffset = vec2<f32>(0.0);
    var gOffset = vec2<f32>(0.0);
    var bOffset = vec2<f32>(0.0);

    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.5) {
            let rPos = ripple.xy;
            let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
            let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
            let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
            let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
            let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
            rOffset += dir * rWave * 0.03;
            gOffset += dir * wave * 0.03;
            bOffset += dir * bWave * 0.03;
        }
    }

    let intensity = 1.0 + mouseDown * 1.5;

    // Sample current with prism + ripple
    let currR = textureSampleLevel(readTexture, u_sampler, rUV + rOffset * intensity, 0.0).r;
    let currG = textureSampleLevel(readTexture, u_sampler, gUV + gOffset * intensity, 0.0).g;
    let currB = textureSampleLevel(readTexture, u_sampler, bUV + bOffset * intensity, 0.0).b;

    // Apply elastic lag: blend current with history
    let newR = mix(currR, history.r, lagR);
    let newB = mix(currB, history.b, lagB);
    let newG = currG; // Green stays instant as anchor

    var color = vec3<f32>(newR, newG, newB);

    // Saturation boost
    let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(vec3<f32>(lum), color, 1.0 + saturationBoost);

    // Spectral glow near mouse
    let glow = exp(-dist * dist * 100.0) * prismStrength * 10.0;
    color += vec3<f32>(0.5, 0.3, 0.8) * glow;

    let finalColor = vec4<f32>(color, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
