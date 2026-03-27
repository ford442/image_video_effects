// ─────────────────────────────────────────────────────────────────────────────
//  Inverse Mandelbrot Realm
//  Category: GENERATIVE
//  Complexity: VERY HIGH
//  Visual concept: Instead of iterating coordinates in the complex plane, we
//    iterate color-space vectors through the Mandelbrot map. Each pixel's RGB
//    becomes a complex number that orbits, accumulates, and escapes — creating
//    alien fractal color fields that change with every parameter tweak.
//  Mathematical approach: Treat (R+iG) as a complex number z; iterate
//    z → z² + c where c is derived from position; track whether the color
//    vector escapes; use smooth colouring with orbit traps on the B channel.
//    Result: fractal structure in color-space, not position-space.
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
    zoom_params: vec4<f32>, // x=Iterations, y=ColorZoom, z=CmapRotate, w=BailoutRadius
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Complex multiplication
// ─────────────────────────────────────────────────────────────────────────────
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

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
//  Value noise
// ─────────────────────────────────────────────────────────────────────────────
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
//  Smooth escape-count (continuous coloring)
// ─────────────────────────────────────────────────────────────────────────────
struct MandResult {
    escaped:  bool,
    smooth_n: f32,  // smooth iteration count [0, maxIter]
    orbit_min: f32, // minimum |z| during orbit (orbit trap)
    final_z:  vec2<f32>,
};

fn inverseMandelbrot(c: vec2<f32>, z0: vec2<f32>, maxIter: i32, bailout: f32) -> MandResult {
    var z = z0;
    var orbitMin = 1e9;
    var res: MandResult;
    res.escaped  = false;
    res.smooth_n = 0.0;
    res.orbit_min = 0.0;
    res.final_z  = z;

    for (var n = 0; n < maxIter; n++) {
        // Standard Mandelbrot iteration: z → z² + c
        z = cmul(z, z) + c;
        let len2 = dot(z, z);
        orbitMin = min(orbitMin, length(z));
        if (len2 > bailout * bailout) {
            // Smooth coloring: n + 1 - log2(log2(|z|))
            let sn = f32(n) + 1.0 - log2(log2(sqrt(len2)));
            res.escaped  = true;
            res.smooth_n = sn;
            res.orbit_min = orbitMin;
            res.final_z  = z;
            return res;
        }
    }
    res.orbit_min = orbitMin;
    res.final_z   = z;
    return res;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Map UV to parameter space (with zoom, pan, mouse)
// ─────────────────────────────────────────────────────────────────────────────
fn uvToC(uv: vec2<f32>, zoom: f32, center: vec2<f32>, t: f32) -> vec2<f32> {
    let aspect = 1.0; // handled outside
    let c = (uv - 0.5) * 2.5 / zoom + center;
    return c;
}

// ─────────────────────────────────────────────────────────────────────────────
//  FBM for fractal texture layering
// ─────────────────────────────────────────────────────────────────────────────
fn fbm_im(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 3; i++) {
        v += a * vnoise(pp);
        pp = pp * 2.1 + vec2<f32>(5.2, 1.3);
        a *= 0.5;
    }
    return v;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Julia set probe: a secondary fractal derived from the same point
//  (color-space iteration with a fixed c)
// ─────────────────────────────────────────────────────────────────────────────
fn juliaColorProbe(z_in: vec2<f32>, c: vec2<f32>, iterations: i32, bailout: f32) -> f32 {
    var z = z_in;
    for (var n = 0; n < iterations; n++) {
        z = cmul(z, z) + c;
        if (dot(z, z) > bailout * bailout) {
            return f32(n) / f32(iterations);
        }
    }
    return 0.0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dwell bands: stripe coloring using iteration count mod
// ─────────────────────────────────────────────────────────────────────────────
fn dwellBand(smooth_n: f32, maxIter: f32, bandWidth: f32, t: f32) -> f32 {
    let band = fract(smooth_n / bandWidth + t * 0.02);
    return smoothstep(0.4, 0.6, band) * smoothstep(0.6, 0.4, band) * 2.0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Escape-time normal for pseudo-3D shading
// ─────────────────────────────────────────────────────────────────────────────
fn escapeNormal(c: vec2<f32>, z0: vec2<f32>, maxIter: i32, bailout: f32) -> vec2<f32> {
    var z = z0;
    var dz = vec2<f32>(1.0, 0.0); // derivative
    for (var n = 0; n < maxIter; n++) {
        dz = cmul(dz, z) * 2.0 + vec2<f32>(1.0, 0.0);
        z  = cmul(z, z) + c;
        if (dot(z, z) > bailout * bailout) { break; }
    }
    let len = length(dz);
    if (len < 1e-8) { return vec2<f32>(0.0, 1.0); }
    return normalize(dz / len);
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

    let maxIter    = i32(u.zoom_params.x * 60.0 + 20.0);  // 20 – 80
    let colorZoom  = u.zoom_params.y * 3.0 + 0.5;          // 0.5 – 3.5
    let cmapRot    = u.zoom_params.z * 2.0;                  // 0 – 2 (hue offset)
    let bailout    = u.zoom_params.w * 8.0 + 2.0;           // 2 – 10

    let aspect = res.x / res.y;

    // ── Coordinate mapping ─────────────────────────────────────────────────
    // c: position-space parameter (the "c" in z² + c)
    // Slowly pan through the Mandelbrot set, center on mouse
    let panX = sin(t * 0.04) * 0.3 + (mouse.x - 0.5) * 0.5;
    let panY = cos(t * 0.031) * 0.2 + (mouse.y - 0.5) * 0.4;
    let center = vec2<f32>(-0.5 + panX, panY);

    let aspectUV = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let c = aspectUV * 2.5 / colorZoom + center;

    // ── Color-space initial vector (z0): derived from position noise ───────
    // This is the "inverse" part: z0 is a color-like vector, not just (0,0)
    let noiseX = vnoise(uv * 5.0 + vec2<f32>(t * 0.02, 0.0)) * 2.0 - 1.0;
    let noiseY = vnoise(uv * 5.0 + vec2<f32>(0.0, t * 0.017)) * 2.0 - 1.0;
    let z0 = vec2<f32>(noiseX, noiseY) * 0.3;

    // ── Iterate ────────────────────────────────────────────────────────────
    let result = inverseMandelbrot(c, z0, maxIter, bailout);

    // ── Coloring ───────────────────────────────────────────────────────────
    var col: vec3<f32>;

    if (!result.escaped) {
        // Interior: color by orbit trap
        let interior = result.orbit_min;
        let hue = fract(interior * 3.0 + cmapRot + t * 0.03);
        col = hsv2rgb(hue, 0.7, 0.3 + interior * 0.4);
    } else {
        // Exterior: smooth iteration count coloring
        let sn = result.smooth_n / f32(maxIter);

        // Primary color: smooth iteration count → hue
        let hue1 = fract(sn * 2.5 + cmapRot + t * 0.05);
        let sat1 = 0.8 + sn * 0.2;
        let val1 = 0.7 + sn * 0.3;
        let baseCol = hsv2rgb(hue1, sat1, val1);

        // Orbit trap color: minimum distance → secondary hue
        let orbitHue = fract(result.orbit_min * 5.0 + cmapRot + 0.5 + t * 0.03);
        let orbitCol = hsv2rgb(orbitHue, 1.0, 1.0);

        // Blend based on escape speed
        let blendFactor = smoothstep(0.0, 0.4, sn);
        col = mix(baseCol, orbitCol, blendFactor * 0.4);

        // Edge-sharpening: use |final_z| for fine detail
        let fz = length(result.final_z);
        let edgeDetail = fract(fz * 3.0) * 0.15;
        col += hsv2rgb(fract(hue1 + 0.33), 1.0, 1.0) * edgeDetail;
    }

    // ── Ripple interaction: distort c slightly near ripples ────────────────
    let ripCount = u32(u.config.y);
    var ripDistort = 0.0;
    for (var i: u32 = 0u; i < ripCount; i++) {
        let r   = u.ripples[i];
        let age = t - r.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let d   = distance(uv, r.xy);
        ripDistort += sin(d * 25.0 - age * 5.0) * exp(-d * 6.0) * exp(-age * 1.5) * 0.3;
    }
    col = mix(col, hsv2rgb(fract(length(c) * 0.7 + t * 0.1 + cmapRot), 1.0, 1.0),
              abs(ripDistort) * 0.3);

    // ── Dwell band overlay (alternate coloring) ────────────────────────────
    if (result.escaped) {
        let band = dwellBand(result.smooth_n, f32(maxIter), 4.0, t);
        col = mix(col, col * (1.0 + band * 0.4), 0.5);
    }

    // ── Julia probe secondary color ────────────────────────────────────────
    let juliaC  = vec2<f32>(sin(t * 0.07) * 0.3, cos(t * 0.05) * 0.3);
    let juliaT  = juliaColorProbe(z0 + c * 0.1, juliaC, maxIter / 2, bailout);
    let juliaH  = fract(juliaT * 3.0 + cmapRot + 0.25 + t * 0.04);
    col = mix(col, hsv2rgb(juliaH, 0.9, 0.8), juliaT * 0.35);

    // ── Escape-time pseudo-3D shading ─────────────────────────────────────
    let escN = escapeNormal(c, z0, maxIter, bailout);
    let lightDir = normalize(vec2<f32>(cos(t * 0.12), sin(t * 0.09)));
    let diffuse = dot(escN, lightDir) * 0.5 + 0.5;
    col = col * (0.6 + diffuse * 0.4);

    // ── FBM texture on interior ────────────────────────────────────────────
    if (!result.escaped) {
        let fbmTex = fbm_im(c * 8.0 + t * 0.01);
        col = mix(col, col * (0.5 + fbmTex), 0.4);
    }

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    let depthOut = select(0.2, result.smooth_n / f32(maxIter), result.escaped);
    textureStore(writeTexture, gid.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
}
