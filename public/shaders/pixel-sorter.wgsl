// ═══════════════════════════════════════════════════════════════════
//  Pixel Sorter
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal-coherence, multi-criterion, upgraded-rgba
//  Complexity: Medium
//  Upgraded: Single sort pass with alpha translucency blending
// ═══════════════════════════════════════════════════════════════════
//  Applies a single sort displacement field and derives spectral
//  tint via mix() with wavelengthToRGB. Alpha encodes sort
//  intensity and luma threshold for translucency compositing.
//  Depth-aware blending and audio-reactive shimmer included.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Direction, y=Reverse, z=Intensity, w=Threshold
  ripples: array<vec4<f32>, 50>,
};

const PHI:    f32 = 1.61803398874989484820;
const TAU:    f32 = 6.28318530717958647692;
const INV_PI: f32 = 0.31830988618379067154;

fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (lambda < 440.0) { r = (440.0 - lambda) / 60.0; b = 1.0; }
  else if (lambda < 490.0) { g = (lambda - 440.0) / 50.0; b = 1.0; }
  else if (lambda < 510.0) { g = 1.0; b = (510.0 - lambda) / 20.0; }
  else if (lambda < 580.0) { r = (lambda - 510.0) / 70.0; g = 1.0; }
  else if (lambda < 645.0) { r = 1.0; g = (645.0 - lambda) / 65.0; }
  else { r = 1.0; }
  var intensity = 1.0;
  if (lambda < 420.0) { intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0; }
  else if (lambda > 700.0) { intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0; }
  return clamp(vec3(r, g, b) * intensity, vec3(0.0), vec3(1.0));
}

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
}

fn get_luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Hue extraction via max-min channel ordering — cheaper than full HSV
fn get_hue(c: vec3<f32>) -> f32 {
    let mx = max(c.r, max(c.g, c.b));
    let mn = min(c.r, min(c.g, c.b));
    let d = mx - mn + 1e-5;
    var h: f32 = 0.0;
    if (mx == c.r) { h = (c.g - c.b) / d; }
    else if (mx == c.g) { h = 2.0 + (c.b - c.r) / d; }
    else { h = 4.0 + (c.r - c.g) / d; }
    return fract(h / 6.0);
}

// Gold-noise (low discrepancy 2D) — better than fract(sin(.)) for sort jitter
fn goldNoise(uv: vec2<f32>, seed: f32) -> f32 {
    return fract(tan(distance(uv * PHI, uv) * (seed + 1e-3)) * uv.x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let direction      = u.zoom_params.x;          // 0=Vert, 1=Horiz, 0.5=Mouse-aware
    let reverse        = u.zoom_params.y;
    let intensityScale = u.zoom_params.z;
    let threshold      = clamp(u.zoom_params.w, 0.0, 1.0);

    // Mouse-velocity from history: dataTextureC stores prior mouse pos in pixel (0,0)
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let mouseVel = (mouse - prevMouse) * 60.0;             // approx normalized
    let mouseSpeed = clamp(length(mouseVel), 0.0, 2.0);

    // Mouse-aware sort axis: blend canonical axis with mouse-velocity direction
    var sortAxis = vec2<f32>(0.0, 1.0);                    // default: vertical
    if (direction > 0.7)      { sortAxis = vec2<f32>(1.0, 0.0); }  // horizontal
    else if (direction > 0.3) {
        let v = mouseVel + vec2<f32>(1e-4);
        sortAxis = normalize(v);
    }

    // Sample original
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = get_luma(c.rgb);
    let hue  = get_hue(c.rgb);

    // Multi-criterion sort key: luma dominant, hue modulates direction sign
    let hueShift = (hue - 0.5);

    // Distance-to-mouse falloff — concentrates effect under cursor (Gaussian bell)
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dMouse  = length(distVec);
    let cursorMask = exp(-dMouse * dMouse * 8.0);          // ~0.35 at d=0.3
    let mouseGate = mix(1.0, mouseDown * 1.5 + cursorMask, smoothstep(0.0, 0.3, dMouse));

    // Click+drag boost intensity; bass adds shimmer
    let intensity = intensityScale * (1.0 + bass * 0.5 + mouseSpeed * 0.4);

    // Sort displacement: only above luma threshold; signed by reverse + hue tint
    var offsetAmt = 0.0;
    if (luma > threshold) {
        offsetAmt = (luma - threshold) * intensity * 0.2 * mouseGate;
    }
    let signMul = mix(-1.0, 1.0, reverse) + hueShift * 0.3;

    // Curl-noise wobble — divergence-free organic perturbation along sort
    let nx = goldNoise(uv * 7.0 + vec2<f32>(time * 0.3, 0.0), 1.0) - 0.5;
    let ny = goldNoise(uv * 7.0 + vec2<f32>(0.0, time * 0.3), 2.0) - 0.5;
    let curl = vec2<f32>(ny, -nx) * 0.015 * mouseGate;

    let sampleUV = uv + sortAxis * offsetAmt * signMul + curl;
    let sampled = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Temporal coherence: blend with prior frame to settle the sort smoothly
    let prevPixel = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let blend = clamp(0.55 + mouseSpeed * 0.3, 0.5, 0.95);
    let tempColor = mix(prevPixel, sampled, blend);

    // Spectral tint based on sort displacement magnitude
    let sortLength = length(sampleUV - uv);
    let wavelength = mix(420.0, 700.0, clamp(sortLength * 8.0 + hue, 0.0, 1.0));
    let spectralTint = wavelengthToRGB(wavelength);
    let tintedColor = mix(tempColor, tempColor * spectralTint, sortLength * 2.0);

    // Audio-reactive shimmer boosts saturation on bass hits
    let shimmerBoost = 1.0 + bass * 0.3 * sin(uv.y * 20.0 + time * 4.0);
    let shimmerColor = tintedColor * shimmerBoost;

    // Depth-aware compositing: reduce effect on distant depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = mix(0.5, 1.0, 1.0 - depth * 0.6);
    let finalColor = mix(tempColor, shimmerColor, depthFactor);

    // Alpha: sort intensity * luma threshold + displacement magnitude
    let dispMag = sortLength;
    let alpha = clamp(get_luma(finalColor) * 0.4 + dispMag * 6.0 + cursorMask * 0.3 + tentAlpha(dispMag * 4.0) * 0.2, 0.0, 1.0);

    // Apply gaussian soft mask around cursor for localized compositing
    let softMask = gaussianMask(dMouse, 0.35);
    let maskedAlpha = alpha * mix(0.6, 1.0, softMask);

    // Vignette subtle darkening at frame edges for cinematic feel
    let vignette = 1.0 - smoothstep(0.3, 1.0, length(uv - vec2<f32>(0.5)) * 1.1);
    let finalMasked = finalColor * mix(0.92, 1.0, vignette);

    textureStore(writeTexture, coord, vec4<f32>(finalMasked, maskedAlpha));

    // Persist current frame for next-frame coherence + mouse history at (0,0)
    textureStore(dataTextureA, coord, vec4<f32>(finalMasked, maskedAlpha));
    if (coord.x == 0 && coord.y == 0) {
        textureStore(dataTextureB, vec2<i32>(0, 0), vec4<f32>(mouse, mouseSpeed, 1.0));
    }

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
}
