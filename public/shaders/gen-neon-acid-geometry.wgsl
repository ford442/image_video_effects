// ═══════════════════════════════════════════════════════════════════
//  Neon Acid Geometry
//  Category: generative
//  Features: neon, acid, geometry, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium-High
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

// Hash functions
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

// Fractal Brownian Motion
fn fbm(p: vec2<f32>, t: f32) -> f32 {
    var val: f32 = 0.0;
    var amp: f32 = 0.5;
    var freq: f32 = 1.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        val += amp * vnoise(p * freq + t * 0.3);
        freq *= 2.0;
        amp *= 0.5;
    }
    return val;
}

// 2D rotation matrix
fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Neon acid palette
fn acidColor(t: f32) -> vec3<f32> {
    // Electric lime -> hot magenta -> neon orange -> electric cyan
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(TAU * (c * t + d));
}

// Triangle SDF
fn sdTriangle(p: vec2<f32>, r: f32) -> f32 {
    let k = sqrt(3.0);
    let q = abs(p);
    return max(q.x - r, max(q.x + k * p.y, q.x - k * p.y) * 0.5);
}

// Hexagon SDF
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let q = abs(p);
    return max(q.x - r * 0.866, max(q.x * 0.5 + q.y * 0.866 - r * 0.866, q.y - r * 0.5));
}

// Circle SDF
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// Smooth minimum for blending shapes
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Glow from SDF
fn sdfGlow(d: f32, width: f32, audioIntensity: f32) -> f32 {
    return smoothstep(width, 0.0, d) * audioIntensity;
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

    var audioIntensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let audioSpeed = speed * (0.8 + bass * 0.7);
    audioIntensity = audioIntensity * (0.85 + treble * 0.6);
    let audioColor = colorShift + mids * 0.25;

    var col = vec3<f32>(0.0);

    // Deep psychedelic background
    let bgNoise = fbm(uv * 2.0 * scale, time * 0.1 * speed);
    let bgHue = fract(bgNoise * 0.3 + time * 0.04 * speed + colorShift);
    col += acidColor(bgHue) * bgNoise * 0.15;
    col += vec3<f32>(0.02, 0.0, 0.04);

    // Beat-like rhythm
    let beat = pow(abs(sin(time * 1.5 * speed)), 4.0);
    let pulse = 1.0 + beat * 0.4 * audioIntensity;

    // Grid of shape centers
    let gridCount = 4;
    for (var gx: i32 = -gridCount; gx <= gridCount; gx = gx + 1) {
        for (var gy: i32 = -gridCount; gy <= gridCount; gy = gy + 1) {
            let center = vec2<f32>(f32(gx), f32(gy)) * (0.18 / scale);
            let seed = hash2(vec2<f32>(f32(gx) + 50.0, f32(gy) + 100.0));
            let seed2 = hash1(f32(gx * 7 + gy * 13) + 200.0);

            // Local UV rotated and scaled
            let rotAngle = time * speed * (0.3 + seed * 0.7) + seed2 * TAU + beat * 0.5;
            let localUV = rot2(rotAngle) * (uv - center);

            // Scale pulsing
            let shapeScale = (0.04 + 0.03 * sin(time * 2.0 * speed + seed * 5.0) * audioIntensity) * pulse;

            // Select shape type based on seed
            let shapeType = floor(seed * 3.0);
            var shapeDist: f32 = 1000.0;

            if (shapeType < 1.0) {
                // Triangle with melting distortion
                let melt = vec2<f32>(
                    vnoise(localUV * 8.0 + time * speed * 2.0) * 0.015,
                    vnoise(localUV * 8.0 + time * speed * 2.0 + 50.0) * 0.015
                ) * audioIntensity;
                shapeDist = sdTriangle(localUV + melt, shapeScale);
            } else if (shapeType < 2.0) {
                // Hexagon
                let melt = vec2<f32>(
                    vnoise(localUV * 6.0 + time * speed * 1.5) * 0.012,
                    vnoise(localUV * 6.0 + time * speed * 1.5 + 30.0) * 0.012
                ) * audioIntensity;
                shapeDist = sdHexagon(localUV + melt, shapeScale * 1.2);
            } else {
                // Circle with wobble
                let wobble = vnoise(localUV * 10.0 + time * speed * 3.0) * 0.01 * audioIntensity;
                shapeDist = sdCircle(localUV, shapeScale + wobble);
            }

            // Color for this shape
            let hue = fract(seed + time * 0.1 * speed + colorShift + beat * 0.2);
            let shapeCol = acidColor(hue);

            // Neon glow from shape edge
            let glow1 = sdfGlow(abs(shapeDist), 0.012 * audioIntensity * pulse, 2.5);
            let glow2 = sdfGlow(abs(shapeDist), 0.035 * audioIntensity * pulse, 0.8);
            let fill = smoothstep(0.005, -0.005, shapeDist) * 0.6;

            // Additive contribution
            col += shapeCol * glow1 * audioIntensity * 1.5;
            col += shapeCol * glow2 * audioIntensity * 0.5;
            col += shapeCol * fill * audioIntensity * 0.8;

            // Mouse-reactive explosion at cursor
            let toMouse = length(uv - mouseNorm);
            let mouseInfluence = smoothstep(0.3, 0.0, toMouse) * mouseDown;
            if (mouseInfluence > 0.01) {
                let mouseDist = length(localUV) * (1.0 + mouseInfluence * 3.0);
                let mouseGlow = exp(-mouseDist * mouseDist * 80.0) * mouseInfluence;
                col += acidColor(fract(seed + colorShift + 0.5)) * mouseGlow * audioIntensity * 3.0;
            }
        }
    }

    // Global overlay: morphing acid waves
    let wave1 = sin(uv.x * 8.0 * scale + time * 2.0 * speed) * cos(uv.y * 6.0 * scale - time * 1.5 * speed);
    let wave2 = sin(uv.x * 5.0 * scale - time * speed + uv.y * 7.0 * scale) * 0.5;
    let wave = (wave1 + wave2) * 0.5;
    let waveGlow = smoothstep(0.3, 0.8, abs(wave)) * 0.15 * audioIntensity;
    col += acidColor(fract(time * 0.08 * speed + colorShift + wave * 0.2)) * waveGlow;

    // Chromatic aberration effect
    let ca = vnoise(uv * 3.0 + time * speed) * 0.03 * audioIntensity;
    col.r += ca * 0.3;
    col.b -= ca * 0.2;

    // Vignette
    let vig = 1.0 - dot(uv * 0.7, uv * 0.7);
    col *= clamp(vig, 0.0, 1.0) * 1.3;

    // Tone map
    col = col / (1.0 + col * 0.25);
    col = pow(col, vec3<f32>(0.92));

    // Brightness boost
    col = col * 2.0;

    // Semantic alpha
    let effect = clamp(dot(col, vec3<f32>(0.4, 0.4, 0.3)) * 1.2, 0.5, 0.98);
    textureStore(writeTexture, pixel, vec4<f32>(col, effect));
}
