// ═══════════════════════════════════════════════════════════════════
//  Nebula Core
//  Category: generative
//  Features: audio-reactive, mouse-driven, held-drag, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: chaos filaments (domain_chaos twists+shears each warp octave, ridged strands); warp lens (warp_amount scales the domain warp, held pointer coils it into a swirling gravity well); photoevaporation pillars (dark eroded dust columns pointing at the core with bright ionised tips)
//  A packing: display RGBA (post-ACES, x audio gain) + semantic alpha; C read back as colour history and convex-mixed into the pre-ACES frame, as HEAD
// ═══════════════════════════════════════════════════════════════════
// Deep-space nebula core with layered plasma clouds, gravity-well mouse interaction,
// audio-reactive shockwaves / sparkles, and temporal feedback trails.
// Enriched with Wolfram Alpha Hydrogen Balmer Series astrophysics data.

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
    config: vec4<f32>,       // x: time, y: ripple count, zw: resolution
    zoom_config: vec4<f32>,  // x: time, yz: mouse UV (y=0 top), w: held (> 0.5)
    zoom_params: vec4<f32>,  // x: density, y: chaos, z: warpAmt, w: speed
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// --- ACES Filmic Tone Mapping ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Hash / Noise helpers (canonical, naga-safe) ---
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash22(i).x;
    let b = hash22(i + vec2<f32>(1.0, 0.0)).x;
    let c = hash22(i + vec2<f32>(0.0, 1.0)).x;
    let d = hash22(i + vec2<f32>(1.0, 1.0)).x;
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * vnoise2(p * freq);
        freq *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// IDEA 1 — Chaos filaments: fBm whose successive octaves are rotated and sheared by
// domain_chaos. At chaos = 0 this is exactly HEAD's fbm(); higher chaos compounds the
// shear per octave so the warp field stretches into strands.
fn fbmChaos(p: vec2<f32>, octaves: i32, chaos: f32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    var q = p;
    let ang = chaos * 0.8;
    let cs = cos(ang);
    let sn = sin(ang);
    let shear = chaos * 0.7;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * vnoise2(q * freq);
        freq *= 2.0;
        amplitude *= 0.5;
        q = vec2<f32>(cs * q.x - sn * q.y, sn * q.x + cs * q.y); // twist
        q = vec2<f32>(q.x + shear * q.y, q.y);                   // shear
    }
    return value;
}

// --- Domain warping (canonical "Inigo" style) ---
// IDEA 2 — Warp lens: `strength` (warp_amount * 4, default 0.5 -> HEAD's fixed 2.0) scales
// the displacement; `coil` rotates the displacement vector so a held pointer winds the
// gas into a spiral around the gravity well.
fn warpDomain(p: vec2<f32>, t: f32, chaos: f32, strength: f32, coil: f32) -> vec2<f32> {
    let q = vec2<f32>(
        fbmChaos(p + vec2<f32>(0.0, 0.0), 4, chaos),
        fbmChaos(p + vec2<f32>(5.2, 1.3), 4, chaos)
    );
    let r = vec2<f32>(
        fbmChaos(p + 4.0 * q + vec2<f32>(1.7, 9.2) + 0.15 * t, 4, chaos),
        fbmChaos(p + 4.0 * q + vec2<f32>(8.3, 2.8) + 0.126 * t, 4, chaos)
    );
    let cc = cos(coil);
    let sc = sin(coil);
    let rc = vec2<f32>(cc * r.x - sc * r.y, sc * r.x + cc * r.y);
    return p + strength * rc;
}

// --- Hydrogen Balmer Series (Wolfram Alpha astrophysics data) ---
// H-alpha: 6562.71 Å → red  |  H-beta: 4861.28 Å → cyan
// H-gamma: 4340.47 Å → blue |  H-delta: 4101.71 Å → violet
fn balmerNebula(dist: f32, nebula: f32, ionization: f32) -> vec3<f32> {
    let hAlpha  = vec3<f32>(1.0, 0.1, 0.0);  // 6562.71 Å — red
    let hBeta   = vec3<f32>(0.0, 0.8, 1.0);  // 4861.28 Å — cyan
    let hGamma  = vec3<f32>(0.2, 0.3, 1.0);  // 4340.47 Å — blue
    let hDelta  = vec3<f32>(0.6, 0.0, 1.0);  // 4101.71 Å — violet

    let core  = smoothstep(0.4 + ionization * 0.3, 0.0, dist);
    let mid   = smoothstep(0.7 + ionization * 0.2, 0.3, dist) * smoothstep(0.0, 0.3, dist);
    let outer = smoothstep(1.2, 0.6, dist);

    return (hAlpha * core + hBeta * mid + hGamma * outer * 0.5 + hDelta * (1.0 - smoothstep(0.0, 1.5, dist)) * 0.25)
           * (0.3 + nebula * 1.4);
}

// IDEA 3 — Photoevaporation pillars.
// Tapered capsule: tip circle radius r1 at origin, base radius r2 at +h along y.
fn sdTaperedColumn(pIn: vec2<f32>, r1: f32, r2: f32, h: f32) -> f32 {
    let p = vec2<f32>(abs(pIn.x), pIn.y);
    let b = (r1 - r2) / h;
    let a = sqrt(1.0 - b * b);
    let k = dot(p, vec2<f32>(-b, a));
    if (k < 0.0) { return length(p) - r1; }
    if (k > a * h) { return length(p - vec2<f32>(0.0, h)) - r2; }
    return dot(p, vec2<f32>(a, b)) - r1;
}

// One dust column pointing at the core (p = 0). Returns (eroded SDF, tip facing).
// Erosion is strongest at the tip; facing = how much this point looks back at the core.
fn pillar(p: vec2<f32>, ang: f32, tipR: f32, r1: f32, r2: f32, h: f32, erosion: f32) -> vec2<f32> {
    let dir = vec2<f32>(cos(ang), sin(ang));
    let perp = vec2<f32>(-dir.y, dir.x);
    let lp = vec2<f32>(dot(p, perp), dot(p, dir) - tipR);
    let tipness = 1.0 - smoothstep(0.0, 0.35, lp.y);
    let d = sdTaperedColumn(lp, r1, r2, h) + (erosion - 0.5) * 0.12 * (0.45 + 1.6 * tipness);
    let fromTip = normalize(p - dir * tipR + vec2<f32>(1e-4, 0.0));
    let toCore = -normalize(p + vec2<f32>(1e-4, 0.0));
    let facing = clamp(dot(fromTip, toCore), 0.0, 1.0);
    return vec2<f32>(d, facing);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let texel = vec2<f32>(id.xy);
    let uv = texel / dims;
    let coords = vec2<i32>(id.xy);

    if (id.x >= u32(dims.x) || id.y >= u32(dims.y)) { return; }

    let t = u.config.x;
    // HEAD fix: mouse is zoom_config.yz (UV, y=0 top), held is zoom_config.w.
    let mouse = u.zoom_config.yz;
    let mouseDown = select(0.0, 1.0, u.zoom_config.w > 0.5);

    // HEAD fix: audio straight from plasmaBuffer[0] (the extraBuffer spring-damper
    // never persisted and its per-thread writes clobbered extraBuffer[3..6]).
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let overall = (bass + mids + treble) / 3.0;
    let bassSmooth = bass;
    let trebleSmooth = treble;

    // Zoom params
    let density = u.zoom_params.x;
    let chaos = u.zoom_params.y;
    let warpAmt = u.zoom_params.z;
    let speed = u.zoom_params.w;

    // Continuous phase for the ring pattern (fract wraps by exactly TAU).
    let mutationSeed = fract(t * 0.01);

    // Aspect-corrected centered coordinates
    var p = (uv - 0.5) * 2.0;
    let aspect = dims.x / dims.y;
    p.x *= aspect;

    // Mouse interaction: gravity well when held (same uv -> p mapping as the pixels)
    var mousePos = (mouse - 0.5) * 2.0;
    mousePos.x *= aspect;
    let mDist = length(p - mousePos);
    let mousePull = exp(-mDist * 3.0) * mouseDown;

    // IDEA 2 — Warp lens: gravity-well coil. Differential rotation about the pointer
    // (strongest at the centre) winds the gas into a spiral; bass tightens it.
    let well = exp(-mDist * 2.2) * mouseDown;
    let coil = well * (3.5 + bass * 2.0);
    let warpStrength = warpAmt * 4.0 * (1.0 + 0.8 * well);

    // Domain warp with mouse gravity + audio chaos
    var wp = p;
    if (mouseDown > 0.5) {
        let rotSwirl = mat2x2<f32>(cos(coil), sin(coil), -sin(coil), cos(coil));
        wp = mousePos + rotSwirl * (p - mousePos) * (1.0 - 0.5 * mousePull);
    }
    // HEAD fix: mids nudge the warp phase (bounded) instead of multiplying t,
    // which made the gas jitter harder the longer the shader ran.
    wp = warpDomain(wp * (1.0 + density * 2.0), t * speed + mids * 0.6, chaos, warpStrength, coil);

    // Layered nebula clouds (3 octaves of fBM for performance)
    let f1 = fbm(wp + t * 0.1 * speed, 5);
    let f2 = fbm(wp * 2.0 - t * 0.15 * speed, 4);
    let f3 = fbm(wp * 0.5 + t * 0.05 * speed + 10.0, 3);

    var nebula = f1 * 0.5 + f2 * 0.3 + f3 * 0.2;

    // IDEA 1 — Chaos filaments: thin ridged strands where the sheared field crosses 0.5.
    var ridge = 1.0 - abs(2.0 * f2 - 1.0);
    ridge = ridge * ridge; ridge = ridge * ridge; ridge = ridge * ridge; ridge = ridge * ridge;
    nebula += ridge * chaos * chaos * 0.6;

    // Ionization front driven by bass
    let ionization = smoothstep(0.3, 0.7, bassSmooth);

    // Balmer emission colors — H-alpha dominates core, H-beta in mid regions
    let dist = length(p);
    var col = balmerNebula(dist, nebula, ionization);

    // Treble adds chromatic sparkles / fine structure
    col += vec3<f32>(trebleSmooth * 0.3, trebleSmooth * 0.1, trebleSmooth * 0.5) * f2;

    // Bass shockwave rings (tinted with H-beta cyan)
    let ringDist = length(p) * (1.0 + bassSmooth * 0.5);
    let rings = sin(ringDist * 10.0 - t * 2.0 * speed + mutationSeed * 6.28) * exp(-ringDist * 2.0);
    col += rings * bassSmooth * vec3<f32>(0.0, 0.8, 1.0);

    // Fine particles from treble (star-like)
    let particles = hash22(floor(p * 50.0 + t * 0.01)).x;
    let particleGlow = smoothstep(0.98, 1.0, particles) * trebleSmooth * 2.0;
    col += vec3<f32>(particleGlow);

    // IDEA 3 — Photoevaporation pillars: dense dust columns (three below the core, one
    // above-right) pointing at it. Erosion noise rides the warped gas so the columns are
    // shredded by the same flow; the core-facing tips carry a bright ionisation rim.
    let erosion = fbm(wp * 1.7 + vec2<f32>(0.0, t * 0.05 * speed), 3);
    let sway = 0.04 * sin(t * speed * 0.3);
    let pA = pillar(p, 1.62 + sway, 0.42, 0.055, 0.15, 1.3, erosion);
    let pB = pillar(p, 1.10 - sway, 0.58, 0.045, 0.12, 1.1, erosion);
    let pC = pillar(p, 2.18 + sway * 0.7, 0.62, 0.05, 0.13, 1.1, erosion);
    let pD = pillar(p, -0.90 - sway * 0.5, 0.62, 0.04, 0.11, 1.0, erosion);
    var pil = pA;
    if (pB.x < pil.x) { pil = pB; }
    if (pC.x < pil.x) { pil = pC; }
    if (pD.x < pil.x) { pil = pD; }
    let aa = 3.0 / dims.y;
    let pillarMask = 1.0 - smoothstep(-aa, aa, pil.x);
    let dustCol = vec3<f32>(0.10, 0.05, 0.035) * (0.4 + nebula);
    col = mix(col, col * 0.08 + dustCol, pillarMask * 0.92);
    let rimW = 0.15 + 0.85 * pil.y;
    let rimBand = exp(-abs(pil.x) * 45.0);
    let evapHalo = exp(-max(pil.x, 0.0) * 10.0) * (1.0 - pillarMask) * pil.y;
    let rimCol = mix(vec3<f32>(1.0, 0.45, 0.32), vec3<f32>(0.65, 0.92, 1.0), ionization);
    col += rimCol * (rimBand * rimW * 1.4 + evapHalo * 0.35) * (0.8 + ionization * 1.2 + bass * 0.6);

    // Mouse glow when active — seeds new star formation
    if (mouseDown > 0.5) {
        let mouseGlow = exp(-mDist * 4.0) * 0.5;
        col += vec3<f32>(0.9, 0.95, 1.0) * mouseGlow;
        // New star formation burst driven by bass
        let starBurst = exp(-mDist * 12.0) * bassSmooth * 3.0;
        col += vec3<f32>(1.0, 0.8, 0.6) * starBurst;
    }

    // Vignette
    let vig = 1.0 - smoothstep(0.5, 1.5, length(p));
    col *= vig;

    // Temporal feedback with audio-driven mix
    let prev = textureLoad(dataTextureC, coords, 0);
    let feedbackMix = 0.25 + bassSmooth * 0.08;
    col = mix(prev.rgb * 0.96, col, feedbackMix);

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bassSmooth + well);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Audio-driven film grain / sparkle pass
    let grain = hash22(uv * 1000.0 + t * 0.1).x;
    let sparkle = smoothstep(0.995, 1.0, grain) * trebleSmooth * 3.0;
    col += vec3<f32>(sparkle * 0.8, sparkle, sparkle * 1.2);

    // ACES tone mapping + semantic alpha
    col = acesToneMap(col * 1.1);
    let alpha = clamp(length(col) * 1.2 + well * 0.2 + sparkle, 0.2, 0.95);

    let outColor = vec4<f32>(col * (0.8 + overall * 0.4), alpha);
    textureStore(writeTexture, coords, outColor);
    textureStore(dataTextureA, coords, outColor);

    // Write depth (nebula intensity as depth; pillars sit in front of the gas)
    textureStore(writeDepthTexture, coords, vec4<f32>(max(nebula, pillarMask * 0.9), 0.0, 0.0, 1.0));
}
