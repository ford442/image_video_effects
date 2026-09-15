// ═══════════════════════════════════════════════════════════════════
//  Chronomorphic Glass Tesseract
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: 4D face-crossing caustics; temporal birefringence
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
  zoom_params: vec4<f32>,  // .x = Fold Speed, .y = Dispersion, .z = Refraction IOR, .w = Gravity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Helpers ─────────────
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 4D Rotation matrices
fn rotXW(a: f32, p: vec4<f32>) -> vec4<f32> {
    var pr = p;
    let r = rot(a);
    let r_xw = r * vec2<f32>(p.x, p.w);
    pr.x = r_xw.x;
    pr.w = r_xw.y;
    return pr;
}

fn rotYW(a: f32, p: vec4<f32>) -> vec4<f32> {
    var pr = p;
    let r = rot(a);
    let r_yw = r * vec2<f32>(p.y, p.w);
    pr.y = r_yw.x;
    pr.w = r_yw.y;
    return pr;
}

fn rotZW(a: f32, p: vec4<f32>) -> vec4<f32> {
    var pr = p;
    let r = rot(a);
    let r_zw = r * vec2<f32>(p.z, p.w);
    pr.z = r_zw.x;
    pr.w = r_zw.y;
    return pr;
}

fn rotXY(a: f32, p: vec4<f32>) -> vec4<f32> {
    var pr = p;
    let r = rot(a);
    let r_xy = r * vec2<f32>(p.x, p.y);
    pr.x = r_xy.x;
    pr.y = r_xy.y;
    return pr;
}

fn rotXZ(a: f32, p: vec4<f32>) -> vec4<f32> {
    var pr = p;
    let r = rot(a);
    let r_xz = r * vec2<f32>(p.x, p.z);
    pr.x = r_xz.x;
    pr.z = r_xz.y;
    return pr;
}

fn rotYZ(a: f32, p: vec4<f32>) -> vec4<f32> {
    var pr = p;
    let r = rot(a);
    let r_yz = r * vec2<f32>(p.y, p.z);
    pr.y = r_yz.x;
    pr.z = r_yz.y;
    return pr;
}

// 3D smooth max
fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

fn rotateTesseractPoint(p3: vec3<f32>, time: f32) -> vec4<f32> {
    var p = vec4<f32>(p3, 0.0);

    let foldSpeed = u.zoom_params.x;
    let t = time * foldSpeed * 0.2;

    p = rotXY(t * 1.3, p);
    p = rotYZ(t * 0.8, p);
    p = rotXZ(t * 1.1, p);

    p = rotXW(t * 0.7, p);
    p = rotYW(t * 0.9, p);
    p = rotZW(t * 1.2, p);
    return p;
}

// Tesseract SDF
fn sdf_tesseract(p3: vec3<f32>, time: f32) -> f32 {
    let p = rotateTesseractPoint(p3, time);
    // Base size
    let s = 1.0;

    // Distance to hypercube edges/faces
    let d = abs(p) - vec4<f32>(s);

    // Approximate distance
    let dist4d = length(max(d, vec4<f32>(0.0))) + min(max(max(d.x, d.y), max(d.z, d.w)), 0.0);

    // Add chronomorphic distortion (ripples)
    let ripple1 = sin(p3.x * 3.0 + time) * sin(p3.y * 2.5 - time * 1.2) * sin(p3.z * 3.5 + time * 0.8);
    let ripple2 = cos(length(p3) * 4.0 - time * 2.0);
    let chronomorph = (ripple1 * 0.08 + ripple2 * 0.05);

    return dist4d - 0.1 + chronomorph; // slight rounding
}

fn tesseractSliceMetrics(p3: vec3<f32>, time: f32) -> vec2<f32> {
    let p4 = rotateTesseractPoint(p3, time);
    // Idea 1: measure when hidden W faces cross the rendered 3D slice.
    let face_distance = abs(abs(p4.w) - 1.0);
    let face_caustic = 1.0 - smoothstep(0.035, 0.2, face_distance);
    return vec2<f32>(face_caustic, p4.w);
}

// Map scene
fn map(p: vec3<f32>) -> f32 {
    let tesseract = sdf_tesseract(p, u.config.x);
    return tesseract;
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct RenderResult {
    color: vec3<f32>,
    depth: f32,
    alpha: f32,
    hit: bool,
}

// Shading & Raymarching
fn render(ro: vec3<f32>, rd: vec3<f32>, uv: vec2<f32>, aspect: f32) -> RenderResult {
    let max_steps = 80;
    let max_dist = 20.0;
    let surf_dist = 0.005;

    var dO = 0.0;
    var p = ro;

    var hit = false;
    for(var i = 0; i < max_steps; i++) {
        p = ro + rd * dO;
        let dS = map(p);
        if(dS < surf_dist) {
            hit = true;
            break;
        }
        if(dO > max_dist) {
            break;
        }
        dO += dS;
    }

    let audio = plasmaBuffer[0].xyz;
    let audioPulse = audio.x * 0.35;

    // Background color (cosmic gradient)
    var col = mix(vec3<f32>(0.01, 0.01, 0.05), vec3<f32>(0.1, 0.02, 0.15), length(uv) * 0.5) + audioPulse * 0.1;
    var alpha = 0.04;

    if (hit) {
        let n = calcNormal(p);
        let v = -rd;
        let slice_metrics = tesseractSliceMetrics(p, u.config.x);

        let ior = u.zoom_params.z;
        let dispersion = u.zoom_params.y;

        // Chromatic Dispersion (Refraction)
        // Idea 2: W-phase offsets split time as well as wavelength.
        let temporal_delay = sin(u.config.x * (0.65 + u.zoom_params.x * 0.2) + slice_metrics.y * PI) *
            dispersion * (0.18 + audio.y * 0.04);
        let iorR = 1.0 / max(ior - dispersion - temporal_delay, 0.2);
        let iorG = 1.0 / max(ior + temporal_delay * 0.25, 0.2);
        let iorB = 1.0 / max(ior + dispersion + temporal_delay, 0.2);

        let refR = refract(rd, n, iorR);
        let refG = refract(rd, n, iorG);
        let refB = refract(rd, n, iorB);

        // Very basic mock environment sampling for internal refractions based on normal and refracted rays
        let envR = vec3<f32>(1.0, 0.2, 0.5) * max(0.0, dot(refR, vec3<f32>(0.0, 1.0, 0.0)));
        let envG = vec3<f32>(0.2, 1.0, 0.5) * max(0.0, dot(refG, vec3<f32>(1.0, 0.0, 0.0)));
        let envB = vec3<f32>(0.2, 0.5, 1.0) * max(0.0, dot(refB, vec3<f32>(0.0, 0.0, 1.0)));

        let refractColor = vec3<f32>(envR.x, envG.y, envB.z) * 1.5;

        // Fresnel / Iridescence
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 4.0);

        // Iridescent pearlescent color based on normal
        let iridescence = 0.5 + 0.5 * cos(TAU * (n.x * 2.0 + u.config.x * 0.2 + vec3<f32>(0.0, 0.33, 0.67)));

        // Inner glow based on audio
        let glow = vec3<f32>(0.8, 0.3, 0.9) * smoothstep(0.5, 1.0, fresnel) * audioPulse;

        // Combine
        col = mix(refractColor, iridescence, fresnel * 0.5) + glow * 2.0;

        // Specular highlight
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let h = normalize(l + v);
        let spec = pow(max(dot(n, h), 0.0), 32.0) * 1.0;
        col += vec3<f32>(spec);

        // Idea 1: W-face crossings focus paired cyan/gold caustic sheets.
        let caustic_color = mix(vec3<f32>(0.2, 0.8, 1.0), vec3<f32>(1.0, 0.55, 0.15),
            0.5 + 0.5 * sin(slice_metrics.y * TAU + u.config.x * 0.4));
        col += caustic_color * slice_metrics.x * (0.65 + audio.z * 0.18);

        // Attenuate by distance
        col *= exp(-0.1 * dO);
        alpha = clamp(0.2 + fresnel * 0.45 + spec * 0.2 + slice_metrics.x * 0.35, 0.0, 1.0);
    }

    let depth = select(0.0, clamp(1.0 - dO / max_dist, 0.0, 1.0), hit);
    return RenderResult(col, depth, alpha, hit);
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let x = i32(global_id.x);
    let y = i32(global_id.y);
    if (x >= i32(dims.x) || y >= i32(dims.y)) { return; }

    let res = vec2<f32>(f32(dims.x), f32(dims.y));
    let base_uv = vec2<f32>(f32(x) + 0.5, f32(y) + 0.5) / res;

    var uv = base_uv * 2.0 - 1.0;
    let aspect = res.x / res.y;
    uv.x *= aspect;

    // Mouse Interaction (Gravity Well)
    // Map mouse UV to screen space
    var mouse_pos = u.zoom_config.yz; // [0, 1]

    // If mouse is not interacting (0,0 is default when off-screen/uninitialized in some wrappers)
    // we just put it off screen
    if (length(mouse_pos) < 0.01) {
        mouse_pos = vec2<f32>(999.0);
    } else {
        mouse_pos = mouse_pos * 2.0 - 1.0;
        mouse_pos.x *= aspect;
    }

    let gravityStrength = u.zoom_params.w;
    let isMouseDown = u.zoom_config.w > 0.0;

    // Apply gravity well spatial distortion
    let distToMouse = length(uv - mouse_pos);
    let pull = (1.0 / (distToMouse + 0.1)) * gravityStrength * 0.5;
    let delta = vec3<f32>(uv - mouse_pos, 0.0);
    let dir = delta / max(length(delta), 0.001);
    let polarity = select(-0.1, 0.2, isMouseDown);
    let rd_warp = dir * pull * polarity;

    // Camera setup
    let time = u.config.x;
    var ro = vec3<f32>(0.0, 0.0, 3.5);

    // Gentle camera drift
    let rcam = rot(time * 0.1);
    let rcam_xz = rcam * vec2<f32>(ro.x, ro.z);
    ro.x = rcam_xz.x;
    ro.z = rcam_xz.y;

    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));

    var rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Apply gravity warp to ray direction
    rd = normalize(rd + rd_warp);

    // Render
    let rendered = render(ro, rd, uv, aspect);
    let coord = vec2<i32>(x, y);
    let source_depth = textureLoad(readDepthTexture, coord, 0).r;
    let depth = select(source_depth, rendered.depth, rendered.hit);
    let display = vec4<f32>(acesToneMap(max(rendered.color, vec3<f32>(0.0))), rendered.alpha);
    textureStore(writeTexture, coord, display);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, display);
}
