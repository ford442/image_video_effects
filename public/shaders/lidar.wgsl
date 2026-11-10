// ═══════════════════════════════════════════════════════════════════
//  LiDAR Scanner
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-11-10
//  Ideas: honest A echo; range ticks along the beam; incidence-angle return
//         intensity; dual-return ghost beam
//  A packing: echo in A.r (was B). Display ACES RGB.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sobel_edge(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    let tl = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).r;
    let tc = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let tr = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, -texel.y), 0.0).r;
    let ml = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
    let mr = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let bl = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, texel.y), 0.0).r;
    let bc = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let br = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, texel.y), 0.0).r;
    let sum_x = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
    let sum_y = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
    return length(vec2<f32>(sum_x, sum_y));
}

fn scan_pattern(uv: vec2<f32>, origin: vec2<f32>, time: f32, speed: f32, mode: u32) -> f32 {
    if (mode == 1u) {
        let dist = length(uv - origin);
        return fract((dist - time * speed * 0.5));
    } else if (mode == 2u) {
        let delta = uv - origin;
        let angle = atan2(delta.y, delta.x) / (2.0 * 3.14159);
        let radius = length(delta);
        return fract(angle + time * speed * 0.2 + radius * 0.5);
    }
    return fract(time * speed);
}

fn point_cloud(uv: vec2<f32>, depth: f32, time: f32) -> f32 {
    let grid_size = 8.0;
    let cell = floor(uv * grid_size);
    let pos = fract(uv * grid_size);
    let jitter = hash12(cell) * 0.5;
    let depth_jitter = fract(depth + jitter + time * 0.1);
    let point_size = 0.3 * (1.0 - depth);
    let d = distance(pos, vec2<f32>(0.5));
    return smoothstep(point_size, point_size * 0.5, d) * (1.0 - depth_jitter);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let held = u.zoom_config.w > 0.5;
    let mouseRad = length(mouse - vec2<f32>(0.5));
    // Held = radial; held + cursor near the rim = spiral. Default linear.
    let scan_mode = select(0u, select(1u, 2u, mouseRad > 0.38), held);

    let scan_speed = u.zoom_params.x * 0.6 * (1.0 + bass * 0.2);
    let beam_width = mix(0.005, 0.15, u.zoom_params.y);
    let contour_freq = mix(5.0, 80.0, u.zoom_params.z);
    let edge_sensitivity = mix(0.002, 0.05, u.zoom_params.w);
    let persistence = 0.62 + treble * 0.25;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

    let edge_val = sobel_edge(uv, texel);
    let is_edge = smoothstep(edge_sensitivity, edge_sensitivity * 2.0, edge_val);
    let contour = 0.5 + 0.5 * sin(depth * contour_freq + time * 0.1);
    let is_contour = smoothstep(0.92, 1.0, contour);

    let scan_pos = scan_pattern(uv, mouse, time, scan_speed, scan_mode);
    let dist_to_scan = abs(depth - scan_pos);
    let in_beam = 1.0 - smoothstep(0.0, beam_width, dist_to_scan);
    let beam_falloff = 1.0 - smoothstep(0.0, beam_width * 2.0, dist_to_scan);
    // Idea 3 — incidence-angle return: grazing surfaces (steep depth slope) return less.
    let incidence = 1.0 / (1.0 + edge_val * 18.0);
    // Idea 4 — dual-return ghost: a weaker second echo trails the first slice.
    let ghostPos = fract(scan_pos - 0.12 - beam_width);
    let ghost = (1.0 - smoothstep(0.0, beam_width * 0.7, abs(depth - ghostPos))) * 0.45;
    let points = point_cloud(uv, depth, time) * in_beam * mix(0.35, 1.0, incidence);

    let prev_echo = textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
    let new_echo = in_beam * (1.0 - depth);
    let echo = max(prev_echo * (1.0 - persistence * 0.1), new_echo);
    // Idea 1 — echo lives in A (HEAD wrote B and never A)
    textureStore(dataTextureA, pixel, vec4<f32>(echo, in_beam, dist_to_scan, 1.0));

    // HEAD smoothstep(0.48,0.5,fract) lit half of every cell; thin lines now.
    let grid_line = 1.0 - smoothstep(0.0, 0.06, abs(fract(uv.x * 20.0) - 0.5)) +
                    1.0 - smoothstep(0.0, 0.06, abs(fract(uv.y * 20.0) - 0.5));
    let grid = grid_line * 0.3 * (1.0 - depth * 0.5);

    let height_color = mix(vec3<f32>(0.0, 0.2, 0.8), vec3<f32>(0.0, 1.0, 0.8), depth);
    let edge_color = vec3<f32>(0.0, 0.9, 1.0) * (1.0 + beam_falloff);
    let pulse = sin(time * 10.0) * 0.3 + 0.7;
    let beam_color = vec3<f32>(1.0, 0.1, 0.1) * pulse;

    // Idea 2 — range ticks along the beam
    let tick = step(0.88, fract(dist_to_scan / max(beam_width * 1.8, 0.002))) * in_beam;

    var hdr = height_color * 0.3;
    hdr += grid;
    hdr = mix(hdr, edge_color * 0.5, is_contour);
    hdr = mix(hdr, edge_color, is_edge * (0.5 + beam_falloff * 0.5));
    hdr += beam_color * in_beam * 0.5 * mix(0.4, 1.2, incidence);
    hdr += vec3<f32>(0.6, 0.05, 0.25) * ghost * incidence;
    hdr = mix(hdr, beam_color, points);
    hdr += vec3<f32>(0.5, 0.2, 0.0) * echo * persistence;
    hdr += vec3<f32>(1.0, 0.85, 0.4) * tick * 0.55;
    hdr += hash12(uv * 100.0 + time) * 0.05 * (1.0 - depth);

    let mapped = aces(hdr);
    let alpha = clamp(srcA * 0.25 + in_beam * 0.4 + echo * 0.25 + is_edge * 0.2 + tick * 0.2 + ghost * 0.15, 0.0, 1.0);
    textureStore(writeTexture, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
