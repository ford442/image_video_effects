// ═══════════════════════════════════════════════════════════════════
//  Julia Set — Orbit Trap
//  Category: generative
//  Features: procedural, animated, audio-reactive, temporal, chromatic,
//            depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13, 2026-11-01
//  Ideas: smooth trap-mode interpolation; velocity |Δz| trap; distance-estimate boundary filaments (log|dz| derivative); interior multiplier banding (Fatou attractor bands)
//  A packing: raw HDR display RGBA (ACES on writeTexture)
//  Scientific: z^n+c n=2..6, smooth μ, circle/line/cross traps,
//              c orbiting a cardioid, mouse-drag c override
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Zoom, y=Power, z=TrapMode, w=TrapScale

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
    velTrap:  f32,
    deNorm:   f32,
}

fn juliaRender(z0: vec2<f32>, c: vec2<f32>, power: f32, trapMode: f32,
               trapScale: f32, time: f32, treble: f32, pxSize: f32) -> JuliaSample {
    let maxIter = 128;
    var z        = z0;
    var zPrev    = z0;
    var trapDist = 1e9;
    var velTrap  = 1e9;
    var filAcc   = 0.0;
    var logDz    = 0.0;   // log|dz/dz0| accumulated in the log domain (never overflows)
    var smoothed = 0.0;
    var i        = 0;

    for (i = 0; i < maxIter; i++) {
        zPrev = z;
        // 2026-11 ideas 1+2: derivative of z^n + c is n z^(n-1); only its magnitude is needed.
        logDz += log(power) + (power - 1.0) * log(max(length(z), 1e-6));
        z = cpow(z, power) + c;

        // Idea 1 — lerp circle↔line↔cross along Trap Mode instead of three bins
        let tdCirc = circTrap(z, trapScale);
        let tdLine = lineTrap(z);
        let tdCross = crossTrap(z);
        let tdA = mix(tdCirc, tdLine, smoothstep(0.0, 0.5, trapMode));
        let tdB = mix(tdLine, tdCross, smoothstep(0.5, 1.0, trapMode));
        let td = mix(tdA, tdB, step(0.5, trapMode));
        trapDist = min(trapDist, td);

        // Idea 2 — velocity trap: stall glow where |Δz| is tiny
        velTrap = min(velTrap, length(z - zPrev));

        // Iteration-derivative filament accumulator: orbit-speed bands
        let dz = length(z) - length(zPrev);
        filAcc += 0.5 + 0.5 * sin(dz * 22.0 + f32(i) * 0.35);

        if (dot(z, z) > 65536.0) { break; }
    }

    var out: JuliaSample;
    out.trapDist = trapDist;
    out.velTrap  = velTrap;
    out.iterNorm = f32(i) / f32(maxIter);
    out.deNorm   = 1e3;

    if (i >= maxIter) {
        // Interior — fine filament detail instead of flat color
        let fil      = filAcc / f32(maxIter);
        let trapNorm = clamp(1.0 - trapDist * 0.5, 0.0, 1.0);
        let bands    = 0.5 + 0.5 * sin(fil * 21.0 + trapNorm * 9.0);
        let hue      = fract(trapNorm * 1.5 + fil * 0.7 + time * 0.05);
        let val      = 0.10 + bands * (0.22 + trapNorm * 0.45);
        let velGlow  = exp(-velTrap * 18.0);
        // 2026-11 Idea 2: interior multiplier banding. logDz / maxIter is the mean log multiplier of
        // the attracting cycle: 0 at the set's boundary, strongly negative near an attractor, so it
        // varies smoothly across each Fatou component and bands it around its attractor.
        let multiplier = clamp(-logDz / f32(maxIter), 0.0, 4.0);
        let fatouBands = 0.5 + 0.5 * sin(multiplier * 7.0 + time * 0.2);
        let fatouHue   = fract(hue + multiplier * 0.08);
        out.col      = hsv2rgb(fatouHue, 0.85, val * (0.7 + 0.6 * fatouBands)) + vec3<f32>(0.85, 0.55, 1.05) * velGlow * 0.22;
        out.smoothed = f32(maxIter);
        out.interior = 1.0;
    } else {
        // Exterior — smooth iteration + trap modulation
        smoothed = smoothIter(f32(i), z);
        let mu    = clamp(smoothed / f32(maxIter), 0.0, 1.0);
        let hue   = fract(mu * 4.0 + time * 0.1 + treble * 0.1);
        let sat   = 0.85;
        let val   = pow(mu, 0.4) * 0.9;
        var col   = hsv2rgb(hue, sat, val);
        let trapGlow = exp(-trapDist * 3.0);
        let trapHue  = fract(trapDist * 1.5 + time * 0.07);
        col = mix(col, hsv2rgb(trapHue, 1.0, 1.0), trapGlow * 0.6);
        let velGlow = exp(-velTrap * 18.0);
        col = mix(col, hsv2rgb(fract(trapHue + 0.18), 0.9, 1.0), velGlow * 0.4);
        // 2026-11 Idea 1: distance-estimate filaments. DE = 0.5 |z| ln|z| / |dz|, measured in pixels;
        // a thin warm lace hugs the true boundary of the set, including the filaments the
        // escape-time bands miss.
        let rEsc = max(length(z), 2.0);
        let logDe = log(0.5 * rEsc * log(rEsc)) - logDz;
        out.deNorm = exp(clamp(logDe, -12.0, 12.0)) / max(pxSize, 1e-6);
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

    let pxSize = scale / resolution.y;                   // complex units per pixel
    let sA = juliaRender(baseP + jOff, c, power, trapMode, trapScale, time, treble, pxSize);
    let sB = juliaRender(baseP - jOff, c, power, trapMode, trapScale, time, treble, pxSize);

    var color     = (sA.col + sB.col) * 0.5;
    let deMin     = min(sA.deNorm, sB.deNorm);
    // Width calibrated on SwiftShader (128 px, default c): at exp(-de*0.35) over 10 % of pixels were > 0.8,
    // a flood, not a filament; exp(-de*1.2) keeps the lace to a sub-pixel-to-one-pixel line.
    let lace      = exp(-deMin * 1.2);
    color += vec3<f32>(1.0, 0.82, 0.55) * lace * (0.35 + treble * 0.3);
    let trapDist  = min(sA.trapDist, sB.trapDist);
    let interior  = max(sA.interior, sB.interior);
    let velTrap   = min(sA.velTrap, sB.velTrap);

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
    finalColor = min(finalColor, vec3<f32>(1.2));

    let pixel = vec2<i32>(global_id.xy);
    let prev = textureLoad(dataTextureC, pixel, 0);
    let prevSafe = min(prev.rgb, vec3<f32>(1.2));
    finalColor = mix(finalColor, prevSafe * 0.9, 0.03 + bass * 0.01);

    let trapGlow = exp(-trapDist * 3.0);
    let velGlow = exp(-velTrap * 18.0);
    let alpha = clamp(0.08 + (1.0 - interior) * 0.5 + interior * 0.22 + trapGlow * 0.28 + velGlow * 0.18 + lace * 0.2, 0.05, 0.98);

    textureStore(dataTextureA, pixel, vec4<f32>(finalColor, alpha));
    textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(finalColor), alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
