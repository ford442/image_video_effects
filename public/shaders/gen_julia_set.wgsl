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
    let c      = cR * vec2<f32>(cos(cAngle), sin(cAngle * 1.618)); // golden ratio winding

    // Map pixel to complex plane
    let scale = 2.5 / zoom;
    var z     = (uv - 0.5) * vec2<f32>(scale * aspect, scale);

    // ─── Julia iteration with orbit trap accumulation ───
    let maxIter = 128;
    var smoothed = 0.0;
    var trapDist = 1e9;
    var i        = 0;

    for (i = 0; i < maxIter; i++) {
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

        if (dot(z, z) > 65536.0) { break; }
    }

    var color: vec3<f32>;
    if (i >= maxIter) {
        // Interior — color by trap distance (captured orbit)
        let trapNorm = clamp(1.0 - trapDist * 0.5, 0.0, 1.0);
        color = hsv2rgb(fract(trapNorm * 3.0 + time * 0.05), 0.8, 0.3 + trapNorm * 0.6);
    } else {
        // Exterior — smooth iteration + trap modulation
        smoothed = smoothIter(f32(i), z);
        let mu    = clamp(smoothed / f32(maxIter), 0.0, 1.0);
        // Base hue from smooth iteration
        let hue   = fract(mu * 4.0 + time * 0.1 + treble * 0.1);
        let sat   = 0.85;
        let val   = pow(mu, 0.4) * 0.9;
        color = hsv2rgb(hue, sat, val);
        // Overlay trap coloring (bright streaks where orbit passed close)
        let trapGlow = exp(-trapDist * 3.0);
        let trapHue  = fract(trapDist * 1.5 + time * 0.07);
        color = mix(color, hsv2rgb(trapHue, 1.0, 1.0), trapGlow * 0.6);
    }

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

    // ─── Temporal feedback ───
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    finalColor = mix(finalColor, prev.rgb * 0.9, 0.03 + bass * 0.01);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(smoothed / f32(maxIter), trapDist, f32(i) / f32(maxIter), 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
