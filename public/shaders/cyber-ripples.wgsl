// ═══════════════════════════════════════════════════════════════════
//  Cyber Ripples
//  Category: interactive-mouse
//  Features: mouse-driven, wave, neon, audio-reactive, upgraded-rgba,
//            temporal-feedback, depth-aware, click-shockwave, aces-tone-map,
//            domain-warped-fbm, audio-palette, sdf-ring-mask
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-07-08
// ═══════════════════════════════════════════════════════════════════
//  Hybrid techniques combined:
//  1. Quantized mouse-driven ripple displacement
//  2. Domain-warped FBM turbulence
//  3. Audio-driven cyber palette shifting
//  4. SDF ring masking with smooth minimum
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const QUANT_STEP: f32 = 24.0;
const ATTEN_SCALE: f32 = 5.0;
const DISP_AMP: f32 = 0.01;
const EPS: f32 = 0.001;

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn neonGlow(color: vec3<f32>, intensity: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.0));
    let lum = dot(safeColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let glowMask = smoothstep(0.22, 1.0, lum);
    let chroma = normalize(safeColor + vec3<f32>(0.001)) * max(lum, 0.18);
    let bloom = (safeColor * safeColor + chroma) * glowMask * max(intensity, 0.0);
    return safeColor + bloom;
}

fn hash21(p: vec2<f32>) -> f32 {
    let n = sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453;
    return fract(n);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v: f32 = 0.0;
    var a: f32 = 0.5;
    var pp = p;
    let rot = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);
    for (var i: i32 = 0; i < 4; i = i + 1) {
        v += a * noise(pp);
        pp = rot * pp * 2.0;
        a *= 0.5;
    }
    return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn sdfRings(p: vec2<f32>, mouse: vec2<f32>, time: f32) -> f32 {
    let d = length(p - mouse);
    let r0 = abs(d - 0.12 - sin(time * 1.3) * 0.03);
    let r1 = abs(d - 0.24 - cos(time * 0.9) * 0.04);
    let r2 = abs(d - 0.36 + sin(time * 0.7) * 0.02);
    return smin(smin(r0, r1, 0.08), r2, 0.08);
}

fn audioPalette(t: f32, bass: f32, treble: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557) + vec3<f32>(treble * 0.3, -bass * 0.2, bass * 0.4);
    return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    let prev = textureLoad(dataTextureC, pixel, 0);
    let env = bass_env(prev.a, bass, 0.8, 0.15);

    let speed = p1 * 5.0 + 1.0;
    let blockSize = p2 * 0.1;
    let aberration = p3 * 0.05;
    let frequency = p4 * 50.0 + 10.0;
    let fbmAmp = p2 * 0.04 + 0.005;

    let aspect = res.x / res.y;
    let uvCorrected = vec2<f32>(uv01.x * aspect, uv01.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let delta = uvCorrected - mouseCorrected;
    let dist = length(delta);
    let dir = select(vec2<f32>(0.0), delta / max(dist, 1e-6), dist > 1e-6);

    let mouseUV = vec2<f32>(mouse.x * aspect - aspect * 0.5, mouse.y - 0.5);

    let warp = fbm(uv * 3.5 + time * 0.2 + env) - 0.5;
    let quant = floor(dist * QUANT_STEP) / QUANT_STEP;
    let wave = sin((quant + warp * 0.08) * frequency - time * speed);

    let clickPhase = dist * 30.0 - time * 12.0;
    let clickPulse = select(0.0, sin(clickPhase) * exp(-dist * 4.0), mouseDown);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let depthAtten = 1.0 - exp(-depth * 3.0);

    let audioBoost = 1.0 + env * 0.6 + mids * 0.2;
    let strength = (1.0 / (dist * ATTEN_SCALE + 0.5)) * (0.3 + 0.7 * depthAtten);
    let displacement = dir * (wave + clickPulse * 0.5) * strength * DISP_AMP * audioBoost;
    var displacedUV = uv01 + displacement;

    let fbmWarp = vec2<f32>(
        fbm(displacedUV * 5.0 + time * 0.3),
        fbm(displacedUV * 5.0 - time * 0.25)
    ) - vec2<f32>(0.5);
    displacedUV = displacedUV + fbmWarp * fbmAmp * (1.0 + env);

    let activePixel = step(EPS, blockSize);
    let blocks = 1.0 / max(blockSize, EPS);
    let pixelated = floor(displacedUV * blocks) / blocks;
    displacedUV = mix(displacedUV, pixelated, activePixel);
    displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let lod = clamp(length(displacement) * res.x * 0.25, 0.0, 2.0);

    let offset = vec2<f32>(aberration * (1.0 + env * 0.5), 0.0);
    let sR = textureSampleLevel(readTexture, u_sampler, displacedUV + offset, lod);
    let sB = textureSampleLevel(readTexture, u_sampler, displacedUV - offset, lod);
    var color = vec3<f32>(sR.r, mix(sR.g, sB.g, 0.5), sB.b);

    let lum = luma(color);

    let rings = sdfRings(uv, mouseUV, time);
    let ringGlow = exp(-rings * 12.0) * (0.15 + env * 0.25);
    color = color + audioPalette(dist * 2.0 - time * 0.2, bass, treble) * ringGlow;
    color = color + vec3<f32>(treble * 0.15 * lum + clickPulse * 0.25);

    color = neonGlow(color, 0.25 + env * 0.35);

    let decay = 0.93 + env * 0.03;
    let trail = mix(prev.rgb * decay, color, 0.25 + env * 0.15);

    let finalColor = acesToneMap(trail * (0.9 + mids * 0.3));

    let effectStrength = clamp(strength * 2.0 + length(displacement) * 50.0 + lum * 0.3 + abs(clickPulse) + ringGlow * 2.0, 0.0, 1.0);
    let alpha = clamp(mix(0.35, 0.95, effectStrength) * (0.6 + depthAtten * 0.4), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(finalColor, env));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
