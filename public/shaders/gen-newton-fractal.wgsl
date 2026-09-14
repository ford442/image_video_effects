// ═══════════════════════════════════════════════════════════════════
//  Newton Fractal
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-14
//  Ideas: convergence-order sheen (estimated order q from successive Newton steps: quadratic glints, linear/relaxed zones shade violet with step isochrones); damped-Newton relaxation waves from clicks / held mouse reshaping the basins
//  A packing: ACES display RGBA in A; A.a = floor(convergenceAlpha*255)/256 + reactionState*(0.999/256) (reaction-diffusion state rides in the sub-1/256 fraction of alpha)
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
  zoom_params: vec4<f32>,  // .x = Zoom, .y = Polynomial Degree, .z = Iteration Precision, .w = Boundary Distortion
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_ROOTS: i32 = 6;

// ── Hash & noise ──────────────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

// ── Complex helpers ───────────────────────────────────────────────
fn cpower(z: vec2<f32>, n: f32) -> vec2<f32> {
    let r = length(z);
    let a = atan2(z.y, z.x);
    let rn = pow(r + 1e-6, n);
    return vec2<f32>(rn * cos(n * a), rn * sin(n * a));
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b, b) + 1e-8;
    return vec2<f32>((a.x * b.x + a.y * b.y) / d, (a.y * b.x - a.x * b.y) / d);
}

fn complexNoise(z: vec2<f32>, time: f32, scale: f32) -> vec2<f32> {
    let q = z * 3.0 + vec2<f32>(time * 0.11, -time * 0.07);
    let n1 = fbm(q, 3);
    let n2 = fbm(q + vec2<f32>(5.2, 1.3), 3);
    return scale * vec2<f32>(n1 - 0.5, n2 - 0.5);
}

// ── Tone & color ──────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

// ── SDF smooth boolean ────────────────────────────────────────────
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ── Reaction-diffusion sampling ───────────────────────────────────
// Reaction state is packed into the sub-1/256 fraction of A.a (see header).
fn unpackState(a: f32) -> f32 {
    return clamp(fract(a * 256.0) / 0.999, 0.0, 1.0);
}

fn sampleState(c: vec2<i32>, dims: vec2<i32>, fallback: f32) -> f32 {
    let inside = c.x >= 0 && c.x < dims.x && c.y >= 0 && c.y < dims.y;
    let cc = clamp(c, vec2<i32>(0), dims - vec2<i32>(1));
    return select(fallback, unpackState(textureLoad(dataTextureC, cc, 0).a), inside);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let mouse = u.zoom_config.yz;

    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    // Parameters
    let zoom = mix(0.5, 5.5, p1);
    let degree = mix(3.0, 6.0, clamp(p2 + bass * 0.04, 0.0, 1.0));
    let maxIter = i32(mix(28.0, 84.0, p3));
    let tol = mix(2e-4, 1e-6, p3);
    let warpStrength = mix(0.0, 0.28, p4) + mids * 0.02;
    let perturbStrength = mix(0.0, 0.09, p4);
    let bloom = clamp(p4 + bass * 0.1, 0.0, 1.0);

    // Coordinate setup with domain warp
    let aspect = res.x / max(res.y, 1.0);
    var p = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 3.5 / zoom;
    let zoomCenter = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    p = p + zoomCenter;
    p = domainWarp(p * 2.5 + vec2<f32>(time * 0.03), warpStrength, 3);

    // Root palette
    let rootColors = array<vec3<f32>, 6>(
        vec3<f32>(0.95, 0.08, 0.12),
        vec3<f32>(0.08, 0.92, 0.15),
        vec3<f32>(0.08, 0.35, 1.00),
        vec3<f32>(1.00, 0.85, 0.08),
        vec3<f32>(0.95, 0.08, 0.85),
        vec3<f32>(0.25, 0.95, 0.95)
    );

    let nRoots = clamp(i32(floor(degree + 0.5)), 3, MAX_ROOTS);
    let rootStep = TAU / degree;

    // Native idea 2: damped-Newton relaxation waves. z -= a * f/f'; a = 1 is
    // classic Newton, a != 1 (from click ripples / held mouse) turns quadratic
    // convergence linear and makes the basin boundaries breathe.
    var relax = 1.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let dist = length((uv01 - rp.xy) * vec2<f32>(aspect, 1.0));
            let band = (dist - age * 0.35) * 12.0;
            relax += exp(-band * band) * exp(-age * 1.1) * 0.55 * (1.0 + bass * 0.3);
        }
    }
    if (u.zoom_config.w > 0.5) {
        let md = length((uv01 - mouse) * vec2<f32>(aspect, 1.0));
        relax -= exp(-md * md * 18.0) * 0.4;
    }
    relax = clamp(relax, 0.45, 1.8);

    // Newton iteration with orbit trapping
    var z = p;
    var iters = 0;
    var orbitMin = 1e9;
    var orbitSecond = 1e9;
    var lastDz = vec2<f32>(0.0);
    var prevStep = 1.0;
    var convOrder = 0.0; // peak observed local convergence order

    for (var i = 0; i < maxIter; i = i + 1) {
        let zn = cpower(z, degree);
        let znm1 = cpower(z, degree - 1.0);
        let perturb = complexNoise(z, time, perturbStrength);
        let dz = cdiv(zn - vec2<f32>(1.0, 0.0) + perturb, degree * znm1) * relax;
        z = z - dz;
        lastDz = dz;
        iters = i;

        // Native idea 1: local convergence order q = log|dz_k| / log|dz_k-1|.
        let stepLen = length(dz);
        // Quadratic Newton climbs toward q=2 as steps shrink; damped or inexact
        // (noise-perturbed) Newton decays toward q=1, so keep the peak estimate.
        if (prevStep < 0.3 && prevStep > 1e-9 && stepLen > 1e-12 && stepLen < prevStep) {
            convOrder = max(convOrder, clamp(log(stepLen) / log(prevStep), 0.5, 3.0));
        }
        prevStep = stepLen;

        // Multi-shape orbit trap
        let r = length(z);
        let dRing = abs(r - 1.0);
        let dAxis = min(abs(z.x), abs(z.y));
        let dDiag = abs(z.x - z.y) * 0.70710678;
        let ang = atan2(z.y, z.x);
        let dSpiral = abs(fract(ang / TAU + log(r + 1e-6) * 0.25 + time * 0.03) - 0.5) * 2.0;
        let dTrap = min(min(min(dRing, dAxis), dDiag), dSpiral);

        let isMin = dTrap < orbitMin;
        orbitSecond = select(min(orbitSecond, dTrap), orbitMin, isMin);
        orbitMin = select(orbitMin, dTrap, isMin);

        if (length(dz) < tol) { break; }
    }

    // Smooth iteration count
    let smoothIter = f32(iters) - log2(tol / max(length(lastDz), tol));
    let iterRatio = clamp(smoothIter / f32(maxIter), 0.0, 1.0);
    let convergence = 1.0 - iterRatio;

    // Identify nearest root
    let theta = atan2(z.y, z.x);
    let nearestIdx = clamp(i32(fract(theta / rootStep + 0.5) * degree + 0.5), 0, nRoots - 1);

    // Multi-root color accumulation for organic boundaries
    var accCol = vec3<f32>(0.0);
    var weightSum = 0.0;
    for (var k = 0; k < MAX_ROOTS; k = k + 1) {
        let alive = k < nRoots;
        let ra = rootStep * f32(k);
        let rk = vec2<f32>(cos(ra), sin(ra));
        let dk = length(z - rk);
        let w = exp(-dk * 7.0) * f32(alive);
        accCol = accCol + rootColors[k] * w;
        weightSum = weightSum + w;
    }
    let blendedRoot = accCol / max(weightSum, 1e-6);
    let baseCol = mix(rootColors[nearestIdx], blendedRoot, 0.35 + p4 * 0.35);

    var color = baseCol * (1.0 - iterRatio * 0.55);

    // Orbit-trap glow
    let trapGlow = exp(-orbitMin * (7.0 + bloom * 10.0 + treble * 4.0));
    let trapIrid = exp(-orbitSecond * (3.0 + bloom * 6.0));
    color = color + vec3<f32>(0.5, 0.7, 0.95) * trapGlow * bloom * 2.0;
    color = color + vec3<f32>(0.95, 0.45, 0.25) * trapIrid * bloom * 0.7;

    // SDF smooth-union halo around roots
    var sdf = 1e9;
    let rootRadius = 0.04 + p4 * 0.05;
    for (var k = 0; k < MAX_ROOTS; k = k + 1) {
        let alive = k < nRoots;
        let ra = rootStep * f32(k);
        let rk = vec2<f32>(cos(ra), sin(ra));
        let dk = length(z - rk) - rootRadius;
        sdf = select(sdf, smin(sdf, dk, 0.07), alive);
    }
    let sdfGlow = exp(-abs(sdf) * (5.0 + bloom * 8.0));
    color = color + vec3<f32>(0.55, 0.9, 1.0) * sdfGlow * bloom * 0.85;

    // Convergence-order sheen: quadratic (q~2) glints, linear (q~1) shades violet,
    // with isochrone contours of the smooth step count.
    let orderQ = select(convOrder, 1.0, convOrder <= 0.0); // never contracted -> treat as linear
    let linearity = 1.0 - smoothstep(1.4, 1.8, orderQ);
    let quadratic = smoothstep(1.75, 1.95, orderQ);
    let isochrone = pow(1.0 - abs(fract(smoothIter * 0.5) - 0.5) * 2.0, 10.0);
    color = color + vec3<f32>(0.45, 0.25, 0.95) * linearity * (0.22 + isochrone * 0.6) * (0.6 + p3 * 0.8) * convergence;
    color = color + vec3<f32>(1.0, 0.9, 0.7) * quadratic * isochrone * 0.18 * (1.0 + treble * 0.6);

    // Reaction-diffusion accent on basin boundaries
    let idims = vec2<i32>(res);
    let prevTex = textureLoad(dataTextureC, pixel, 0);
    let c0 = unpackState(prevTex.a);
    let cR = sampleState(pixel + vec2<i32>(1, 0), idims, c0);
    let cL = sampleState(pixel + vec2<i32>(-1, 0), idims, c0);
    let cT = sampleState(pixel + vec2<i32>(0, 1), idims, c0);
    let cB = sampleState(pixel + vec2<i32>(0, -1), idims, c0);
    let lap = cR + cL + cT + cB - 4.0 * c0;

    let feed = trapGlow * (1.0 - trapGlow) * 4.0;
    let rdState = clamp(c0 + 0.25 * (0.22 * lap + feed - 0.16 * c0), 0.0, 1.0);
    color = color + vec3<f32>(0.95, 0.2, 0.35) * rdState * (0.4 + bloom * 0.6);

    // Subtle temporal color feedback
    let prevColor = prevTex.rgb;
    color = mix(color, prevColor * 0.96, 0.03);

    // Chromatic aberration + ACES
    let caStr = 0.0025 * (1.0 + bass) + convergence * 0.001;
    color = genChromaticShift(color, uv01, caStr, time);
    color = acesToneMap(color * (1.05 + mids * 0.15));

    // Semantic alpha & depth
    let vignette = clamp(1.0 - length(uv01 - vec2<f32>(0.5)) * 1.15, 0.0, 1.0);
    let convAlpha = clamp(convergence * (1.0 - trapGlow * 0.25) * vignette, 0.0, 1.0);
    let alpha = floor(convAlpha * 255.0) / 256.0 + rdState * (0.999 / 256.0);
    let depth = convergence * (0.8 + iterRatio * 0.2);
    let finalRGBA = vec4<f32>(color, alpha);

    textureStore(writeTexture, pixel, finalRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, pixel, finalRGBA);
}
