// ═══════════════════════════════════════════════════════════════════
//  Spectral Vortex — Alpha Translucency Upgrade
//  Category: distortion
//  Features: mouse-driven, depth-aware, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-17
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=TwistScale, y=DistortionStep, z=ColorShift, w=CurlAmp
  ripples: array<vec4<f32>, 50>,
};

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5; var s = 0.0; var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * valueNoise(q);
        q = q * 2.02; a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0*q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0*q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0*r);
}

// ── HSV Helpers ──────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    var c = v * s;
    var x = c * (1.0 - abs(((h * 6.0) % 2.0) - 1.0));
    let m = v - c;
    var rgb = vec3<f32>(0.0, 0.0, 0.0);
    if (h < 1.0/6.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0/6.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0/6.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0/6.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0/6.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + m;
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let cmax = max(c.r, max(c.g, c.b));
    let cmin = min(c.r, min(c.g, c.b));
    let delta = cmax - cmin;
    var h = 0.0;
    if (delta > 0.0) {
        if (cmax == c.r) { h = (c.g - c.b) / delta % 6.0; }
        else if (cmax == c.g) { h = (c.b - c.r) / delta + 2.0; }
        else { h = (c.r - c.g) / delta + 4.0; }
        h = h / 6.0;
        if (h < 0.0) { h = h + 1.0; }
    }
    var s = select(0.0, delta / cmax, cmax > 0.0);
    return vec3<f32>(h, s, cmax);
}

// ── Spectral Tint ────────────────────────────────────────────
fn wavelengthToRGB(w: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(vec3<f32>(w, w + 2.09, w + 4.18));
}

// ── Energy Normalization ─────────────────────────────────────
fn normalizeEnergy(curlMag: f32, audioBoost: f32) -> f32 {
    let maxCurl = 5.0 * audioBoost;
    return clamp(curlMag / maxCurl, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let texelSize = 1.0 / resolution;

    // Parameters
    let twistScale = u.zoom_params.x;
    let distortionStep = u.zoom_params.y;
    let colorShift = u.zoom_params.z;
    let curlAmp = u.zoom_params.w;

    // Audio-reactive twist from bass
    let bass = plasmaBuffer[0].x;
    let audioTwist = 1.0 + bass * 3.0;

    // 1. Calculate Curl of Source Image Luminance
    let l = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texelSize.x, 0.0), 0.0).r;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
    let t = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texelSize.y), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;

    let dx = (r - l) * 0.5;
    let dy = (b - t) * 0.5;

    // Curl vector (velocity) with audio amplification
    let vel = vec2<f32>(dy, -dx) * mix(1.0, 20.0, curlAmp) * audioTwist;

    // 2. Accumulate Phase in Depth Buffer
    let prevPhase = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let curlMag = length(vel);
    let normalizedCurl = normalizeEnergy(curlMag, audioTwist);
    let newPhase = prevPhase + curlMag * 0.1 + 0.01;

    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(newPhase, 0.0, 0.0, 0.0));

    // 3. Distort UVs based on Phase and Velocity
    let angle = newPhase * twistScale;
    var s = sin(angle);
    var c = cos(angle);
    let rotMat = mat2x2<f32>(c, -s, s, c);

    // Domain-warped displacement for organic flow
    let warp = warpedFBM(uv * 3.0, u.config.x * 0.15);
    let offset = rotMat * vel * distortionStep * (1.0 + sin(u.config.x * 0.5)) * (1.0 + warp * 0.3);
    let distortedUV = uv + offset;

    // 4. Sample Source with single unified displacement
    let srcCol = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // 5. Apply Hue Rotation with spectral tint via mix
    var hsv = rgb2hsv(srcCol.rgb);
    hsv.x = fract(hsv.x + angle * 0.1 + colorShift * u.config.x);
    hsv.z = hsv.z * (1.0 + normalizedCurl * 2.0);

    var finalRGB = hsv2rgb(hsv.x, hsv.y, hsv.z);
    if (hsv.z < 0.2) {
        finalRGB = 1.0 - finalRGB;
    }

    // Spectral tint blended via mix, NOT channel splitting
    let spectralTint = wavelengthToRGB(u.config.x * 0.3 + normalizedCurl * 6.28);
    finalRGB = mix(finalRGB, finalRGB * spectralTint, normalizedCurl * colorShift);

    // 6. Depth-aware compositing
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = mix(0.6, 1.0, depth);
    finalRGB = finalRGB * depthFactor;

    // Alpha = curl magnitude / maxCurl (translucency based on energy)
    let alpha = mix(0.35, 1.0, normalizedCurl);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
}
