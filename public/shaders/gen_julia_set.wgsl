// ═══════════════════════════════════════════════════════════════════════════════
//  Julia Set / Newton Fractal — Smooth Iteration + Orbit Trap Coloring
//  Category: generative
//  Features: procedural, animated, audio-reactive, temporal, chromatic, depth-aware
//  Complexity: High
//  Scientific: Generalized Julia iteration z_{n+1} = z^n + c for n=2..6,
//              smooth (continuous) iteration μ = i − log₂(log₂|z|),
//              multi-trap orbit coloring: circle trap, line trap, cross trap,
//              animated Julia parameter c orbiting a cardioid,
//              audio-driven trap scale and mode selection
//  Upgraded: Phase B, 2026-05-31
//  Optimizer pass, 2026-07-22: bass-driven Lissajous c-morph (mouse drag
//              overrides), interior filament detail from the iteration
//              derivative, 2-sample hash-jitter rotated-grid AA, pre-tint
//              temporal accumulation clamped at 1.2 (luma-echo-warp lesson).
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,  // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Zoom, y=Power, z=TrapMode, w=TrapScale
    ripples:     array<vec4<f32>, 50>,
}

const PI: f32  = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ─── Hash library (canonical codebase forms) ───
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

// Complex z^n via polar form
fn cpow(z: vec2<f32>, n: f32) -> vec2<f32> {
    let r = length(z);
    let th = atan2(z.y, z.x);
    return pow(r, n) * vec2<f32>(cos(n*th), sin(n*th));
}

// Smooth (Munafo) iteration count: μ = i − log₂(log₂|z|)
fn smoothIter(i: f32, z: vec2<f32>) -> f32 {
    let lz = log(length(z));
    return i - log2(max(log2(lz), 0.0001));
}

// ─── Orbit trap functions ───
// Returns min distance to trap shape accumulated over all iterates
fn circTrap(z: vec2<f32>, radius: f32) -> f32 {
    return abs(length(z) - radius);
}
fn lineTrap(z: vec2<f32>) -> f32 {
    return abs(z.y);           // real axis
}
fn crossTrap(z: vec2<f32>) -> f32 {
    return min(abs(z.x), abs(z.y));
}

// HSV → RGB
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let hi = floor(h * 6.0);
    let f  = h * 6.0 - hi;
    let p  = v * (1.0 - s);
    let q  = v * (1.0 - f * s);
    let t  = v * (1.0 - (1.0 - f) * s);
    let m  = i32(hi) % 6;
    if (m == 0) { return vec3<f32>(v, t, p); }
    if (m == 1) { return vec3<f32>(q, v, p); }
    if (m == 2) { return vec3<f32>(p, v, t); }
    if (m == 3) { return vec3<f32>(p, q, v); }
    if (m == 4) { return vec3<f32>(t, p, v); }
    return vec3<f32>(v, p, q);
}

// ACES tone map — keeps trap glow highlights from clipping
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Single-sample Julia evaluation ───
// Runs the z^n+c orbit with trap accumulation and an iteration-derivative
// filament accumulator (banded change of |z| between successive iterates).
struct JuliaSample {
    col:      vec3<f32>,
    smoothed: f32,
    trapDist: f32,
    iterNorm: f32,
    interior: f32,
}

fn juliaRender(z0: vec2<f32>, c: vec2<f32>, power: f32, trapMode: f32,
               trapScale: f32, time: f32, treble: f32) -> JuliaSample {
    let maxIter = 128;
    var z        = z0;
    var zPrev    = z0;
    var trapDist = 1e9;
    var filAcc   = 0.0;
    var smoothed = 0.0;
    var i        = 0;

    for (i = 0; i < maxIter; i++) {
        zPrev = z;
        z = cpow(z, power) + c;

        // Accumulate min trap distance
        var td = 0.0;
        if (trapMode < 0.33) {
            td = circTrap(z, trapScale);
        } else if (trapMode < 0.67) {
            td = lineTrap(z);
        } else {
            td = crossTrap(z);
        }
        trapDist = min(trapDist, td);

        // Iteration-derivative filament accumulator: orbit-speed bands
        let dz = length(z) - length(zPrev);
        filAcc += 0.5 + 0.5 * sin(dz * 22.0 + f32(i) * 0.35);

        if (dot(z, z) > 65536.0) { break; }
    }

    var out: JuliaSample;
    out.trapDist = trapDist;
    out.iterNorm = f32(i) / f32(maxIter);

    if (i >= maxIter) {
        // Interior — fine filament detail instead of flat color
        let fil      = filAcc / f32(maxIter);
        let trapNorm = clamp(1.0 - trapDist * 0.5, 0.0, 1.0);
        let bands    = 0.5 + 0.5 * sin(fil * 21.0 + trapNorm * 9.0);
        let hue      = fract(trapNorm * 1.5 + fil * 0.7 + time * 0.05);
        let val      = 0.10 + bands * (0.22 + trapNorm * 0.45);
        out.col      = hsv2rgb(hue, 0.85, val);
        out.smoothed = f32(maxIter);
        out.interior = 1.0;
    } else {
        // Exterior — smooth iteration + trap modulation
        smoothed = smoothIter(f32(i), z);
        let mu    = clamp(smoothed / f32(maxIter), 0.0, 1.0);
        // Base hue from smooth iteration
        let hue   = fract(mu * 4.0 + time * 0.1 + treble * 0.1);
        let sat   = 0.85;
        let val   = pow(mu, 0.4) * 0.9;
        var col   = hsv2rgb(hue, sat, val);
        // Overlay trap coloring (bright streaks where orbit passed close)
        let trapGlow = exp(-trapDist * 3.0);
        let trapHue  = fract(trapDist * 1.5 + time * 0.07);
        col = mix(col, hsv2rgb(trapHue, 1.0, 1.0), trapGlow * 0.6);
        out.col      = col;
        out.smoothed = smoothed;
        out.interior = 0.0;
    }
    return out;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let zoom     = mix(0.2, 3.0, u.zoom_params.x);
    let power    = mix(2.0, 6.0, u.zoom_params.y);      // z^n exponent
    let trapMode = u.zoom_params.z;                       // 0=circle,0.5=line,1=cross
    let trapScale= mix(0.2, 1.5, u.zoom_params.w) * (1.0 + bass * 0.3);

    // Animated Julia parameter c orbiting a cardioid-like path
    let cAngle = time * 0.3 + mids * 0.5;
    let cR     = 0.7885;                                  // near Mandelbrot boundary
    var c      = cR * vec2<f32>(cos(cAngle), sin(cAngle * 1.618)); // golden ratio winding

    // Audio c-morph: slow Lissajous perturbation, amplitude follows bass —
    // the set breathes with the music
    let lissAmp = 0.06 + bass * 0.22;
    c += lissAmp * vec2<f32>(sin(time * 0.71), sin(time * 1.13 + 1.31));

    // Mouse drag overrides the orbit: cursor position becomes c directly
    if (u.zoom_config.w > 0.5) {
        c = (u.zoom_config.yz - vec2<f32>(0.5, 0.5)) * vec2<f32>(1.6, -1.6);
    }

    // Map pixel to complex plane
    let scale = 2.5 / zoom;
    let baseP = (uv - 0.5) * vec2<f32>(scale * aspect, scale);

    // ─── Hash-jitter AA: 2-sample rotated grid, one half-pixel apart ───
    let jAng = hash21(vec2<f32>(global_id.xy)) * TAU;
    let jRad = 0.35 * (scale / resolution.y);           // sub-pixel in complex units
    let jOff = vec2<f32>(cos(jAng), sin(jAng)) * jRad;

    let sA = juliaRender(baseP + jOff, c, power, trapMode, trapScale, time, treble);
    let sB = juliaRender(baseP - jOff, c, power, trapMode, trapScale, time, treble);

    var color     = (sA.col + sB.col) * 0.5;
    let smoothed  = (sA.smoothed + sB.smoothed) * 0.5;
    let trapDist  = min(sA.trapDist, sB.trapDist);
    let iterNorm  = (sA.iterNorm + sB.iterNorm) * 0.5;
    let interior  = max(sA.interior, sB.interior);

    // Blend with input texture
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    var finalColor = mix(inputColor.rgb, color, 0.9);

    // ─── Chromatic dispersion ───
    let chrStrength = 0.004 + bass * 0.008;
    let chrR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chrStrength * (1.0 + mids * 0.5), 0.0), 0.0).r;
    let chrG = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, chrStrength * (1.0 + treble * 0.3)), 0.0).g;
    let chrB = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-chrStrength * 0.7 * (1.0 + bass * 0.4), chrStrength * 0.3), 0.0).b;
    let chrColor = vec3<f32>(chrR, chrG, chrB);
    finalColor = mix(finalColor, chrColor, 0.2 + bass * 0.15);

    // Pre-tint clamp: temporal accumulation can never exceed 1.2
    // (luma-echo-warp lesson — unbounded feedback blooms into white mush)
    finalColor = min(finalColor, vec3<f32>(1.2));

    // ─── Temporal feedback (clamped history, short trail) ───
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevSafe = min(prev.rgb, vec3<f32>(1.2));
    finalColor = mix(finalColor, prevSafe * 0.9, 0.03 + bass * 0.01);

    // ─── Tone map ───
    finalColor = acesToneMap(finalColor);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(smoothed / 128.0, trapDist, iterNorm, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
