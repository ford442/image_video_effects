// ═══════════════════════════════════════════════════════════════════
//  Chronos Biomechanical Void-Leviathan
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: vertebral phase-lag undulation; auroral vortex wake
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
    zoom_params: vec4<f32>,  // .x = Time Offset, .y = Audio Reactivity, .z = Aurora, .w = Evolution Speed
    ripples: array<vec4<f32>, 50>,
};

// --- GLOBALS & MATH ---
const PI = 3.14159265359;
const MAX_STEPS = 120;
const MAX_DIST = 40.0;
const SURF_DIST = 0.005;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);

    // Smooth interpolation
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(mix(dot(hash33(i + vec3<f32>(0.,0.,0.)), f - vec3<f32>(0.,0.,0.)),
                dot(hash33(i + vec3<f32>(1.,0.,0.)), f - vec3<f32>(1.,0.,0.)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.,1.,0.)), f - vec3<f32>(0.,1.,0.)),
                dot(hash33(i + vec3<f32>(1.,1.,0.)), f - vec3<f32>(1.,1.,0.)), u.x), u.y),
        mix(mix(dot(hash33(i + vec3<f32>(0.,0.,1.)), f - vec3<f32>(0.,0.,1.)),
                dot(hash33(i + vec3<f32>(1.,0.,1.)), f - vec3<f32>(1.,0.,1.)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.,1.,1.)), f - vec3<f32>(0.,1.,1.)),
                dot(hash33(i + vec3<f32>(1.,1.,1.)), f - vec3<f32>(1.,1.,1.)), u.x), u.y), u.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var x = p;
    for (var i = 0; i < 4; i++) {
        f += w * noise3D(x);
        w *= 0.5;
        x *= 2.0;
    }
    return f;
}

// --- SDF FUNCTIONS ---
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// --- DOMAIN WARPING & KIFS ---
fn swimDistortion(p_in: vec3<f32>, time: f32) -> vec3<f32> {
    var p = p_in;

    // Idea 1: adjacent vertebral segments inherit a delayed swimming phase.
    let swimFreq = 0.5;
    let swimAmp = 0.8;
    let vertebra = (p.z + 5.0) * 1.5;
    let segment_id = floor(vertebra);
    let segment_mix = smoothstep(0.15, 0.85, fract(vertebra));
    let phase_a = segment_id * 0.24;
    let phase_b = (segment_id + 1.0) * 0.24;
    let phase_lag = mix(phase_a, phase_b, segment_mix);
    let body_mask = smoothstep(-5.0, 5.0, p.z);
    p.x += sin(p.z * swimFreq - time * 2.0 - phase_lag) * swimAmp * body_mask;
    p.y += cos(p.z * swimFreq * 0.7 - time * 1.45 - phase_lag) * swimAmp * 0.18 * body_mask;

    // Mouse orbit
    let mouse = u.zoom_config.yz;
    let rx = (mouse.y - 0.5) * PI;
    let ry = -(mouse.x - 0.5) * PI * 2.0;
    let rotX = rotate2D(rx);
    let rotY = rotate2D(ry);

    var tempXZ = vec2<f32>(p.x, p.z) * rotY;
    p.x = tempXZ.x;
    p.z = tempXZ.y;

    var tempYZ = vec2<f32>(p.y, p.z) * rotX;
    p.y = tempYZ.x;
    p.z = tempYZ.y;

    return p;
}

// --- MAP SCENE ---
fn map(p_in: vec3<f32>, time: f32) -> f32 {
    let p = swimDistortion(p_in, time);

    // 1. Build leviathan SDF
    // Main Body (capsule)
    var d = sdCapsule(p, vec3<f32>(0.0, 0.0, -4.0), vec3<f32>(0.0, 0.0, 4.0), max(0.35, 1.2 - p.z*0.1));

    // Head (ellipsoid)
    let head = sdEllipsoid(p - vec3<f32>(0.0, 0.0, 4.5), vec3<f32>(1.0, 0.8, 1.5));
    d = smin(d, head, 0.5);

    // 2. Cyber-plating & Ribbing details
    // Modulo arithmetic for repeating ribs along the spine
    var ribP = p;
    ribP.z = (fract(ribP.z * 1.5) - 0.5) / 1.5;
    let ribs = sdCapsule(ribP, vec3<f32>(0.0, -1.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), 0.15 + (p.z+4.0)*0.05);
    // Combine with smin to integrate ribs organically
    d = smin(d, ribs, 0.2);

    // 3. Temporal wake (KIFS fractals) trailing behind
    if (p_in.z < -2.0) {
        var fractP = p_in;
        fractP.z += time * 3.0; // move back
        for (var i = 0; i < 3; i++) {
            fractP = abs(fractP) - vec3<f32>(0.5, 0.5, 0.5);
            var tempXY = vec2<f32>(fractP.x, fractP.y) * rotate2D(0.5);
            fractP.x = tempXY.x;
            fractP.y = tempXY.y;
            fractP *= 1.5;
        }
        let wake = length(fractP) * pow(1.5, -3.0) - 0.1;
        // Fade wake based on z distance
        let wakeWeight = smoothstep(-2.0, -10.0, p_in.z);
        d = smin(d, wake + (1.0 - wakeWeight)*5.0, 1.0);
    }

    return d;
}

fn map_glow(p_in: vec3<f32>, time: f32) -> f32 {
     let p = swimDistortion(p_in, time);
     var ribP = p;
     ribP.z = (fract(ribP.z * 1.5) - 0.5) / 1.5;
     return sdCapsule(ribP, vec3<f32>(0.0, -1.2, 0.0), vec3<f32>(0.0, 1.2, 0.0), 0.1);
}

fn map_wake_glow(p: vec3<f32>, time: f32) -> f32 {
    // Idea 2: twin auroral helices coil through the existing KIFS wake.
    let phase = p.z * 1.35 - time * 2.2;
    let radius = 0.55 + 0.12 * sin(p.z * 0.7 - time);
    let helix_a = vec2<f32>(cos(phase), sin(phase)) * radius;
    let helix_b = -helix_a;
    let filament_a = abs(length(p.xy - helix_a) - 0.055);
    let filament_b = abs(length(p.xy - helix_b) - 0.055);
    let behind_tail = 1.0 - smoothstep(-2.4, -1.5, p.z);
    return min(filament_a, filament_b) + (1.0 - behind_tail) * 5.0;
}

// --- NORMAL CALCULATION ---
fn getNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time) - map(p - e.xyy, time),
        map(p + e.yxy, time) - map(p - e.yxy, time),
        map(p + e.yyx, time) - map(p - e.yyx, time)
    );
    return normalize(n);
}

// --- RAYMARCHING ---
struct MarchResult {
    dist: f32,
    glow: f32,
    wake_glow: f32,
    steps: f32,
    hit: bool,
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32) -> MarchResult {
    var dO = 0.0;
    var glow = 0.0;
    var wake_glow = 0.0;
    var steps = 0.0;
    var hit = false;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p, time);

        // Accumulate glow near ribs
        let dGlow = map_glow(p, time);
        glow += 0.01 / (0.01 + dGlow * dGlow);
        let dWake = map_wake_glow(p, time);
        wake_glow += 0.004 / (0.004 + dWake * dWake);

        if (abs(dS) < SURF_DIST) {
            hit = true;
            break;
        }

        dO += dS * 0.7; // Relax step size for better smin stability
        steps += 1.0;

        if (dO > MAX_DIST) {
            break;
        }
    }

    return MarchResult(dO, glow, wake_glow, steps, hit);
}

// --- MAIN COMPUTE SHADER ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) GlobalInvocationID: vec3<u32>) {
    let texSize = vec2<f32>(textureDimensions(writeTexture));
    if (f32(GlobalInvocationID.x) >= texSize.x || f32(GlobalInvocationID.y) >= texSize.y) {
        return;
    }

    let uv = (vec2<f32>(GlobalInvocationID.xy) - 0.5 * texSize) / texSize.y;

    // Parameters
    let time = u.config.x * u.zoom_params.w + u.zoom_params.x;
    let audio = plasmaBuffer[0].xyz;
    let audioReact = audio.x * u.zoom_params.y;
    let brightness = u.zoom_params.z;

    // Camera Setup
    let ro = vec3<f32>(0.0, 0.0, -12.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Perform Raymarch
    let res = raymarch(ro, rd, time);

    var col = vec3<f32>(0.0);

    // 1. Nebula Background (Volumetric)
    // Raymarch through a noisy volume if we didn't hit or in front of hit
    let maxBgDepth = min(res.dist, MAX_DIST);
    var volDen = 0.0;
    for(var j=0; j<20; j++){
         let pBg = ro + rd * (maxBgDepth * (f32(j)/20.0));
         volDen += clamp(fbm(pBg * 0.2 - vec3<f32>(0.0, 0.0, time * 0.5)) - 0.3, 0.0, 1.0);
    }
    col += vec3<f32>(0.05, 0.1, 0.15) * volDen * 0.1;


    if (res.hit) {
        let p = ro + rd * res.dist;
        let n = getNormal(p, time);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(n, halfDir), 0.0), 32.0);

        // Base Cyber-Obsidian color
        var matCol = vec3<f32>(0.02, 0.03, 0.05);

        // Add lighting
        col = matCol * (diff * 0.5 + 0.5) + vec3<f32>(1.0) * spec * 0.2;
    }

    // Add Bioluminescent Glow (Acoustic Symbiosis)
    // Base cyan/magenta, pulsing with audio
    let glowCol = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.0, 0.8),
        sin(time * 0.5 + audio.y * 0.2) * 0.5 + 0.5);
    col += glowCol * res.glow * 0.05 * (1.0 + audioReact * 2.0) * brightness;
    let wakeCol = mix(vec3<f32>(0.1, 0.65, 1.0), vec3<f32>(0.9, 0.12, 1.0),
        0.5 + 0.5 * sin(time * 0.7));
    col += wakeCol * res.wake_glow * 0.022 * (1.0 + audio.y * 0.6 + audio.z * 0.35) * brightness;

    // Atmospheric fog
    col = mix(col, vec3<f32>(0.01, 0.02, 0.03), 1.0 - exp(-0.02 * res.dist));

    // Tone mapping (ACES approx)
    col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14),
        vec3<f32>(0.0), vec3<f32>(1.0));

    let coord = vec2<i32>(GlobalInvocationID.xy);
    let alpha = clamp(select(0.04, 0.3, res.hit) + res.glow * 0.01 + res.wake_glow * 0.018, 0.0, 1.0);
    let display = vec4<f32>(col, alpha);
    let source_depth = textureLoad(readDepthTexture, coord, 0).r;
    let depth = select(source_depth, clamp(1.0 - res.dist / MAX_DIST, 0.0, 1.0), res.hit);
    textureStore(writeTexture, coord, display);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, display);
}
