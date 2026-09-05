// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Medusa
//  Category: generative
//  Features: raymarched, audio-reactive, mouse-gravity-well, feedback-loops,
//            upgraded-rgba, chromatic-tentacles, temporal-bioluminescence,
//            audio-sway, depth-output, gravity-attractor, mouse-trail
//  Complexity: High
//  Upgraded: 2026-06-28 — Interactivist Batch (gravity wells + feedback loops)
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── Mouse gravity well + attractor ───
fn applyMouseGravity(p: vec3<f32>, mouse_pos: vec3<f32>, strength: f32) -> vec3<f32> {
    let m_dist = length(p - mouse_pos);
    let gravity = strength / (m_dist * m_dist + 0.5);
    return p + normalize(p - mouse_pos) * gravity * (1.0 + strength);
}

fn applyMouseAttractor(p: vec3<f32>, mouse_pos: vec3<f32>, attract: f32) -> vec3<f32> {
    let m_dist = length(p - mouse_pos);
    let pull = attract / (m_dist * m_dist + 1.0);
    return p - normalize(p - mouse_pos) * pull;
}

fn map(p: vec3<f32>, time: f32, bass: f32, mids: f32) -> vec2<f32> {
    var p1 = p;

    // Mouse in 3D: screen-top (zoom_config.z=0) = +Y/up
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (u.zoom_config.z - 0.5) * 5.0, 0.0);

    // Gravity well repulsion + attractor dual force
    let heldGain = mix(0.25, 1.0, clamp(u.zoom_config.w, 0.0, 1.0));
    let repulse_strength = u.zoom_params.w * 3.0 * heldGain;
    let attract_strength = u.zoom_params.w * 1.5 * heldGain;
    p1 = applyMouseGravity(p1, mouse_pos, repulse_strength);
    p1 = applyMouseAttractor(p1, mouse_pos, attract_strength);

    // Audio-reactive tentacle sway with feedback memory
    let sway = sin(time * 0.5 + p1.y * 2.0) * 0.1 * (1.0 + mids * 0.5);
    let sway_bass = cos(time * 0.3 + p1.x * 1.5) * 0.05 * bass;
    p1.x += sway + sway_bass;
    p1.z += sway_bass * 0.5;

    var p_bell = p1;
    p_bell.y += sin(time + length(p_bell.xz)) * 0.2 * (1.0 + bass * 0.3);
    let bell = length(p_bell * vec3<f32>(1.0, 2.0, 1.0)) - 1.0;

    var p_tent = p1;
    let angle = atan2(p_tent.z, p_tent.x);
    let num_tentacles = 8.0;
    let a = (angle + PI) / (TAU / num_tentacles);
    let idx = floor(a);
    let p_tent_xy = rot2D(time * 0.5 + p_tent.y * u.zoom_params.y) * p_tent.xy;
    p_tent.x = p_tent_xy.x;
    p_tent.y = p_tent_xy.y;
    let tentacles = length(p_tent.xz) - 0.1 * (1.0 - p_tent.y * 0.1);

    let d = smin(bell, tentacles, 0.5);
    return vec2<f32>(d, 1.0);
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, bass: f32, mids: f32) -> vec2<f32> {
    var dO = 0.0;
    var mat = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p, time, bass, mids);
        dO += dS.x;
        mat = dS.y;
        if(dO > MAX_DIST || abs(dS.x) < SURF_DIST) { break; }
    }
    return vec2<f32>(dO, mat);
}

fn getNormal(p: vec3<f32>, time: f32, bass: f32, mids: f32) -> vec3<f32> {
    let d = map(p, time, bass, mids).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy, time, bass, mids).x,
        map(p - e.yxy, time, bass, mids).x,
        map(p - e.yyx, time, bass, mids).x
    );
    return normalize(n);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }
    let uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x * clamp(u.zoom_params.x, 0.1, 5.0);

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    let rm = raymarch(ro, rd, time, bass, mids);
    let d = rm.x;

    var col = vec3<f32>(0.02, 0.01, 0.05);
    var hit = 0.0;
    var fresnel = 0.0;

    // Feedback loop: read previous frame glow accumulation
    let coord = vec2<i32>(id.xy);
    let prevFrame = textureLoad(dataTextureC, coord, 0);
    let prevGlow = prevFrame.a;

    if (d < MAX_DIST) {
        hit = 1.0;
        let p = ro + rd * d;
        let n = getNormal(p, time, bass, mids);
        let viewDir = -rd;
        fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        let glow = clamp(bass * u.zoom_params.z * 1.5 + 0.2, 0.0, 1.0);

        // Chromatic tentacle separation: R core, B tips, G mid
        let distFromCore = length(p.xz);
        let coreFactor = exp(-distFromCore * 2.0);
        let tipFactor = smoothstep(0.5, 2.0, distFromCore);
        let rCol = mix(vec3<f32>(0.1, 0.5, 0.8), vec3<f32>(0.9, 0.3, 0.2), coreFactor);
        let bCol = mix(vec3<f32>(0.1, 0.5, 0.8), vec3<f32>(0.2, 0.3, 0.9), tipFactor);
        col = mix(rCol, bCol, 0.5) * (1.0 - fresnel);
        col += vec3<f32>(0.2, 0.9, 0.8) * glow * (1.0 - fresnel);

        // Mouse-proximity chromatic boost
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (u.zoom_config.z - 0.5) * 5.0, 0.0);
        let mouse_dist = length(p - mouse_pos);
        let mouse_prox = exp(-mouse_dist * 2.0);
        col += vec3<f32>(0.5, 0.1, 0.3) * mouse_prox * bass * 2.0;

        // Temporal bioluminescence pulse memory with feedback
        let prevGlow2 = prevFrame.a;
        let pulseMemory = mix(glow, prevGlow2 * 0.92, 0.15 + bass * 0.05);
        col += vec3<f32>(0.3, 0.7, 0.6) * pulseMemory * fresnel;

        // Audio trail feedback: accumulate bass-driven color in feedback buffer
        let trailColor = vec3<f32>(0.6, 0.2, 0.8) * bass * mouse_prox;
        col += trailColor * 0.5;
    }

    // Feedback loop: blend with previous frame for motion trails
    col = mix(col, prevFrame.rgb * 0.95, 0.08 + bass * 0.03);

    let rippleCount = min(i32(u.config.y), 50);
    for (var i = 0; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age > 0.0 && age < 2.5) {
            let radius = age * 0.32;
            let ring = exp(-abs(distance(vec2<f32>(id.xy) / res, ripple.xy) - radius) * 100.0) * exp(-age * 1.8) * ripple.w;
            col += vec3<f32>(0.25, 0.9, 1.0) * ring * (0.5 + treble);
        }
    }

    let lumaOut = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(hit * (0.5 + fresnel * 0.4) + lumaOut * 0.2 + 0.05, 0.0, 1.0);
    col = acesToneMap(col * 1.1);
    let packed = vec4<f32>(col, alpha);
    textureStore(writeTexture, coord, packed);

    let depth = clamp(d / MAX_DIST, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, packed);
}
