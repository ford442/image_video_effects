// ═══════════════════════════════════════════════════════════════════
//  Aetherial Plasma Loom
//  Category: generative
//  Features: audio-reactive, mouse-driven, temporal-feedback, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: counter-woven plasma ribbons; reconnection knots with paired exhaust
//  A packing: ACES display RGBA
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Density, .y = Flow Speed, .z = Twist, .w = Core Brightness
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash13(p3: vec3<f32>) -> f32 {
    var p = fract(p3 * 0.1031);
    p += dot(p, p.yzx + vec3<f32>(33.33));
    return fract((p.x + p.y) * p.z);
}

// 3D noise (value noise)
fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    let res = mix(
        mix(mix(hash13(p), hash13(p + vec3<f32>(1.0, 0.0, 0.0)), f2.x),
            mix(hash13(p + vec3<f32>(0.0, 1.0, 0.0)), hash13(p + vec3<f32>(1.0, 1.0, 0.0)), f2.x), f2.y),
        mix(mix(hash13(p + vec3<f32>(0.0, 0.0, 1.0)), hash13(p + vec3<f32>(1.0, 0.0, 1.0)), f2.x),
            mix(hash13(p + vec3<f32>(0.0, 1.0, 1.0)), hash13(p + vec3<f32>(1.0, 1.0, 1.0)), f2.x), f2.y), f2.z
    );
    return res;
}

fn fbm3(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        f += amp * noise3(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return f;
}

fn rotZ(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct LoomSample {
    distance: f32,
    ribbon_a: f32,
    ribbon_b: f32,
    knot: f32,
    exhaust_pair: vec2<f32>,
}

fn sampleLoom(p: vec3<f32>) -> LoomSample {
    var pos = p;

    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 2.0, -(u.zoom_config.z - 0.5) * 2.0, 0.0);
    let d_mouse = length(pos.xy - mouse_pos.xy);
    let twist_amount = u.zoom_params.z;
    let angle = twist_amount / (d_mouse + 0.1);

    if (u.zoom_config.w > 0.0) {
        let rz = rotZ(angle);
        let xy = rz * pos.xy;
        pos = vec3<f32>(xy.x, xy.y, pos.z);
    }

    let flow = u.config.x * u.zoom_params.y;
    let warp = fbm3(pos * 0.5 + vec3<f32>(0.0, 0.0, flow));
    let radius = max(length(pos.xy), 0.0001);
    let theta = atan2(pos.y, pos.x);
    let pitch = 0.7 + twist_amount * 0.32;

    // Idea 1 — Counter-woven plasma ribbons: opposite helical phases form
    // the loom's crossing warp and weft while retaining the FBM-warped shell.
    let phase_a = theta - (pos.z * pitch + flow + warp * 0.55);
    let phase_b = theta - (-pos.z * pitch + flow * 0.73 + PI * 0.5 - warp * 0.55);
    let radial_a = abs(radius - (0.92 + (warp - 0.5) * 0.24));
    let radial_b = abs(radius - (1.04 - (warp - 0.5) * 0.18));
    let across_a = abs(sin(phase_a)) * radius * 0.55;
    let across_b = abs(sin(phase_b)) * radius * 0.55;
    let ribbon_a = length(vec2<f32>(radial_a, across_a)) - 0.085;
    let ribbon_b = length(vec2<f32>(radial_b, across_b)) - 0.075;

    // Idea 2 — Reconnection knots: anti-aligned crossings compress to a hot
    // knot, then pulse cyan/magenta exhaust along the two ribbon tangents.
    let tangent_a = normalize(vec2<f32>(pitch, 1.0));
    let tangent_b = normalize(vec2<f32>(-pitch, 1.0));
    let anti_alignment = smoothstep(0.0, 0.8, -dot(tangent_a, tangent_b));
    let near_a = exp(-abs(ribbon_a) * 30.0);
    let near_b = exp(-abs(ribbon_b) * 30.0);
    let knot = near_a * near_b * anti_alignment;
    let exhaust_a = knot * (0.5 + 0.5 * sin(pos.z * 8.0 + theta * 3.0 - flow * 4.0));
    let exhaust_b = knot * (0.5 + 0.5 * sin(-pos.z * 8.0 + theta * 3.0 - flow * 4.0 + PI));

    return LoomSample(min(ribbon_a, ribbon_b), ribbon_a, ribbon_b, knot, vec2<f32>(exhaust_a, exhaust_b));
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = vec2<f32>(pixel) / resolution;
    let aspect = resolution.x / resolution.y;
    let clip = (uv * 2.0 - vec2<f32>(1.0)) * vec2<f32>(aspect, 1.0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(clip, 1.0));

    // Density integration loop
    var t = 0.0;
    var density_a = 0.0;
    var density_b = 0.0;
    var knot_energy = 0.0;
    var exhaust_energy = vec2<f32>(0.0);
    var nearest = 10.0;
    let max_steps = 60;
    let density_param = u.zoom_params.x;

    for (var i = 0; i < max_steps; i++) {
        let p = ro + rd * t;
        let loom = sampleLoom(p);
        let core_mask = smoothstep(0.28, 0.72, length(p.xy));
        let near_a = exp(-abs(loom.ribbon_a) * 28.0) * core_mask;
        let near_b = exp(-abs(loom.ribbon_b) * 28.0) * core_mask;

        if (loom.distance < 0.14) {
            density_a += near_a * density_param * (0.018 + bass * 0.006);
            density_b += near_b * density_param * (0.018 + mids * 0.005);
            knot_energy += loom.knot * (0.025 + mids * 0.012);
            exhaust_energy += loom.exhaust_pair * (0.018 + treble * 0.009);
            nearest = min(nearest, t);
        }

        t += max(loom.distance * 0.5, 0.02);
        if (t > 8.0) { break; }
    }

    let core_bright = u.zoom_params.w;
    let total_density = density_a + density_b;
    let normalized_density = 1.0 - exp(-total_density * 1.8);
    var hdr_color = palette(normalized_density + u.config.x * 0.1) * total_density * core_bright * 1.6;
    hdr_color += vec3<f32>(0.1, 1.1, 1.7) * exhaust_energy.x * core_bright * 4.0;
    hdr_color += vec3<f32>(1.7, 0.12, 1.1) * exhaust_energy.y * core_bright * 4.0;
    hdr_color += vec3<f32>(2.5, 2.2, 1.8) * knot_energy * core_bright * 5.0;
    hdr_color += vec3<f32>(0.05, 0.0, 0.1) * max(1.0 - length(clip), 0.0);

    let current_color = acesToneMap(hdr_color * (1.0 + treble * 0.08));
    let color = mix(current_color, prev.rgb, 0.06 + clamp(mids, 0.0, 2.0) * 0.015);
    let coverage = clamp(normalized_density + knot_energy * 2.0, 0.0, 1.0);
    let alpha = max(coverage, prev.a * 0.88);
    let depth_out = select(0.0, clamp(1.0 - nearest / 8.0, 0.0, 1.0), nearest < 8.0);
    let display_rgba = vec4<f32>(color, alpha);

    textureStore(writeTexture, pixel, display_rgba);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth_out, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, display_rgba);
}
