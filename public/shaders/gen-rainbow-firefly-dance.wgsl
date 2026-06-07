// ═══════════════════════════════════════════════════════════════════
//  Rainbow Firefly Dance
//  Category: generative
//  Features: firefly, rainbow, dance, audio-reactive, mouse-interactive,
//            semantic-alpha, aces-tone-mapping, chromatic-aberration,
//            temporal-feedback, depth-aware
//  Complexity: Medium
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// Simple hash
fn hash2(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

// Value noise
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// 2D rotation
fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Rainbow color from hue
fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k.xyz) * 6.0 - 3.0);
    return clamp(p - 0.5, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Firefly glow with soft halo
fn fireflyGlow(pos: vec2<f32>, center: vec2<f32>, radius: f32, intensity: f32) -> f32 {
    let d = length(pos - center);
    let core = exp(-d * d / (radius * radius * 0.08));
    let halo = exp(-d * d / (radius * radius * 0.8));
    return core * 1.5 + halo * 0.4 * intensity;
}

// ACES tone mapping
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Compute firefly field at a given UV (for chromatic aberration)
fn fireflyField(
    uv: vec2<f32>, time: f32, speed: f32, scale: f32,
    colorShift: f32, intensity: f32, bass: f32, numFireflies: i32,
    mouseNorm: vec2<f32>, mouseDown: f32
) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    let bassPulse = 1.0 + bass * 0.5;
    for (var i: i32 = 0; i < numFireflies; i = i + 1) {
        let fi = f32(i);
        let seed = hash1(fi * 17.31);
        let seed2 = hash1(fi * 43.71 + 100.0);

        // Base orbit parameters
        let orbitRadius = 0.15 + seed * 0.5;
        let orbitSpeed = (0.2 + seed2 * 0.8) * speed;
        let orbitPhase = seed * TAU + fi * 0.3;

        // Organic swirling motion
        let t = time * orbitSpeed + orbitPhase;
        let swirlX = cos(t * 0.7 + seed * 3.0) * orbitRadius;
        let swirlY = sin(t * 0.9 + seed2 * 2.0) * orbitRadius;

        // Additional turbulence
        let turb = vec2<f32>(
            vnoise(vec2<f32>(fi * 0.1, time * 0.3 * speed)) - 0.5,
            vnoise(vec2<f32>(fi * 0.1 + 50.0, time * 0.25 * speed)) - 0.5
        ) * 0.3;

        // Firefly position
        var fPos = vec2<f32>(swirlX, swirlY) + turb;

        // Mouse attraction
        let toMouse = mouseNorm - fPos;
        let mouseDist = length(toMouse);
        let attractStrength = mouseDown * 0.3 * intensity + (1.0 - mouseDown) * 0.05;
        fPos += normalize(toMouse + vec2<f32>(0.001)) * attractStrength / (mouseDist + 0.3);

        // Scale firefly size with bass pulse
        let fSize = (0.008 + 0.012 * sin(time * 2.0 * speed * bassPulse + fi) * intensity) * scale;

        // Rainbow color
        let hue = fract(fi / f32(numFireflies) + time * 0.15 * speed + colorShift + seed * 0.3);
        let fColor = hue2rgb(hue);

        // Brightness pulsing
        let pulse = 0.7 + 0.3 * sin(time * 3.0 * speed + fi * 1.7);

        // Glow
        let glow = fireflyGlow(uv, fPos, fSize, intensity);
        col += fColor * glow * pulse * intensity * 2.5;
    }
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);
    let time = u.config.x;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouseDown = u.zoom_config.w;
    let mouseNorm = (mouse - resolution * 0.5) / min(resolution.x, resolution.y);

    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // ═══ AUDIO REACTIVITY ═══
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ═══ DEPTH AWARENESS ═══
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel) / resolution, 0.0).r;
    let depthFactor = 0.5 + depth * 0.5;

    var col = vec3<f32>(0.0);

    // Background gradient
    let bgHue = fract(time * 0.02 * speed + colorShift * 0.5 + bass * 0.05);
    let bgCol = hue2rgb(bgHue) * 0.06;
    col += bgCol + vec3<f32>(0.02, 0.01, 0.04);

    // Organic flowing field background
    let flow1 = vnoise(uv * 3.0 * scale + vec2<f32>(time * 0.1 * speed, time * 0.07 * speed));
    let flow2 = vnoise(uv * 5.0 * scale + vec2<f32>(-time * 0.08 * speed, time * 0.12 * speed));
    let flow = flow1 * flow2;
    col += hue2rgb(fract(flow + time * 0.03 * speed + colorShift + treble * 0.1)) * flow * 0.15 * intensity * (1.0 + mids * 0.2);

    // ═══ TEMPORAL FEEDBACK ═══
    let prevFrame = textureLoad(dataTextureC, pixel, 0);
    let trailDecay = 0.92;
    var trailColor = prevFrame.rgb * trailDecay;

    // ═══ CHROMATIC ABERRATION ON FIREFLY GLOW ═══
    let caStrength = 0.003 * intensity * (1.0 + bass);
    let numFireflies = i32(80.0 * (1.0 + bass * 0.3));
    let effIntensity = intensity * depthFactor;

    let rField = fireflyField(uv + vec2<f32>(caStrength, 0.0), time, speed, scale, colorShift, effIntensity, bass, numFireflies, mouseNorm, mouseDown);
    let gField = fireflyField(uv, time, speed, scale, colorShift, effIntensity, bass, numFireflies, mouseNorm, mouseDown);
    let bField = fireflyField(uv - vec2<f32>(caStrength, 0.0), time, speed, scale, colorShift, effIntensity, bass, numFireflies, mouseNorm, mouseDown);
    var fireflyCol = vec3<f32>(rField.r, gField.g, bField.b);

    // Additive blend with phosphorescent trail
    col = max(col, trailColor * 0.5);
    col += trailColor * 0.3;
    col += fireflyCol;

    // Vignette for depth
    let vig = 1.0 - dot(uv * 0.8, uv * 0.8);
    col *= clamp(vig, 0.0, 1.0) * 1.2;

    // ═══ ACES TONE MAPPING ═══
    col = acesToneMap(col * 2.0);
    col = pow(col, vec3<f32>(0.9));

    // ═══ SEMANTIC ALPHA ═══
    let totalGlow = length(fireflyCol) + length(trailColor);
    let alpha = clamp(totalGlow * depthFactor * (1.0 + bass) * 0.5, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthFactor * 0.5 + totalGlow * 0.1, 0.0, 0.0, 0.0));
}
