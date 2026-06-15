// ═══════════════════════════════════════════════════════════════════
//  Cyber Ripples
//  Category: interactive-mouse
//  Features: mouse-driven, wave, neon, audio-reactive, upgraded-rgba,
//            temporal-feedback, depth-aware, click-shockwave, aces-tone-map
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-14
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

    // Temporal state: previous frame color + smoothed bass envelope in alpha
    let prev = textureLoad(dataTextureC, pixel, 0);
    let env = bass_env(prev.a, bass, 0.8, 0.15);

    let speed = p1 * 5.0 + 1.0;
    let blockSize = p2 * 0.1;
    let aberration = p3 * 0.05;
    let frequency = p4 * 50.0 + 10.0;

    // Mouse-driven ripple origin with aspect correction
    let aspect = res.x / res.y;
    let uvCorrected = vec2<f32>(uv01.x * aspect, uv01.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let delta = uvCorrected - mouseCorrected;
    let dist = length(delta);
    let dir = select(vec2<f32>(0.0), delta / max(dist, 1e-6), dist > 1e-6);

    // Quantized digital wave
    let quant = floor(dist * QUANT_STEP) / QUANT_STEP;
    let wave = sin(quant * frequency - time * speed);

    // Click shockwave burst
    let clickPhase = dist * 30.0 - time * 12.0;
    let clickPulse = select(0.0, sin(clickPhase) * exp(-dist * 4.0), mouseDown);

    // Depth-aware compositing for slot 2/3 chains
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let depthAtten = 1.0 - exp(-depth * 3.0);

    // Audio-reactive displacement
    let audioBoost = 1.0 + env * 0.6 + mids * 0.2;
    let strength = (1.0 / (dist * ATTEN_SCALE + 0.5)) * (0.3 + 0.7 * depthAtten);
    let displacement = dir * (wave + clickPulse * 0.5) * strength * DISP_AMP * audioBoost;
    var displacedUV = uv01 + displacement;

    // Branchless pixelation
    let activePixel = step(EPS, blockSize);
    let blocks = 1.0 / max(blockSize, EPS);
    let pixelated = floor(displacedUV * blocks) / blocks;
    displacedUV = mix(displacedUV, pixelated, activePixel);
    displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    // Anti-moiré LOD bias
    let lod = clamp(length(displacement) * res.x * 0.25, 0.0, 2.0);

    // 2-tap chromatic aberration
    let offset = vec2<f32>(aberration * (1.0 + env * 0.5), 0.0);
    let sR = textureSampleLevel(readTexture, u_sampler, displacedUV + offset, lod);
    let sB = textureSampleLevel(readTexture, u_sampler, displacedUV - offset, lod);
    var color = vec3<f32>(sR.r, mix(sR.g, sB.g, 0.5), sB.b);

    // Treble sparkle + click glow
    let lum = luma(color);
    color = color + vec3<f32>(treble * 0.15 * lum + clickPulse * 0.25);

    // Neon glow driven by bass envelope
    color = neonGlow(color, 0.25 + env * 0.35);

    // Temporal feedback trail
    let decay = 0.93 + env * 0.03;
    let trail = mix(prev.rgb * decay, color, 0.25 + env * 0.15);

    // ACES tone mapping with mid-frequency exposure lift
    let finalColor = acesToneMap(trail * (0.9 + mids * 0.3));

    // Semantic alpha: interaction intensity + depth
    let effectStrength = clamp(strength * 2.0 + length(displacement) * 50.0 + lum * 0.3 + abs(clickPulse), 0.0, 1.0);
    let alpha = clamp(mix(0.35, 0.95, effectStrength) * (0.6 + depthAtten * 0.4), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(finalColor, env));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
