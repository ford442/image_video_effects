// ═══════════════════════════════════════════════════════════════════
//  Neon Acid Geometry
//  Category: generative
//  Features: neon, acid, geometry, audio-reactive, mouse-interactive,
//            semantic-alpha, upgraded-rgba, temporal, chromatic-aberration
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-07
//  By: Kimi Agent Upgrade
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

// ═══ CHUNK: acesToneMap (standard ACES) ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: phToColor (universal indicator pH→RGB) ═══
// pH 0-3: strong acid → red
// pH 4-6: weak acid → orange/yellow
// pH 7:   neutral → green
// pH 8-10: weak base → blue
// pH 11-14: strong base → purple
fn phToColor(ph: f32) -> vec3<f32> {
    let p = clamp(ph, 0.0, 14.0);
    let c0 = vec3<f32>(1.0, 0.0, 0.2);   // pH 0  strong acid
    let c1 = vec3<f32>(1.0, 0.6, 0.0);   // pH 3.5 weak acid
    let c2 = vec3<f32>(0.0, 0.8, 0.3);   // pH 7   neutral
    let c3 = vec3<f32>(0.0, 0.4, 1.0);   // pH 9   weak base
    let c4 = vec3<f32>(0.6, 0.0, 1.0);   // pH 14  strong base
    let t1 = smoothstep(0.0, 3.5, p);
    let t2 = smoothstep(3.5, 7.0, p);
    let t3 = smoothstep(7.0, 9.0, p);
    let t4 = smoothstep(9.0, 14.0, p);
    var col = mix(c0, c1, t1);
    col = mix(col, c2, t2);
    col = mix(col, c3, t3);
    col = mix(col, c4, t4);
    return col;
}

// ═══ CHUNK: Snell's Law / Critical Angle ═══
fn snellRefract(incident: f32, n1: f32, n2: f32) -> f32 {
    let sinTheta2 = (n1 / n2) * sin(incident);
    return asin(clamp(sinTheta2, -1.0, 1.0));
}

fn criticalAngle(n1: f32, n2: f32) -> f32 {
    return asin(clamp(n2 / n1, 0.0, 1.0));
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

    // pH oscillation driven by bass: 0→14→0 cycle
    let phCycle = 7.0 + 7.0 * sin(time * (0.5 + bass * 2.0));

    // Critical-angle refraction distortion (water-air ~48.6°)
    let crit = criticalAngle(1.33, 1.0);
    let refractUV = uv * (1.0 + sin(crit) * 0.1 * bass);

    var col = vec3<f32>(0.0);

    // Deep psychedelic background tinted by pH
    let bgNoise = fbm(refractUV * 2.0 * scale, time * 0.1 * speed);
    let bgHue = fract(bgNoise * 0.3 + time * 0.04 * speed + colorShift);
    col += phToColor(fract(bgHue * 14.0)) * bgNoise * 0.15;
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
            let localUV = rot2(rotAngle) * (refractUV - center);

            // Scale pulsing
            let shapeScale = (0.04 + 0.03 * sin(time * 2.0 * speed + seed * 5.0) * audioIntensity) * pulse;

            // Select shape type based on seed
            let shapeType = floor(seed * 3.0);
            var shapeDist: f32 = 1000.0;

            if (shapeType < 1.0) {
                // Triangle with melting distortion — mids control drip speed
                let melt = vec2<f32>(
                    vnoise(localUV * 8.0 + time * speed * (2.0 + mids * 3.0)) * 0.015,
                    vnoise(localUV * 8.0 + time * speed * (2.0 + mids * 3.0) + 50.0) * 0.015
                ) * audioIntensity;
                shapeDist = sdTriangle(localUV + melt, shapeScale);
            } else if (shapeType < 2.0) {
                // Hexagon — mids control distortion rate
                let melt = vec2<f32>(
                    vnoise(localUV * 6.0 + time * speed * (1.5 + mids * 2.0)) * 0.012,
                    vnoise(localUV * 6.0 + time * speed * (1.5 + mids * 2.0) + 30.0) * 0.012
                ) * audioIntensity;
                shapeDist = sdHexagon(localUV + melt, shapeScale * 1.2);
            } else {
                // Circle with wobble
                let wobble = vnoise(localUV * 10.0 + time * speed * 3.0) * 0.01 * audioIntensity;
                shapeDist = sdCircle(localUV, shapeScale + wobble);
            }

            // pH-based color: seed offsets phase, bass drives oscillation
            let shapePH = fract(seed + phCycle / 14.0 + colorShift + beat * 0.2) * 14.0;
            let shapeCol = phToColor(shapePH);

            // Neon glow from shape edge with acid/base transitions
            let glow1 = sdfGlow(abs(shapeDist), 0.012 * audioIntensity * pulse, 2.5);
            let glow2 = sdfGlow(abs(shapeDist), 0.035 * audioIntensity * pulse, 0.8);
            let fill = smoothstep(0.005, -0.005, shapeDist) * 0.6;

            // Additive contribution
            col += shapeCol * glow1 * audioIntensity * 1.5;
            col += shapeCol * glow2 * audioIntensity * 0.5;
            col += shapeCol * fill * audioIntensity * 0.8;

            // Mouse-reactive explosion at cursor with localized pH disturbance
            let toMouse = length(refractUV - mouseNorm);
            let mouseInfluence = smoothstep(0.3, 0.0, toMouse) * mouseDown;
            if (mouseInfluence > 0.01) {
                let mouseDist = length(localUV) * (1.0 + mouseInfluence * 3.0);
                let mouseGlow = exp(-mouseDist * mouseDist * 80.0) * mouseInfluence;
                // Mouse toggles between acid (pH 2) and base (pH 12) splashes
                let mousePH = select(2.0, 12.0, mouseDown > 0.5 && hash1(seed + time) > 0.5);
                col += phToColor(mousePH) * mouseGlow * audioIntensity * 3.0;
            }
        }
    }

    // Global overlay: morphing acid waves tinted by pH
    let wave1 = sin(refractUV.x * 8.0 * scale + time * 2.0 * speed) * cos(refractUV.y * 6.0 * scale - time * 1.5 * speed);
    let wave2 = sin(refractUV.x * 5.0 * scale - time * speed + refractUV.y * 7.0 * scale) * 0.5;
    let wave = (wave1 + wave2) * 0.5;
    let waveGlow = smoothstep(0.3, 0.8, abs(wave)) * 0.15 * audioIntensity;
    col += phToColor(fract(wave * 7.0 + phCycle * 0.5)) * waveGlow;

    // Treble-driven bubble sparkle
    let sparkle = hash2(vec2<f32>(floor(refractUV * 40.0)));
    let sparkleTrigger = step(1.0 - treble * 0.3, sparkle);
    col += phToColor(fract(sparkle * 14.0)) * sparkleTrigger * treble * 2.0;

    // ═══ TEMPORAL FEEDBACK ═══
    let prev = textureSampleLevel(dataTextureC, u_sampler, (vec2<f32>(pixel) + 0.5) / resolution, 0.0);
    col = mix(prev.rgb * 0.96, col, 0.25);
    textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));

    // ═══ CHROMATIC ABERRATION ═══
    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Vignette
    let vig = 1.0 - dot(uv * 0.7, uv * 0.7);
    col *= clamp(vig, 0.0, 1.0) * 1.3;

    // ═══ ACES TONE MAP + SEMANTIC ALPHA ═══
    col = acesToneMap(col * 1.1);
    let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
}
