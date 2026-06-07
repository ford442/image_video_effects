// ─────────────────────────────────────────────────────────────────────────────
//  Hyperbolic Tessellation Engine
//  Category: GENERATIVE
//  Complexity: VERY HIGH
//  Visual concept: Non-Euclidean Poincaré-disk tessellation rendered in
//    real-time. Hyperbolic tiles subdivide infinitely toward the boundary,
//    colored by recursive depth — M.C. Escher meets fractals.
//  Mathematical approach: Poincaré disk model with Möbius transformation
//    orbit-trapping; each pixel is iteratively mapped to the fundamental
//    domain via hyperbolic isometries; depth=iteration count; color from HSV
//    with depth-derived hue; mouse steers the hyperbolic origin.
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
    zoom_params: vec4<f32>, // x=TileSymmetry(3-8), y=DepthColor, z=RotSpeed, w=BoundaryGlow
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  HSV → RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c  = v * s;
    let h6 = fract(h) * 6.0;
    let x  = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
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
//  Complex arithmetic
// ─────────────────────────────────────────────────────────────────────────────
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b, b) + 1e-12;
    return vec2<f32>(dot(a, b), a.y*b.x - a.x*b.y) / d;
}
fn cconj(z: vec2<f32>) -> vec2<f32> { return vec2<f32>(z.x, -z.y); }

// ─────────────────────────────────────────────────────────────────────────────
//  Poincaré-disk Möbius translation: moves point c to origin
//  T_c(z) = (z - c) / (1 - conj(c) * z)
// ─────────────────────────────────────────────────────────────────────────────
fn poincareMobius(z: vec2<f32>, c: vec2<f32>) -> vec2<f32> {
    return cdiv(z - c, vec2<f32>(1.0, 0.0) - cmul(cconj(c), z));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hyperbolic rotation (pure rotation in Poincaré disk = usual complex rotation)
// ─────────────────────────────────────────────────────────────────────────────
fn hypRot(z: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle); let c = cos(angle);
    return vec2<f32>(c*z.x - s*z.y, s*z.x + c*z.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Fold z into fundamental domain of {p,q} tessellation.
//  Uses a "reflection" approach: reflect across each generator until inside.
//  Returns (folded_z, iteration_count).
// ─────────────────────────────────────────────────────────────────────────────
fn tessellate(z_in: vec2<f32>, p: f32, q: f32, maxIter: i32) -> vec2<f32> {
    // Vertex of fundamental triangle at origin for {p,q}
    // cosh(edge_length) = cos(π/p)*cos(π/q)/sin(π/p)/sin(π/q) ... simplified
    let r = cos(3.14159265 / p) / sin(3.14159265 * (0.5 - 1.0/q) + 3.14159265/p);
    var z = z_in;
    // Iteratively reflect across the p generator edges
    for (var i = 0; i < maxIter; i++) {
        let zLen2 = dot(z, z);
        if (zLen2 > 0.999) { break; }
        // Reflection across circle of radius r centered at (r, 0)
        let d2 = dot(z - vec2<f32>(r, 0.0), z - vec2<f32>(r, 0.0));
        let rr = r * 0.7; // reflection circle radius
        if (d2 < rr * rr) {
            // Invert through circle
            z = vec2<f32>(r, 0.0) + cdiv(vec2<f32>(rr * rr, 0.0), cconj(z - vec2<f32>(r, 0.0)));
        }
        // Rotate by 2π/p to try next edge
        z = hypRot(z, 6.28318 / p);
    }
    return z;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Orbit trap: measure how close z comes to a reference set
// ─────────────────────────────────────────────────────────────────────────────
fn orbitTrap(z: vec2<f32>, center: vec2<f32>, radius: f32) -> f32 {
    return smoothstep(radius, 0.0, length(z - center));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth noise for tile texture
// ─────────────────────────────────────────────────────────────────────────────
fn h2_ht(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn vnoise_ht(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f*f*(3.0-2.0*f);
    return mix(mix(h2_ht(i),h2_ht(i+vec2<f32>(1,0)),u.x),mix(h2_ht(i+vec2<f32>(0,1)),h2_ht(i+vec2<f32>(1,1)),u.x),u.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hyperbolic distance in Poincaré disk
// ─────────────────────────────────────────────────────────────────────────────
fn hypDist(z1: vec2<f32>, z2: vec2<f32>) -> f32 {
    let d  = length(z1 - z2);
    let d1 = 1.0 - dot(z1, z1);
    let d2 = 1.0 - dot(z2, z2);
    let arg = clamp(1.0 + 2.0 * d * d / max(d1 * d2, 1e-8), 1.0, 1e6);
    return log(arg + sqrt(arg * arg - 1.0));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tile interior texture: adds Escher-like creature pattern as noise
// ─────────────────────────────────────────────────────────────────────────────
fn tileTexture(z: vec2<f32>, depth: f32, t: f32) -> f32 {
    let scale = 8.0 * (1.0 + depth * 2.0);
    let n1 = vnoise_ht(z * scale + vec2<f32>(t * 0.02, 0.0));
    let n2 = vnoise_ht(z * scale * 2.0 + vec2<f32>(0.0, t * 0.015));
    return n1 * 0.6 + n2 * 0.4;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Geodesic distance to nearest lattice line (for tile edge rendering)
// ─────────────────────────────────────────────────────────────────────────────
fn geodesicEdge(z: vec2<f32>, p: f32) -> f32 {
    var minDist = 1e9;
    for (var k = 0; k < 8; k++) {
        let angle = 6.28318 * f32(k) / p;
        let dir = vec2<f32>(cos(angle), sin(angle)) * 0.3;
        let edgeD = abs(dot(z, vec2<f32>(-dir.y, dir.x)));
        minDist = min(minDist, edgeD);
    }
    return exp(-minDist * 30.0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    let uv    = vec2<f32>(gid.xy) / res;
    let t     = u.config.x;
    let mouse = u.zoom_config.yz;

    // Parameters
    let tileSym    = u.zoom_params.x * 5.0 + 3.0;   // p: 3 – 8
    let depthColor = u.zoom_params.y;                  // hue offset 0-1
    let rotSpeed   = u.zoom_params.z * 0.3 - 0.15;   // -0.15 – 0.15 rad/s
    let boundGlow  = u.zoom_params.w;                  // 0 – 1

    // Map UV to Poincaré disk (aspect-correct, within radius 0.97)
    let aspect = res.x / res.y;
    var z = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 1.94;
    let diskRadius = length(z);
    if (diskRadius >= 0.98) {
        // Outside disk: boundary color
        let boundary = smoothstep(0.98, 1.0, diskRadius);
        let bgColor  = hsv2rgb(t * 0.05 + depthColor, 0.6, boundary * boundGlow * 0.5);
        textureStore(writeTexture, gid.xy, vec4<f32>(bgColor, 1.0));
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(0.0, 0.0, 0.0, 1.0));
        return;
    }

    // Apply time-varying global rotation
    z = hypRot(z, t * rotSpeed);

    // Shift disk center toward mouse
    let mCenter = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 0.5;
    let mLen = length(mCenter);
    var safeCenter = mCenter;
    if (mLen > 0.9) { safeCenter = mCenter * (0.9 / mLen); }
    z = poincareMobius(z, safeCenter);

    // ── Iterative tessellation ────────────────────────────────────────────
    let p = floor(tileSym);
    let q = 3.0; // {p, 3} tessellation
    let maxIter = 24;
    var iter = 0;
    var zz = z;

    for (var k = 0; k < maxIter; k++) {
        let prev = zz;
        zz = tessellate(zz, p, q, 3);
        // Count meaningful moves
        if (length(zz - prev) > 0.001) { iter++; }
    }

    // ── Depth from iteration count ────────────────────────────────────────
    let depth = f32(iter) / f32(maxIter);

    // ── Orbit trap for edge lines ─────────────────────────────────────────
    let edgeLine = orbitTrap(zz, vec2<f32>(0.0), 0.08);
    let vertexGlow = orbitTrap(zz, vec2<f32>(cos(t * 0.7) * 0.15, sin(t * 0.5) * 0.15), 0.05);

    // ── Color mapping ─────────────────────────────────────────────────────
    let hue  = fract(depth * 0.7 + depthColor + t * 0.04);
    let sat  = 0.7 + depth * 0.3;
    let val  = 0.15 + (1.0 - depth) * 0.7 + edgeLine * 0.4 + vertexGlow * 0.6;

    // Boundary glow: brighter toward disk edge
    let glowFalloff = smoothstep(0.7, 0.97, diskRadius) * boundGlow;
    let glowHue     = fract(hue + 0.5);
    var col = hsv2rgb(hue, sat, clamp(val, 0.0, 1.0));
    col = mix(col, hsv2rgb(glowHue, 1.0, 1.0), glowFalloff * 0.4);

    // Tile edge darkening
    col *= (1.0 - edgeLine * 0.6);
    col += hsv2rgb(fract(hue + 0.15), 0.9, 1.0) * edgeLine * 0.3;

    // ── Tile interior texture (Escher-like) ───────────────────────────────
    let tileDetail = tileTexture(zz, depth, t) * (1.0 - edgeLine);
    col = mix(col, col * (0.7 + tileDetail * 0.6), 0.5);

    // ── Geodesic edge lines ───────────────────────────────────────────────
    let geoEdge = geodesicEdge(zz, p);
    col = mix(col, hsv2rgb(fract(hue + 0.25), 1.0, 1.0), geoEdge * 0.5 * (1.0 - depth));

    // ── Hyperbolic distance-based fog ─────────────────────────────────────
    let hypD = hypDist(z, vec2<f32>(0.0));
    let fog  = exp(-hypD * 0.15);
    col = mix(hsv2rgb(fract(t * 0.04 + 0.6), 0.3, 0.08), col, fog);

    // ── Animated iridescence on tile faces ───────────────────────────────
    let iridPhase = depth * 4.0 + t * 0.07 + length(zz) * 5.0;
    let iridColor = hsv2rgb(fract(iridPhase * 0.5), 0.9, 0.4) * (1.0 - edgeLine);
    col = clamp(col + iridColor * depth * 0.3, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, gid.xy, vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
