// ═══════════════════════════════════════════════════════════════════
//  Snow / Blizzard (Depth-Aware)
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09, 2026-11-19
//  Ideas: flake tumble; land fade into the C bank; depth-occluded flake layers; wind-carried bank (saltation)
//  A packing: accumulation scalar in A.r (raw). Display ACES RGB.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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
    // Rescue: HEAD added both time terms, so the pattern (and the flakes) travelled UP and against the
    // wind sign. Subtracting makes flakes fall (+y is down) and blow toward +x when wind > 0.
    let skewed_uv = vec2<f32>(
        uv.x * (1.0 + f32(layer) * 0.1) + turbulence - wind_drift,
        uv.y * (0.8 + f32(layer) * 0.05) - time * layer_speed
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

// d(depth)/d(uv) by central differences (library depth: 1 = near, y grows downward).
fn depth_slope(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    return vec2<f32>(dR - dL, dD - dU) / (2.0 * texel);
}

// ── Idea 3 (depth-occluded flake layers): each flake layer sits on a virtual depth plane (far → near);
// a scene pixel clearly nearer than the plane hides that layer's flakes, so far snow falls BEHIND the
// subject and near snow falls in front. Flat / absent depth (≤ plane) leaves HEAD's flakes untouched.
fn layer_visible(depth: f32, plane: f32) -> f32 {
    return 1.0 - 0.85 * smoothstep(plane + 0.04, plane + 0.22, depth);
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
    // ── Idea 3: far / mid / near layer planes at 0.40 / 0.65 / 0.90 (depth 1 = near)
    snow_acc += snow_layer(uv, 0u, speed, density * 0.7, wind, time) * 0.6 * layer_visible(depth, 0.40);
    snow_acc += snow_layer(uv, 1u, speed, density * 0.9, wind, time) * 0.8 * layer_visible(depth, 0.65);
    snow_acc += snow_layer(uv, 2u, speed, density, wind, time) * 1.0 * layer_visible(depth, 0.90);
    // Idea 2 — land fade: flakes settle into the existing bank
    snow_acc *= 1.0 - prev_snow * 0.85;

    var accumulated_snow = 0.0;
    let slope = depth_slope(uv, texel);
    // HEAD's normal, value-identical (-(dR-dL)*0.5 == -slope.x*texel.x): lighting is unchanged.
    let normal = normalize(vec3<f32>(-slope.x * texel.x, -slope.y * texel.y, 1.0));
    if (accumulation_amt > 0.01) {
        // Rescue: HEAD thresholded the per-texel-scaled normal.y (≈0 on real depth maps) and with the
        // wrong sign (depth 1 = near, so a floor has normal.y < 0): Accumulation was dead. Use the
        // per-uv slope with a fixed relief gain and select UP-facing (-y) surfaces.
        let relief = normalize(vec3<f32>(-slope * 1.5, 1.0));
        let up_factor = smoothstep(0.3, 0.7, -relief.y);
        let d_up = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
        let edge_factor = 1.0 - smoothstep(0.01, 0.05, abs(depth - d_up));
        let height_factor = smoothstep(0.0, 0.5, depth);
        let accumulation_factor = up_factor * edge_factor * height_factor * accumulation_amt;
        // ── Idea 4: wind-carried bank (saltation). Wind lifts settled snow off exposed lips and drops it
        // downwind: blend the bank with its upwind neighbour (exact C load, 1 px along sign(wind)) at a
        // rate ∝ |wind|. wind = 0 → carried == prev_snow, exactly HEAD.
        let upwind_px = vec2<i32>(select(-1, 1, wind > 0.0), 0);
        let upwind_bank = stateAt(pixel - upwind_px, dims).r;
        let carried = mix(prev_snow, upwind_bank, clamp(abs(wind) * 0.045, 0.0, 0.12));
        accumulated_snow = clamp(carried + accumulation_factor * 0.01 - melt_rate, 0.0, 0.8);
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
