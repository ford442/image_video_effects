// ═══════════════════════════════════════════════════════════════════
//  Celestial Clockwork Plasma-Loom
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: Keplerian astrolabe gearing; over-under plasma shuttle
//  A packing: ACES display RGBA with exact-C temporal blend
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

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Simplex noise hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

// Smooth noise
fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
    return mix(mix(mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                       dot(hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), f2.x),
                   mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                       dot(hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), f2.x), f2.y),
               mix(mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                       dot(hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), f2.x),
                   mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                       dot(hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), f2.x), f2.y), f2.z);
}

// SDF primitives
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

// Global variables for raymarching context
struct Context {
    glow: f32,
    mat_id: f32, // 1.0: gears, 2.0: plasma, 3.0: singularity
    shuttle: f32,
}

var<private> ctx: Context;

fn map(p_in: vec3<f32>) -> f32 {
    let time = u.config.x;
    var p = p_in;

    // Parameters
    let gearComplex = u.zoom_params.x; // Gear Complexity and Count
    let audioReact = u.zoom_params.y;  // Audio Plasma Reactivity
    let rotSpeed = u.zoom_params.z;    // Loom Rotation Speed
    let timeDilat = u.zoom_params.w;   // Time Dilation Intensity

    let audio = plasmaBuffer[0].xyz;
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Mouse Interaction (Time Dilation Field)
    let mouse = u.zoom_config.yz;
    // Map mouse from 0..1 to -1..1 loosely based on screen space
    let m_pos = vec3<f32>((mouse.x - 0.5) * 2.0 * 5.0, (mouse.y - 0.5) * 2.0 * 5.0, 0.0);
    let m_dist = length(p - m_pos);

    // Localized twisting
    let twist_amt = exp(-m_dist * 0.5) * timeDilat * 2.0;
    p = vec3<f32>(rot(twist_amt * sin(time)) * p.xy, p.z);

    // Global rotation
    let g_rot = time * mix(0.1, 1.0, rotSpeed) + bass * audioReact * 0.5;
    p = vec3<f32>(rot(g_rot * 0.3) * p.xy, p.z);
    p = vec3<f32>(p.x, rot(g_rot * 0.5) * p.yz);

    // 1. Interlocking Astrolabe Gears (Chronoglass)
    let rings = mix(2.0, 6.0, gearComplex);
    var d_gears = 1000.0;

    for(var i = 1; i <= 4; i++) {
        let fi = f32(i);
        if (fi > rings) { break; }

        let radius = fi * 1.5;
        let thickness = 0.15;

        var gp = p;
        // Idea 1: Keplerian ring rates slow with radius and alternate direction.
        let gear_direction = select(-1.0, 1.0, (i % 2) == 0);
        let kepler_rate = gear_direction / pow(max(radius, 0.5), 1.5);
        let ring_phase = g_rot * kepler_rate * 5.0;
        let gear_xz = rot(ring_phase) * gp.xz;
        gp = vec3<f32>(gear_xz.x, gp.y, gear_xz.y);
        let gear_yz = rot(ring_phase * (0.8 + fi * 0.12)) * gp.yz;
        gp = vec3<f32>(gp.x, gear_yz.x, gear_yz.y);

        // Base ring
        var ring_d = sdTorus(gp, vec2<f32>(radius, thickness));

        // Gear teeth (subtraction via polar rep)
        let teeth_count = 8.0 * fi;
        var polar_angle = atan2(gp.z, gp.x);
        let sector = 6.28318 / teeth_count;
        polar_angle = floor((polar_angle + sector * 0.5) / sector) * sector;

        let tooth_pos = vec3<f32>(cos(polar_angle) * radius, 0.0, sin(polar_angle) * radius);
        let tooth_d = sdSphere(gp - tooth_pos, thickness * 1.2);

        // Carve teeth
        ring_d = max(ring_d, -tooth_d);

        d_gears = min(d_gears, ring_d);
    }

    // 2. Plasma Threads
    let plasma_noise = noise(p * 0.5 + vec3<f32>(0.0, time * 0.5, 0.0));
    let plasma_angle = atan2(p.z, p.x);

    // Idea 2: opposed threads weave over/under while a shuttle crosses their necks.
    let weave_count = mix(3.0, 7.0, gearComplex);
    let weave_lift = sin(plasma_angle * weave_count - time * (0.7 + rotSpeed * 2.0)) *
        (0.12 + audioReact * 0.18);
    let thread_radius = 3.0 + sin(time) * 0.5;
    let thread_width = 0.13 + bass * audioReact * 0.18;
    let thread_a = sdTorus(p - vec3<f32>(0.0, weave_lift, 0.0), vec2<f32>(thread_radius, thread_width));
    let thread_b = sdTorus(p + vec3<f32>(0.0, weave_lift, 0.0), vec2<f32>(thread_radius, thread_width));
    let d_plasma = min(thread_a, thread_b) + plasma_noise * 0.9 * (0.45 + audioReact);
    let shuttle_phase = 0.5 + 0.5 * cos(plasma_angle - time * (1.2 + rotSpeed * 3.0) - mids * 0.2);
    let shuttle = pow(shuttle_phase, 14.0) * exp(-abs(d_plasma) * 20.0);
    ctx.shuttle = max(ctx.shuttle, shuttle * (0.7 + treble * 0.3));

    // 3. Singularity Core
    let d_core = sdSphere(p, 0.5 + bass * audioReact * 0.2);

    // Combine and set materials
    var d = d_gears;
    ctx.mat_id = 1.0;

    if (d_plasma < d) {
        d = d_plasma;
        ctx.mat_id = 2.0;
    }

    if (d_core < d) {
        d = d_core;
        ctx.mat_id = 3.0;
    }

    // Accumulate glow for volumetric rendering
    // Soft bloom for plasma, intense for core
    if (ctx.mat_id == 2.0) {
        ctx.glow += 0.01 / (0.01 + d_plasma * d_plasma);
    } else if (ctx.mat_id == 3.0) {
        ctx.glow += 0.05 / (0.01 + d_core * d_core);
    }

    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

// Background Fractal Void
fn background(rd: vec3<f32>) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var p = rd * 2.0;
    for(var i=0; i<4; i++) {
        p = abs(p) / dot(p,p) - vec3<f32>(0.5);
        col += vec3<f32>(0.05, 0.1, 0.2) * length(p) * 0.1;
    }
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // Reset context
    ctx.glow = 0.0;
    ctx.mat_id = 0.0;
    ctx.shuttle = 0.0;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -8.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    let max_steps = 100;
    let max_dist = 20.0;

    for(var i=0; i<max_steps; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > max_dist) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);

    if (t < max_dist) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        let mat = ctx.mat_id;

        // Lighting
        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let dif = max(dot(n, light_dir), 0.0);
        let fre = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        if (mat == 1.0) {
            // Chronoglass (Deep Indigo + Gold/Orange edges)
            let base_col = vec3<f32>(0.05, 0.1, 0.3); // Cosmic indigo
            // Fake refraction: sample background with perturbed ray
            let ref_rd = refract(rd, n, 0.65);
            let ref_col = background(ref_rd);

            // Edge emission (Starfire gold)
            let edge_emit = vec3<f32>(1.0, 0.7, 0.2) * fre * 2.0;

            col = base_col * dif + ref_col * 0.5 + edge_emit;
        } else if (mat == 2.0) {
            // Plasma Threads
            let base_col = vec3<f32>(1.0, 0.4, 0.1); // Searing solar orange
            col = base_col * (dif + 0.5) + vec3<f32>(1.0, 0.8, 0.4) * fre;
            col += vec3<f32>(0.35, 0.75, 1.0) * ctx.shuttle * 1.8;
        } else if (mat == 3.0) {
            // Singularity Core (Black hole + accretion disk)
            let emit = vec3<f32>(1.0, 0.9, 0.5) * fre * 5.0; // Bright rim
            col = mix(vec3<f32>(0.0), emit, fre);
        }
    } else {
        // Background
        col = background(rd);
    }

    // Add volumetric bloom (from glow accumulation)
    let bloom_col_plasma = vec3<f32>(1.0, 0.3, 0.05);
    let bloom_col_core = vec3<f32>(0.5, 0.7, 1.0);

    col += ctx.glow * 0.1 * mix(bloom_col_plasma, bloom_col_core, clamp(ctx.shuttle, 0.0, 1.0));

    // ACES tone mapping
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d_const = 0.59;
    let e = 0.14;
    col = clamp((col * (a * col + b)) / (col * (c * col + d_const) + e), vec3<f32>(0.0), vec3<f32>(1.0));

    let px = vec2<i32>(global_id.xy);
    let history = textureLoad(dataTextureC, px, 0);
    let historyBlend = 0.86;
    let historyDecay = 0.94;
    let color = mix(history.rgb, col, historyBlend);
    let has_hit = t < max_dist;
    let current_alpha = clamp(select(0.04, 0.28, has_hit) + ctx.glow * 0.015 + ctx.shuttle * 0.45, 0.0, 1.0);
    let alpha = max(history.a * historyDecay, current_alpha);
    let depth = select(0.0, clamp(1.0 - t / max_dist, 0.0, 1.0), has_hit);

    textureStore(writeTexture, px, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, px, vec4<f32>(depth));
    textureStore(dataTextureA, px, vec4<f32>(color, alpha));
}
