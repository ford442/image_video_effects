// ═══════════════════════════════════════════════════════════════════
//  Snow / Blizzard (Depth-Aware)
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: flake tumble; land fade into the C bank
//  A packing: accumulation scalar in A.r (raw). Display ACES RGB.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hexagon_dist(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    var pa = abs(p);
    pa -= 2.0 * min(dot(k.xy, pa), 0.0) * k.xy;
    pa -= vec2<f32>(clamp(pa.x, -k.z * r, k.z * r), r);
    return length(pa) * sign(pa.y);
}

fn snowflake(uv: vec2<f32>, seed: f32, size: f32, tumble: f32) -> f32 {
    let center = vec2<f32>(0.5);
    let ang = seed * 6.28 + tumble;
    let cs = cos(ang);
    let sn = sin(ang);
    let rot = mat2x2<f32>(cs, -sn, sn, cs);
    let p = rot * (uv - center);
    let d = hexagon_dist(p * 2.0, size);
    let branch = 1.0 - smoothstep(0.0, 0.1, abs(p.x) - size * 0.3) *
                         smoothstep(0.0, 0.1, abs(p.y) - size * 0.8);
    return smoothstep(0.0, 0.02, -d) * branch;
}

fn snow_layer(uv: vec2<f32>, layer: u32, speed: f32, density: f32, wind: f32, time: f32) -> f32 {
    let seed = f32(layer) * 3.7;
    let layer_speed = speed * (1.0 + f32(layer) * 0.2);
    let gust = sin(time * 0.1 + seed) * 0.5 + 0.5;
    let turbulence = sin(uv.y * 8.0 + time * 2.0 + seed) * 0.15 * wind * gust;
    let wind_drift = time * layer_speed * wind * 0.3;
    let skewed_uv = vec2<f32>(
        uv.x * (1.0 + f32(layer) * 0.1) + turbulence + wind_drift,
        uv.y * (0.8 + f32(layer) * 0.05) + time * layer_speed
    );
    let cell_size = vec2<f32>(40.0, 40.0) / (1.0 + f32(layer) * 0.3);
    let cell = floor(skewed_uv * cell_size);
    let pos = fract(skewed_uv * cell_size);
    let rand = hash13(vec3<f32>(cell, seed));
    if (rand > density) { return 0.0; }
    let flake_size = 0.3 + rand * 0.4;
    // Idea 1 — tumble: hex arms spin with fall time and seed
    let tumble = time * (1.4 + rand * 3.2) * (0.4 + f32(layer) * 0.2);
    let flake = snowflake(pos, rand, flake_size, tumble);
    let depth_fade = 1.0 - f32(layer) * 0.3;
    return flake * depth_fade;
}

fn calculate_normal(uv: vec2<f32>, texel: vec2<f32>) -> vec3<f32> {
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    return normalize(vec3<f32>(-(dR - dL) * 0.5, -(dD - dU) * 0.5, 1.0));
}

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;
    let dims = vec2<i32>(resolution);
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

    let speed = max(0.01, u.zoom_params.x * 2.0) * (1.0 + bass * 0.25);
    let density = clamp(u.zoom_params.y * 0.5 * (1.0 + treble * 0.2), 0.0, 1.0);
    let wind = (u.zoom_params.z - 0.5) * 4.0 + (mouse.x - 0.5) * 1.4;
    let accumulation_amt = u.zoom_params.w;
    let melt_rate = 0.001;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let prev_snow = stateAt(pixel, dims).r;

    var snow_acc = 0.0;
    snow_acc += snow_layer(uv, 0u, speed, density * 0.7, wind, time) * 0.6;
    snow_acc += snow_layer(uv, 1u, speed, density * 0.9, wind, time) * 0.8;
    snow_acc += snow_layer(uv, 2u, speed, density, wind, time) * 1.0;
    // Idea 2 — land fade: flakes settle into the existing bank
    snow_acc *= 1.0 - prev_snow * 0.85;

    var accumulated_snow = 0.0;
    let normal = calculate_normal(uv, texel);
    if (accumulation_amt > 0.01) {
        let up_factor = smoothstep(0.3, 0.7, normal.y);
        let d_up = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
        let edge_factor = 1.0 - smoothstep(0.01, 0.05, abs(depth - d_up));
        let height_factor = smoothstep(0.0, 0.5, depth);
        let accumulation_factor = up_factor * edge_factor * height_factor * accumulation_amt;
        accumulated_snow = clamp(prev_snow + accumulation_factor * 0.01 - melt_rate, 0.0, 0.8);
    }

    textureStore(dataTextureA, pixel, vec4<f32>(accumulated_snow, snow_acc, 0.0, 1.0));

    let snow_color = vec3<f32>(0.92, 0.95, 1.0);
    let light_dir = normalize(vec3<f32>(0.3, 0.8, 0.5));
    let snow_lighting = max(0.2, dot(normal, light_dir));
    var hdr = base_color.rgb;
    hdr = mix(hdr, snow_color, clamp(snow_acc * 0.9, 0.0, 1.0));
    hdr = mix(hdr, snow_color * snow_lighting, accumulated_snow);
    let sparkle = pow(max(snow_acc, 0.0), 3.0) * treble * 0.35;
    hdr += vec3<f32>(sparkle);
    let mapped = aces(hdr);
    let alpha = clamp(base_color.a * 0.45 + snow_acc * 0.4 + accumulated_snow * 0.5, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
