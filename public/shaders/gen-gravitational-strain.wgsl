// ─────────────────────────────────────────────────────────────────────────────
//  Gravitational Strain Field
//  Category: GENERATIVE
//  Complexity: VERY HIGH
//  Visual concept: Invisible gravity wells warp space itself. We render the
//    curvature of space as visual distortion, with bright emission at field
//    collision zones — dark matter visualization as fine art.
//  Mathematical approach: N gravity wells each contribute a metric tensor
//    deformation to the ray. Rays are traced along geodesics by integrating
//    dv/ds = -∇Φ where Φ = Σ -GM/r. Lensed image is sampled from a
//    procedural star-field background. Tidal forces emit color where |∇²Φ|
//    is large (field gradient maxima).
// ─────────────────────────────────────────────────────────────────────────────
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
    config:      vec4<f32>, // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=unused, y=MouseX, z=MouseY, w=unused
    zoom_params: vec4<f32>, // x=WellCount(1-6), y=WellMass, z=BendStrength, w=EmissionScale
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  HSV → RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s; let h6 = fract(h) * 6.0;
    let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if      (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + (v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hash / noise
// ─────────────────────────────────────────────────────────────────────────────
fn h1(n: f32) -> f32 { return fract(sin(n * 127.1 + 311.7) * 43758.5); }
fn h2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h2(i), h2(i+vec2<f32>(1,0)), u.x), mix(h2(i+vec2<f32>(0,1)), h2(i+vec2<f32>(1,1)), u.x), u.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gravitational potential Φ at 2-D position p from N wells
// ─────────────────────────────────────────────────────────────────────────────
fn gravPotential(p: vec2<f32>, wells: array<vec3<f32>, 6>, n: i32) -> f32 {
    var phi = 0.0;
    for (var i = 0; i < n; i++) {
        let wpos = wells[i].xy;
        let mass = wells[i].z;
        let r    = length(p - wpos) + 0.05;
        phi     -= mass / r;
    }
    return phi;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gravitational gradient ∇Φ
// ─────────────────────────────────────────────────────────────────────────────
fn gravGrad(p: vec2<f32>, wells: array<vec3<f32>, 6>, n: i32) -> vec2<f32> {
    var g = vec2<f32>(0.0);
    for (var i = 0; i < n; i++) {
        let wpos = wells[i].xy;
        let mass = wells[i].z;
        let d    = p - wpos;
        let r2   = dot(d, d) + 0.0025;
        g       += d * mass / (r2 * sqrt(r2));
    }
    return -g;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Procedural star field
// ─────────────────────────────────────────────────────────────────────────────
fn starField(uv: vec2<f32>, t: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    // Multiple scales of star density
    let scales = array<f32, 3>(40.0, 80.0, 160.0);
    for (var s = 0; s < 3; s++) {
        let sc  = scales[s];
        let cell = floor(uv * sc);
        let frac = fract(uv * sc);
        let seed = h2(cell + vec2<f32>(f32(s) * 73.1, 0.0));
        if (seed > 0.97) {
            let starPos = vec2<f32>(h2(cell + 1.0), h2(cell + 2.0));
            let dist    = length(frac - starPos);
            let twinkle = 0.7 + 0.3 * sin(t * (seed * 5.0 + 1.0) + seed * 100.0);
            let bright  = exp(-dist * sc * 0.4) * twinkle;
            let hue     = fract(seed * 3.7 + t * 0.01);
            col        += hsv2rgb(hue, 0.3 + seed * 0.4, bright * 0.8 / f32(s + 1));
        }
    }
    // Nebula glow
    let nebHue = fract(vnoise(uv * 3.0 + t * 0.005) + t * 0.01);
    col += hsv2rgb(nebHue, 0.6, vnoise(uv * 6.0 + t * 0.01) * 0.12);
    return col;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tidal emission: bright where field curvature (∇²Φ) is large
// ─────────────────────────────────────────────────────────────────────────────
fn tidalEmission(p: vec2<f32>, wells: array<vec3<f32>, 6>, n: i32, t: f32) -> vec3<f32> {
    let eps = 0.01;
    let phi  = gravPotential(p, wells, n);
    let phiR = gravPotential(p + vec2<f32>(eps, 0.0), wells, n);
    let phiL = gravPotential(p - vec2<f32>(eps, 0.0), wells, n);
    let phiU = gravPotential(p + vec2<f32>(0.0, eps), wells, n);
    let phiD = gravPotential(p - vec2<f32>(0.0, eps), wells, n);
    let laplacian = abs((phiR + phiL + phiU + phiD - 4.0 * phi) / (eps * eps));

    // Also add gradient magnitude (shear stress)
    let gx = (phiR - phiL) / (2.0 * eps);
    let gy = (phiU - phiD) / (2.0 * eps);
    let gradMag = length(vec2<f32>(gx, gy));

    let emission = clamp(laplacian * 0.03 + gradMag * 0.5, 0.0, 3.0);
    let hue = fract(phi * 0.3 + t * 0.08);
    return hsv2rgb(hue, 0.9, 1.0) * emission;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res    = u.config.zw;
    let uv     = vec2<f32>(gid.xy) / res;
    let t      = u.config.x;
    let mouse  = u.zoom_config.yz;

    let wellCount   = i32(u.zoom_params.x * 5.0 + 1.5);   // 1 – 6
    let wellMass    = u.zoom_params.y * 0.08 + 0.01;        // 0.01 – 0.09
    let bendStrength = u.zoom_params.z * 0.15 + 0.02;       // 0.02 – 0.17
    let emScale     = u.zoom_params.w * 3.0 + 0.5;          // 0.5 – 3.5

    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    // ── Set up gravity wells ───────────────────────────────────────────────
    var wells: array<vec3<f32>, 6>;
    for (var i = 0; i < 6; i++) {
        let seed = f32(i) * 13.7;
        let orbitR = h1(seed) * 0.25 + 0.1;
        let orbitS = (h1(seed + 1.0) * 0.5 + 0.3) * (select(-1.0, 1.0, i32(h1(seed + 2.0) * 10.0) % 2 == 0));
        let angle  = orbitS * t + h1(seed + 3.0) * 6.28318;
        let wx     = cos(angle) * orbitR * aspect;
        let wy     = sin(angle) * orbitR;
        let mass   = wellMass * (h1(seed + 4.0) * 0.8 + 0.4);
        wells[i] = vec3<f32>(wx, wy, mass);
    }
    // Add mouse-controlled well
    let mouseWell = vec2<f32>((mouse.x - 0.5) * aspect, mouse.y - 0.5);
    wells[0] = vec3<f32>(mouseWell.x, mouseWell.y, wellMass * 1.5);

    // ── Ray deflection: trace geodesic via Euler integration ─────────────
    var rayPos = p;
    var rayVel = vec2<f32>(0.0);
    let steps  = 20;
    let stepSz = 1.0 / f32(steps);

    for (var s = 0; s < steps; s++) {
        let acc  = gravGrad(rayPos, wells, wellCount) * bendStrength;
        rayVel  += acc * stepSz;
        rayPos  += rayVel * stepSz;
    }

    // ── Sample lensed star field ───────────────────────────────────────────
    let lensedUV = (rayPos / vec2<f32>(aspect, 1.0) + 0.5);
    let stars    = starField(lensedUV, t);

    // ── Tidal emission ────────────────────────────────────────────────────
    let emission = tidalEmission(p, wells, wellCount, t) * emScale;

    // ── Schwarzschild-like darkening near wells ───────────────────────────
    var darkening = 1.0;
    for (var i = 0; i < wellCount; i++) {
        let d     = length(p - wells[i].xy);
        let rs    = wells[i].z * 2.0; // Schwarzschild-like radius
        darkening *= 1.0 - exp(-d * d / (rs * rs * 0.1)) * 0.85;
    }

    // ── Ripple: adds temporary extra gravity well ─────────────────────────
    let ripCount = u32(u.config.y);
    var ripEmission = vec3<f32>(0.0);
    for (var i: u32 = 0u; i < ripCount; i++) {
        let r   = u.ripples[i];
        let age = t - r.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let rp  = (r.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let d   = length(p - rp);
        let ring = exp(-(d - age * 0.3) * (d - age * 0.3) * 80.0) * exp(-age * 1.5);
        ripEmission += hsv2rgb(fract(age * 0.4), 0.9, ring * 2.0);
    }

    // ── Compose ───────────────────────────────────────────────────────────
    var col = stars * darkening + emission + ripEmission;
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth: gravitational potential (normalized)
    let phi = gravPotential(p, wells, wellCount);
    let depthOut = clamp((-phi) / (wellMass * f32(wellCount) * 20.0), 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
}
