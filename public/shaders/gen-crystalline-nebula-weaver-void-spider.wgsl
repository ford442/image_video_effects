// ═══════════════════════════════════════════════════════════════════
//  Crystalline Nebula-Weaver Void-Spider
//  Category: generative
//  Features: raymarched, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: nebula-condensed web nodes (lattice nodes only crystallise where the same fbm that paints the nebula is dense); metachronal eight-leg tetrapod gait (two-segment knee-bent legs, L1-R2-L3-R4 vs R1-L2-R3-L4); spinneret dragline sagging under gravity
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read back exactly as HDR history
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
    ripples: array<vec4<f32>, 50>
}

// ----------------------------------------------------------------
// Real hash-based value noise + fbm (replaces fake sin-dot field)
// ----------------------------------------------------------------

fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.3183099 + vec3<f32>(0.1, 0.2, 0.3)) * 17.0;
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

fn vnoise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f); // smoothstep weights
    return mix(
        mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), s.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), s.x), s.y),
        mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), s.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), s.x), s.y),
        s.z);
}

// Rotation matrix between octaves decorrelates the crystalline lattice
const FBM_ROT = mat3x3<f32>(
    vec3<f32>( 0.00,  0.80,  0.60),
    vec3<f32>(-0.80,  0.36, -0.48),
    vec3<f32>(-0.60, -0.48,  0.64)
);

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) { // 4 octaves, rotated between layers
        value += amplitude * vnoise(pos);
        pos = FBM_ROT * pos * 2.03;
        amplitude *= 0.5;
    }
    return value;
}

// IQ cosine palette for crystalline hue grading
fn palette(t: f32) -> vec3<f32> {
    let ab = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return ab + ab * cos(6.28318 * (c * t + d));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// Camera z for projecting web nodes onto the nebula (set once in main).
var<private> gCamZ: f32 = -7.5;

const WEB_R: f32 = 5.0;       // node lattice is bounded to a ball around the weaver
const NODE_RMAX: f32 = 0.07;  // largest condensed node radius, in lattice-cell units

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// ----------------------------------------------------------------
// Spider Geometry (abdomen pulses with real bass)
// ----------------------------------------------------------------

// Idea 2: Metachronal eight-leg tetrapod gait.
// Four leg pairs by angular repetition around the cephalothorax (mirror in x for the sides),
// each leg a femur + tibia capsule bent at a raised knee. Legs L1,R2,L3,R4 swing/lift in one
// tetrapod group, R1,L2,R3,L4 half a cycle later, with a small back-to-front metachronal lag.
// Bass only scales stride amplitude (`stride`); the phase is pure time.
fn legAt(q: vec3<f32>, idx: f32, sideI: f32, time: f32, stride: f32) -> f32 {
    let phi0 = 0.1745 + (idx + 0.5) * 0.6109;             // sectors of 35 degrees from 10 degrees
    let gsum = idx + sideI;
    let tetrapod = gsum - 2.0 * floor(gsum * 0.5);        // 0: L1 R2 L3 R4 | 1: R1 L2 R3 L4
    let phase = time * 4.0 + tetrapod * 3.14159 + idx * 0.4;
    let lift = max(sin(phase), 0.0) * 0.35 * stride;      // swing phase lifts the knee
    let phi = phi0 + cos(phase) * 0.13 * stride;          // protraction / retraction
    let dir = vec3<f32>(sin(phi), 0.0, cos(phi));
    let hip = dir * 0.45;
    let knee = hip + dir * 1.25 + vec3<f32>(0.0, 0.85 + lift, 0.0);
    let foot = knee + dir * 1.15 + vec3<f32>(0.0, -1.75 + lift * 0.6, 0.0);
    let femur = sdCapsule(q, hip, knee, 0.11);
    let tibia = sdCapsule(q, knee, foot, 0.08);
    return min(femur, tibia);
}

fn sdLegs(p: vec3<f32>, time: f32, stride: f32) -> f32 {
    let hc = p - vec3<f32>(0.0, 0.0, 1.2);
    let sideI = select(0.0, 1.0, hc.x >= 0.0);           // 0 = left, 1 = right
    let q = vec3<f32>(abs(hc.x), hc.y, hc.z);
    let sec = (atan2(q.x, q.z) - 0.1745) / 0.6109;        // 0 = forward (+z), pi = rear
    let idx = clamp(floor(sec), 0.0, 3.0);
    // Also evaluate the nearest neighbouring leg (the other side's leg past the first/last
    // sector, since the two sides are out of phase) so the repeated SDF stays a lower bound.
    let nbRaw = idx + select(-1.0, 1.0, sec - idx >= 0.5);
    let cross = nbRaw < 0.0 || nbRaw > 3.0;
    let nb = clamp(nbRaw, 0.0, 3.0);
    let nbSide = select(sideI, 1.0 - sideI, cross);
    return min(legAt(q, idx, sideI, time, stride), legAt(q, nb, nbSide, time, stride));
}

fn sdSpider(p: vec3<f32>, audioReact: f32, time: f32) -> f32 {
    // Abdomen and Cephalothorax
    let abdomen = length(p * vec3<f32>(1.0, 1.5, 1.0)) - (1.0 + audioReact * 0.2);
    let head = length(p - vec3<f32>(0.0, 0.0, 1.5)) - 0.7;
    var body = smin(abdomen, head, 0.5);

    // Legs: eight jointed legs (Idea 2) replace HEAD's single mirrored box pair
    let leg = sdLegs(p, time, 1.0 + audioReact * 0.5);

    return smin(body, leg, 0.2);
}

// ----------------------------------------------------------------
// Web and Environment Geometry
// ----------------------------------------------------------------

// Idea 3: Spinneret dragline. HEAD's thread1 was an infinite line down the view axis (seen only
// as a dot). The silk now leaves the abdomen tip and runs to an anchor above-left, sagging in
// a parabola whose depth is set by Gravity Distortion (straight at 0).
fn sdDragline(p: vec3<f32>, r: f32) -> f32 {
    let sag = u.zoom_params.y * 1.6;
    let S = vec3<f32>(0.0, 0.3, -0.95);     // spinnerets at the rear of the abdomen
    let A = vec3<f32>(-3.2, 7.5, 1.5);      // anchor off-frame, upper left
    var d = 1e5;
    var prev = S;
    for (var k = 1; k <= 4; k++) {
        let s = f32(k) * 0.25;
        let cur = mix(S, A, s) - vec3<f32>(0.0, 4.0 * sag * s * (1.0 - s), 0.0);
        d = min(d, sdCapsule(p, prev, cur, r));
        prev = cur;
    }
    return d;
}

// Idea 1: Nebula-condensed web nodes. The HEAD node lattice (fract grid at 2*web_complexity)
// is gated per cell by the SAME fbm density that paints the background nebula, sampled where
// the node centre projects on screen: nodes only crystallise out of dense gas and grow with it.
// Absent cells return a safe bound to the neighbouring cells (>= 1 - max|q| cell units), and the
// lattice is bounded to a ball around the weaver so grazing rays stop crawling through it.
fn sdNodes(p: vec3<f32>, time: f32, mouse: vec2<f32>) -> f32 {
    let wc = max(u.zoom_params.x, 0.1);       // Web Complexity
    let k = 2.0 * wc;                          // cells per world unit (HEAD: fract(p*wc*2))
    let ball = length(p) - WEB_R;
    if (ball > 0.5) { return ball; }
    let ps = p * k;
    let cell = floor(ps) + vec3<f32>(0.5);
    let q = ps - cell;
    let others = 1.0 - max(abs(q.x), max(abs(q.y), abs(q.z))) - NODE_RMAX;
    // Node centre back in (undragged) world space, projected through the pinhole camera.
    let cw = cell / k + vec3<f32>(mouse * 2.0, 0.0);
    let zc = cw.z - gCamZ;
    var gate = 0.0;
    if (zc > 0.3) {
        let dens = fbm(vec3<f32>(cw.xy / zc * 2.5, time * 0.15));
        gate = smoothstep(0.50, 0.62, dens);
    }
    let rEff = select(-1.0, NODE_RMAX * gate, gate > 0.0);
    let d = min(length(q) - rEff, others) / k; // HEAD divided a 2x-scaled distance by wc only
    return max(d, ball);
}

fn sdWeb(p: vec3<f32>, time: f32, mouse: vec2<f32>) -> f32 {
    let web_complexity = max(u.zoom_params.x, 0.1); // Web Complexity
    return min(sdDragline(p, 0.02 / web_complexity), sdNodes(p, time, mouse));
}

// Two-octave warp component, rescaled to fbm's 4-octave range/mean.
fn fbmLite(p: vec3<f32>) -> f32 {
    return (0.5 * vnoise(p) + 0.25 * vnoise(FBM_ROT * p * 2.03)) * 1.25;
}

fn displace(p: vec3<f32>, time: f32, mouse: vec2<f32>) -> vec3<f32> {
    let gravity_distortion = u.zoom_params.y; // Gravity Distortion
    // Real 3D warp (HEAD added one scalar to all three axes: a pure diagonal shift).
    // Same mean offset as HEAD, now decorrelated per axis.
    let q = p + vec3<f32>(time * 0.5);
    let w = vec3<f32>(fbmLite(q), fbmLite(q.yzx + vec3<f32>(17.3, 3.1, 8.7)), fbmLite(q.zxy - vec3<f32>(9.1, 5.3, 2.9)));
    let distortedP = p + w * gravity_distortion;
    return distortedP - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
}

// x = scene distance, y = condensed-node distance (for the node glow accumulator)
fn mapParts(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> vec2<f32> {
    let displacedP = displace(p, time, mouse);
    let web_complexity = max(u.zoom_params.x, 0.1);

    let spider = sdSpider(displacedP, audioReact, time);
    let nodes = sdNodes(displacedP, time, mouse);
    let web = min(sdDragline(displacedP, 0.02 / web_complexity), nodes) + fbm(p) * 0.1;
    return vec2<f32>(min(spider, web), nodes);
}

fn map(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> f32 {
    return mapParts(p, time, audioReact, mouse).x;
}

// Central-difference normal for crystalline shading
fn calcNormal(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.002, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audioReact, mouse) - map(p - e.xyy, time, audioReact, mouse),
        map(p + e.yxy, time, audioReact, mouse) - map(p - e.yxy, time, audioReact, mouse),
        map(p + e.yyx, time, audioReact, mouse) - map(p - e.yyx, time, audioReact, mouse)
    ));
}

// Hue-preserving clamp: scales rgb down by its peak instead of per-channel clip
fn hueClamp(col: vec3<f32>, limit: f32) -> vec3<f32> {
    let peak = max(col.r, max(col.g, col.b));
    return col * (limit / max(peak, limit));
}

// ACES filmic tonemapping (Narkowicz fit)
fn aces(x: vec3<f32>) -> vec3<f32> {
    let y = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    return clamp(y, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// Main Raymarching and Shading
// ----------------------------------------------------------------

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (global_id.x >= dimensions.x || global_id.y >= dimensions.y) { return; }
    let id = vec2<f32>(f32(global_id.x), f32(global_id.y));
    // y flipped so world +y (and the key light) is screen-up (HEAD rendered upside down)
    let uvRaw = (id - 0.5 * vec2<f32>(f32(dimensions.x), f32(dimensions.y))) / f32(dimensions.y);
    let uv = vec2<f32>(uvRaw.x, -uvRaw.y);
    let uv01 = (id + vec2<f32>(0.5)) / vec2<f32>(dimensions);

    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let audioBass = audio.x;   // bass drives the abdomen pulse
    let audioMids = audio.y;   // mids energise the nebula filaments
    let audioTreble = audio.z; // treble drives web-thread glint
    let aspect = f32(dimensions.x) / max(f32(dimensions.y), 1.0);
    // Mouse in the same y-up frame as uv so the dragged weaver still follows the pointer
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, -1.0);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    // Ray setup (void_depth coupling keeps the spider in frame)
    let void_depth = u.zoom_params.w; // Void Depth
    // Holding the pointer lunges the camera 30% closer (the JSON's documented hold behaviour)
    let ro = vec3<f32>(0.0, 0.0, -5.0 * void_depth * (1.0 - 0.3 * held));
    gCamZ = ro.z;
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching loop with crystalline glow accumulation
    var t = 0.0;
    var d = 0.0;
    var glow = 0.0;
    var nodeGlow = 0.0;
    var hit = false;
    let max_dist = 20.0 * void_depth;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let md = mapParts(p, time, audioBass, mouse);
        d = md.x;
        glow += exp(-max(d, 0.0) * 6.0) * 0.02;
        // Idea 1: condensed nodes gather their own glow as the ray grazes them
        nodeGlow += exp(-max(md.y, 0.0) * 30.0) * 0.03;
        if (d < 0.001) { hit = true; break; }
        if (t > max_dist) { break; }
        t += d;
    }

    let plasma_intensity = u.zoom_params.z; // Plasma Intensity

    // Nebula background: true fbm density graded through the cosine palette
    let nebDens = fbm(vec3<f32>(uv * 2.5, time * 0.15));
    var col = palette(nebDens + uv.x * 0.15 + time * 0.02 + audioMids * 0.12) * nebDens * nebDens * (0.35 + audioMids * 0.2);

    var depthNear = 0.0;
    // Only a converged ray is a surface (HEAD painted step-exhausted rays as hits)
    if (hit) {
        let hitP = ro + rd * t;
        let n = calcNormal(hitP, time, audioBass, mouse);
        let lightDir = normalize(vec3<f32>(0.6, 0.8, -0.4));
        let diff = max(dot(n, lightDir), 0.0);
        let fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        depthNear = 1.0 - clamp(t / max_dist, 0.0, 1.0);

        // Crystalline hue from the nebula field at the hit point
        let hueT = fbm(hitP * 0.7 + vec3<f32>(time * 0.1));
        var surf = palette(hueT) * (0.25 + 0.75 * diff) * (0.2 + depthNear * 0.8);
        surf += palette(hueT + 0.35) * fres * 1.2;

        // Bass-lit plasma body
        surf += vec3<f32>(1.0, 0.2, 0.8) * audioBass * (0.4 + fres);

        // Treble glint: sparkle hugging the web threads near the hit
        let webD = sdWeb(displace(hitP, time, mouse), time, mouse);
        let sparkle = pow(vnoise(hitP * 24.0 + vec3<f32>(time * 3.0)), 8.0);
        surf += vec3<f32>(0.9, 0.95, 1.0) * sparkle * audioTreble * exp(-max(webD, 0.0) * 24.0) * 6.0;

        col += surf * plasma_intensity;
    }

    // Crystalline glow gathered along the march, tinted by palette + plasma
    col += palette(nebDens + 0.5) * glow * (0.6 + audioBass * 0.8) * (0.5 + plasma_intensity);

    // Idea 1: condensed nodes shine in the colour of the gas they condensed from
    // (the node projects onto this pixel, so nebDens here is its gating density).
    col += palette(nebDens + 0.25) * nodeGlow * (0.8 + audioTreble * 0.6) * (0.5 + plasma_intensity);

    // Expanding click fronts pluck the crystalline web.
    var rippleGlow = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.5) {
            let delta = vec2<f32>((uv01.x - ripple.x) * aspect, uv01.y - ripple.y);
            rippleGlow += exp(-abs(length(delta) - age * 0.2) * 75.0) * exp(-age * 1.35);
        }
    }
    col += palette(nebDens + 0.7) * rippleGlow * (0.35 + audioTreble * 0.7);

    // Exact A/C display-history feedback; the host copies A → C.
    let coord = vec2<i32>(global_id.xy);
    let history = textureLoad(dataTextureC, coord, 0);
    let hdrColor = clamp(mix(col, history.rgb, 0.07 + audioBass * 0.06), vec3<f32>(0.0), vec3<f32>(6.0));

    // Tame the blowout: hue-preserving clamp at ~2.0, then ACES
    col = aces(hueClamp(hdrColor, 2.0));

    let hitMask = select(0.0, smoothstep(0.0, 0.18, depthNear), hit);
    let alpha = clamp(hitMask * 0.75 + glow * 0.18 + nodeGlow * 0.2 + nebDens * 0.12 + rippleGlow * 0.16, 0.02, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthNear, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
