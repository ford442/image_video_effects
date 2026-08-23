// ═══════════════════════════════════════════════════════════════════
//  Holographic Bismuth-Core Reactor
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=MouseInfluence
  ripples: array<vec4<f32>, 50>,
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}


const MAX_STEPS: i32 = 100;
const MAX_DIST: f32  = 50.0;
const SURF_DIST: f32 = 0.001;

// 3D rotation helper — column-major mat3x3 for WGSL
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let a  = normalize(axis);
    let s  = sin(angle);
    let c  = cos(angle);
    let oc = 1.0 - c;
    // mat3x3<f32>(col0, col1, col2)
    return mat3x3<f32>(
        vec3<f32>(oc * a.x * a.x + c,         oc * a.x * a.y + a.z * s,  oc * a.z * a.x - a.y * s),
        vec3<f32>(oc * a.x * a.y - a.z * s,   oc * a.y * a.y + c,        oc * a.y * a.z + a.x * s),
        vec3<f32>(oc * a.z * a.x + a.y * s,   oc * a.y * a.z - a.x * s,  oc * a.z * a.z + c      )
    );
}

// Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn map(p_in: vec3<f32>, time: f32, bass: f32) -> vec2<f32> {
    var p = p_in;

    // Mouse warp — standard layout: zoom_config.yz = MouseX, MouseY
    let mouse = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);
    let mouseGain = u.zoom_params.w * (1.0 + held * 0.65);
    p = rot3D(vec3<f32>(1.0, 0.0, 0.0), (mouse.y - 0.5) * 3.14 * mouseGain) * p;
    p = rot3D(vec3<f32>(0.0, 1.0, 0.0), (mouse.x - 0.5) * 3.14 * mouseGain) * p;

    var s: f32 = 1.0;

    // Audio-reactive pulse: bass modulates the pulse amplitude
    let speed = mix(0.2, 2.4, clamp(u.zoom_params.y, 0.0, 1.0));
    let pulse      = sin(time * speed * 2.0) * 0.5 + 0.5;
    let bass_boost = 1.0 + bass * 0.5;
    let core_scale = mix(0.28, 1.05, clamp(u.zoom_params.z, 0.0, 1.0)) *
                     (1.0 + pulse * bass_boost * (0.08 + u.zoom_params.x * 0.32));

    // KIFS Bismuth fractals
    for (var i = 0; i < 4; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.5, 0.5) * core_scale;
        p = rot3D(vec3<f32>(0.0, 1.0, 0.0), 1.5708) * p; // 90 deg folding
        p = rot3D(vec3<f32>(1.0, 0.0, 0.0), 1.5708) * p;
        p = p * 1.5;
        s *= 1.5;
    }

    let d1 = sdBox(p, vec3<f32>(0.3, 0.3, 0.3)) / max(s, 0.001);

    // Orbiting micro-crystals
    var p2 = p_in;
    p2 = rot3D(vec3<f32>(0.0, 1.0, 0.0), time * speed) * p2;
    p2 = p2 - round(p2 / 2.0) * 2.0; // Domain repetition
    let d2 = sdBox(p2, vec3<f32>(0.05, 0.05, 0.05));

    // Branchless: return minimum distance with ID encoded in .y
    let isCore = step(d2, d1); // 1.0 when d1 <= d2 (core wins)
    let dMin   = mix(d2, d1, isCore);
    let idMin  = mix(2.0, 1.0, isCore);
    return vec2<f32>(dMin, idMin);
}

fn getNormal(p: vec3<f32>, time: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, bass).x;
    let n = vec3<f32>(
        d - map(p - vec3<f32>(e.x, e.y, e.y), time, bass).x,
        d - map(p - vec3<f32>(e.y, e.x, e.y), time, bass).x,
        d - map(p - vec3<f32>(e.y, e.y, e.x), time, bass).x
    );
    return normalize(n);
}

// Iridescence based on thin-film interference — mids drive shift
fn iridescence(dot_vn: f32, time: f32, bass: f32, mids: f32) -> vec3<f32> {
    let speed = mix(0.2, 2.4, clamp(u.zoom_params.y, 0.0, 1.0));
    let t = dot_vn * 2.0 + time * speed * 0.5 + bass * u.zoom_params.x + mids * 0.3;
    let r = sin(t * 3.14) * 0.5 + 0.5;
    let g = sin(t * 3.14 + 2.09) * 0.5 + 0.5;
    let b = sin(t * 3.14 + 4.18) * 0.5 + 0.5;
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    // Standard boundary guard
    if (id.x >= u32(resolution.x) || id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(id.xy);
    let uv_px = vec2<f32>(id.xy) / resolution; // [0,1] for depth/texture sampling

    // Standard UV for raymarching: centred, aspect-corrected
    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / max(resolution.y, 0.001);

    // Time from standard uniform
    let time = u.config.x;

    // Audio reactivity
    let audioBands = plasmaBuffer[0].xyz;
    let bass   = audioBands.x;
    let mids   = audioBands.y;
    let treble = audioBands.z;
    let held = step(0.5, u.zoom_config.w);
    let heldPlasma = 1.0 + held * u.zoom_params.w * (0.7 + bass * 0.8);

    // Raymarching setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    var p     = ro;
    var dO    = 0.0;
    var res   = vec2<f32>(0.0);
    var accum = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p   = ro + rd * dO;
        res = map(p, time, bass);
        let dS = res.x;
        dO += dS;

        // Volumetric plasma accumulation — treble adds sparkle
        accum += (0.12 + u.zoom_params.x * 0.65 + treble * 0.1) * heldPlasma * 0.05 / max(1.0 + abs(dS) * 50.0, 0.001);

        if (dS < SURF_DIST || dO > MAX_DIST) { break; }
    }

    // Hit test: branchless using step
    let hit = step(dO, MAX_DIST); // 1.0 if hit, 0.0 if miss

    let n      = getNormal(p, time, bass);
    let v      = -rd;
    let dot_vn = max(dot(v, n), 0.0);

    let surface_col = iridescence(dot_vn, time, bass, mids) * exp(-dO * 0.1);

    // Blend surface color in for hit pixels, zero for miss
    var col = surface_col * hit;

    // Add plasma bloom (always)
    col = col + vec3<f32>(0.2, 0.6, 1.0) * accum * heldPlasma;

    // Bounded click rings excite the reactor shell without adding persistent state.
    let aspect = resolution.x / max(resolution.y, 1.0);
    let rippleCount = min(u32(u.config.y), 50u);
    var clickRings = 0.0;
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.0) { continue; }
        let dist = length((uv_px - ripple.xy) * vec2<f32>(aspect, 1.0));
        let strength = clamp(ripple.w, 0.0, 1.0) * exp(-age * 1.5);
        clickRings += exp(-abs(dist - age * 0.36) * 80.0) * strength;
    }
    col += vec3<f32>(1.0, 0.28, 1.25) * clickRings * (0.45 + mids + treble * 0.6);

    // Meaningful alpha: 1.0 on surface hit, fades to plasma bloom level for misses
    let alpha = clamp(mix(clamp(accum * 3.0 + clickRings * 0.3, 0.0, 1.0), 1.0, hit), 0.0, 1.0);

    // Exact-load temporal HDR display history. A remains semantic RGBA rather
    // than auxiliary masks, while ACES is applied only to the visible output.
    let previous = textureLoad(dataTextureC, coord, 0);
    let historyWeight = clamp(0.90 - u.zoom_params.y * 0.25 - held * 0.08, 0.48, 0.90);
    let historyColor = clamp(max(col, previous.rgb * historyWeight), vec3<f32>(0.0), vec3<f32>(8.0));
    let historyAlpha = max(alpha, previous.a * historyWeight);
    let controlled = applyGenerativePrimaryControls(vec4<f32>(historyColor, historyAlpha));

    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(controlled.rgb), controlled.a));
    textureStore(dataTextureA, coord, controlled);

    // Depth: normalized ray distance (0=near, 1=far/miss)
    let depth_val = clamp(dO / MAX_DIST, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_val, 0.0, 0.0, 0.0));
}
