// ═══════════════════════════════════════════════════════════════════════════════
//  Inverse Mandelbrot Realm
//  Category: GENERATIVE | Complexity: VERY_HIGH
//  Inverse/reciprocal iteration in color-space rather than position-space.
//  Instead of z → z² + c, we iterate color vectors: c → f(c, z) where z is
//  the spatial coordinate. Generates alien fractals where colors iterate instead
//  of coordinates—a completely novel aesthetic.
//  Mathematical approach: Color-space Mandelbrot with reciprocal mapping,
//  quaternion iteration for 3-channel color, escape-time coloring in RGB
//  dimensions, Julia set morphing via mouse position.
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=IterMode, y=MouseX, z=MouseY, w=Saturation
    zoom_params: vec4<f32>,  // x=Zoom, y=MaxIter, z=ColorRotSpeed, w=InversePower
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Complex operations
// ─────────────────────────────────────────────────────────────────────────────
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b, b) + 1e-12;
    return vec2<f32>(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / d;
}

fn cpow(z: vec2<f32>, n: f32) -> vec2<f32> {
    let r = length(z);
    let theta = atan2(z.y, z.x);
    let rn = pow(r + 1e-10, n);
    return rn * vec2<f32>(cos(n * theta), sin(n * theta));
}

// ─────────────────────────────────────────────────────────────────────────────
//  3D "tricomplex" multiplication for color-space iteration
//  Extends complex multiplication to 3 components using quaternion-like rules
// ─────────────────────────────────────────────────────────────────────────────
fn triMul(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        a.x * b.x - a.y * b.y - a.z * b.z,
        a.x * b.y + a.y * b.x + a.z * b.z * 0.5,
        a.x * b.z + a.z * b.x + a.y * b.y * 0.5
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reciprocal in color space: 1/c where c is a 3D color vector
// ─────────────────────────────────────────────────────────────────────────────
fn triReciprocal(c: vec3<f32>) -> vec3<f32> {
    let d = dot(c, c) + 1e-8;
    return vec3<f32>(c.x, -c.y, -c.z) / d;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hash
// ─────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ─────────────────────────────────────────────────────────────────────────────
//  HSV to RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(h6 % 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Color-space Mandelbrot iteration
//  Instead of z → z² + c (position), we do:
//  color → f(color, position) where f uses tricomplex arithmetic
//  The "escape" happens in color-magnitude space
// ─────────────────────────────────────────────────────────────────────────────
fn colorMandelbrot(pos: vec2<f32>, juliaC: vec2<f32>, maxIter: i32, invPower: f32, mode: f32, time: f32) -> vec4<f32> {
    // Initial color seeded from position
    var c = vec3<f32>(pos.x, pos.y, sin(pos.x * pos.y + time * 0.1) * 0.5);

    // Julia constant embedded in color space
    let jc = vec3<f32>(juliaC.x * 0.8, juliaC.y * 0.8, sin(time * 0.3) * 0.3);

    var z = c;
    var escaped = false;
    var iter = 0;
    var colorAccum = vec3<f32>(0.0);
    var orbitTrap = 1e5;

    for (var i = 0; i < 64; i++) {
        if (i >= maxIter) { break; }

        // === Iteration modes ===
        if (mode < 0.33) {
            // Mode 1: Standard tricomplex Mandelbrot
            // z → z² + c (in color space)
            z = triMul(z, z) + c;
        } else if (mode < 0.66) {
            // Mode 2: Reciprocal iteration (the "inverse" part)
            // z → 1/z^n + c
            let zp = triMul(z, z);
            z = triReciprocal(zp) * invPower + c;
        } else {
            // Mode 3: Hybrid—alternates between forward and inverse
            if (i % 2 == 0) {
                z = triMul(z, z) + c;
            } else {
                z = triReciprocal(z) * invPower + jc;
            }
        }

        // Track orbit trap: minimum distance to origin in color space
        let mag = length(z);
        orbitTrap = min(orbitTrap, mag);

        // Accumulate color from orbit (for smooth coloring)
        colorAccum += abs(z) / f32(maxIter);

        // Escape condition in color space
        if (mag > 4.0) {
            escaped = true;
            iter = i;
            break;
        }
        iter = i;
    }

    // Smooth iteration count for anti-aliasing
    let smoothIter = f32(iter) + 1.0 - log(log(length(z) + 1e-6)) / log(2.0);

    return vec4<f32>(colorAccum, smoothIter);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = (fragCoord * 2.0 - dims) / dims.y;
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let zoom = exp(u.zoom_params.x * 4.0 - 2.0);           // 0.13 – 7.4
    let maxIter = i32(u.zoom_params.y * 40.0 + 16.0);      // 16 – 56
    let colorRotSpeed = u.zoom_params.z * 0.3 + 0.02;      // 0.02 – 0.32
    let invPower = u.zoom_params.w * 3.0 + 0.5;            // 0.5 – 3.5
    let iterMode = u.zoom_config.x;                          // 0 – 1
    let saturation = u.zoom_config.w * 0.6 + 0.4;          // 0.4 – 1.0

    // Julia constant from mouse position
    let mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mouseY = (u.zoom_config.z / dims.y) * 2.0 - 1.0;
    let juliaC = vec2<f32>(mouseX, mouseY) * 0.8;

    // ─────────────────────────────────────────────────────────────────────────
    //  Slow pan and zoom animation
    // ─────────────────────────────────────────────────────────────────────────
    let panX = sin(time * 0.07) * 0.3;
    let panY = cos(time * 0.05) * 0.2;
    let pos = uv / zoom + vec2<f32>(panX, panY);

    // ─────────────────────────────────────────────────────────────────────────
    //  Run color-space fractal iteration
    // ─────────────────────────────────────────────────────────────────────────
    let result = colorMandelbrot(pos, juliaC, maxIter, invPower, iterMode, time);
    let colorAccum = result.xyz;
    let smoothIter = result.w;

    // ─────────────────────────────────────────────────────────────────────────
    //  Coloring: the accumulated color orbit IS the color
    //  This is the key insight—we're iterating colors, so the orbit itself
    //  contains the visual information
    // ─────────────────────────────────────────────────────────────────────────

    // Normalize accumulated color
    var col = colorAccum * 3.0;

    // Rotate hue over time for living, breathing fractal
    let hueAngle = time * colorRotSpeed;
    let cosH = cos(hueAngle);
    let sinH = sin(hueAngle);
    let rotated = vec3<f32>(
        col.r * cosH - col.g * sinH,
        col.r * sinH + col.g * cosH,
        col.b
    );
    col = abs(rotated);

    // Iteration-based secondary coloring
    let iterColor = hsv2rgb(
        fract(smoothIter * 0.03 + time * 0.01),
        saturation,
        0.9
    );
    col = mix(col, iterColor, 0.35);

    // ─────────────────────────────────────────────────────────────────────────
    //  Deep interior: special coloring for non-escaping regions
    // ─────────────────────────────────────────────────────────────────────────
    if (smoothIter >= f32(maxIter) - 1.0) {
        // Inside the set: use orbit trap coloring
        let trapColor = hsv2rgb(
            fract(length(colorAccum) * 2.0 + time * 0.05),
            0.6 * saturation,
            0.3 + length(colorAccum) * 0.4
        );
        col = trapColor;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: perturbation in color-parameter space
    // ─────────────────────────────────────────────────────────────────────────
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let rUV = (r.xy * 2.0 - 1.0);
        let dist = length(uv - rUV);
        let age = time - r.z;
        if (age > 0.0 && age < 4.0) {
            let wave = exp(-abs(dist - age * 0.5) * 10.0) * exp(-age * 0.6);
            let waveColor = hsv2rgb(fract(dist * 3.0 + age), 0.9, 1.0);
            col += waveColor * wave * 0.3;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Final processing
    // ─────────────────────────────────────────────────────────────────────────
    // Vignette
    col *= 1.0 - 0.3 * dot(uv, uv) * 0.3;

    // Tone mapping
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
