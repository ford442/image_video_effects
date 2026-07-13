// ═══════════════════════════════════════════════════════════════════
//  VHS Chroma Bleed — Authentic Tape Degradation Edition
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, jitter-smear, chromatic-bleed,
//            depth-scatter, upgraded-rgba, film-grain, scanlines, crt-barrel,
//            tape-tracking, compression-artifacts, analog-warmth, vignette,
//            time-varying-chroma, noise-bands
//  Complexity: High
//  Chunks From: vhs-chroma-bleed, hash, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-06-28
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h1 = hash21(p);
  let h2 = hash21(p + vec2<f32>(1.0, 0.0));
  return vec2<f32>(h1, h2);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

// Temporal grain with VHS-specific noise patterns
fn vhsGrain(gid: vec2<f32>, time: f32, treble: f32) -> f32 {
    let t1 = hash21(gid + fract(time * 0.5) * 100.0);
    let t2 = hash21(gid * 1.7 + fract(time * 0.3) * 100.0);
    let grain = mix(t1, t2, 0.5) - 0.5;
    return grain * (1.0 + treble * 0.5);
}

// Tape tracking error: horizontal wobble with jitter
fn tapeTracking(uv: vec2<f32>, time: f32, jitterAmt: f32, bass: f32) -> f32 {
    let linePhase = floor(uv.y * 480.0);
    let lineHash = hash21(vec2<f32>(linePhase, floor(time * 30.0)));
    let trackingError = sin(time * 8.0 + linePhase * 0.1) * 0.003 * jitterAmt;
    let dropout = step(1.0 - bass * 0.08, lineHash) * 0.01 * bass;
    return trackingError + dropout;
}

// Time-varying VHS chromatic aberration (channel delay)
fn vhsChromatic(uv: vec2<f32>, time: f32, strength: f32) -> vec3<f32> {
    let rShift = sin(time * 3.7 + uv.y * 50.0) * strength * 0.003;
    let gShift = sin(time * 5.3 + uv.y * 40.0) * strength * 0.0015;
    let bShift = sin(time * 2.1 + uv.y * 60.0) * strength * 0.003;
    return vec3<f32>(rShift, gShift, bShift);
}

// Scanlines with VHS-specific intensity variation
fn vhsScanlines(y: f32, time: f32, intensity: f32) -> f32 {
    let freq = 525.0;
    let scan = sin(y * freq) * 0.5 + 0.5;
    let fade = sin(y * freq * 0.5 + time * 1.5) * 0.2 + 0.8;
    return 1.0 - scan * intensity * fade;
}

// CRT barrel distortion
fn crtDistort(uv: vec2<f32>, k: f32) -> vec2<f32> {
    let center = uv - vec2<f32>(0.5);
    let r2 = dot(center, center);
    let distort = 1.0 + k * r2 + k * k * r2 * r2;
    return center * distort + vec2<f32>(0.5);
}

// Vignette
fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let center = uv - vec2<f32>(0.5);
    let r = length(center) * 1.4142;
    return pow(1.0 - r * strength, 2.0);
}

// Analog warmth: color temperature shift toward orange/yellow
fn analogWarmth(color: vec3<f32>, amount: f32) -> vec3<f32> {
    let warmth = vec3<f32>(1.08, 1.02, 0.92);
    return mix(color, color * warmth, amount);
}

// Saturation roll-off: colors desaturate toward white in highlights
fn saturationRolloff(color: vec3<f32>, amount: f32) -> vec3<f32> {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let highlight = smoothstep(0.5, 1.0, luma);
    let desat = mix(color, vec3<f32>(luma), highlight * amount);
    return desat;
}

// Compression artifacts: subtle blockiness simulation
fn compressionArtifacts(uv: vec2<f32>, time: f32, strength: f32) -> f32 {
    let blockUV = floor(uv * vec2<f32>(64.0, 32.0)) / vec2<f32>(64.0, 32.0);
    let blockHash = hash21(blockUV + time * 0.1);
    return (blockHash - 0.5) * strength * 0.02;
}

// Noise bands: horizontal bands of noise
fn noiseBands(uv: vec2<f32>, time: f32, strength: f32) -> f32 {
    let bandY = floor(uv.y * 8.0);
    let bandHash = hash21(vec2<f32>(bandY, floor(time * 4.0)));
    let bandIntensity = smoothstep(0.85, 1.0, bandHash) * strength;
    return bandIntensity * (hash21(uv * 100.0 + time) - 0.5) * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // ── Cinematic params ──
    let crtK = -0.06;
    let vignetteStrength = 0.5 + bass * 0.2;
    let scanlineIntensity = 0.06 + treble * 0.04;
    let warmthAmount = 0.15 + mids * 0.1;
    let saturationRoll = 0.3 + treble * 0.2;
    let compressionStr = 0.5 + bass * 0.3;
    let noiseBandStr = 0.4 + treble * 0.3;

    // Apply CRT barrel distortion
    let distortedUV = crtDistort(uv, crtK);
    let validUV = clamp(distortedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, validUV, 0.0).r;
    let depthScatter = mix(0.7, 1.3, depth);

    let bleedStrength = u.zoom_params.x * bass_env(bass, mids);
    let jitterAmt = u.zoom_params.y;
    let driftSpeed = u.zoom_params.z;
    let rgbShift = u.zoom_params.w * depthScatter;

    // Audio-reactive jitter: bass drives line dropout, treble adds micro-jitter
    let lineHash = hash21(vec2<f32>(0.0, uv.y * resolution.y));
    let dropOut = step(1.0 - bass * 0.15, lineHash);
    let microJitter = (hash21(vec2<f32>(time * 100.0, uv.y * 500.0)) - 0.5) * jitterAmt * (1.0 + treble);

    let dToMouse = uv - mousePos;
    let lenD = length(dToMouse);
    let safeDir = select(vec2<f32>(0.0), dToMouse / max(lenD, 0.0001), lenD > 0.001);
    let mouseDist = length(dToMouse);
    let mouseForce = smoothstep(0.3, 0.0, mouseDist) * 0.05;

    let jitter = microJitter + safeDir.y * mouseForce;
    let drift = sin(uv.y * 20.0 + time * driftSpeed * 5.0) * 0.005 * depthScatter;
    let bleed = (dropOut * 0.02) + bleedStrength * (0.02 + drift) * depthScatter;

    // Tape tracking error
    let trackingOffset = tapeTracking(uv, time, jitterAmt, bass);

    // Time-varying VHS chromatic aberration
    let vhsCA = vhsChromatic(uv, time, 1.0 + bass * 0.5);

    // Chromatic bleed: R and B shift in opposite directions with VHS-specific offsets
    let rOff = clamp(validUV + vec2<f32>(-bleed * (1.0 + rgbShift) + vhsCA.r + trackingOffset, jitter), vec2<f32>(0.0), vec2<f32>(1.0));
    let bOff = clamp(validUV + vec2<f32>(bleed * (1.0 + rgbShift) + vhsCA.b + trackingOffset, -jitter), vec2<f32>(0.0), vec2<f32>(1.0));
    let gOff = clamp(validUV + vec2<f32>(vhsCA.g + trackingOffset * 0.5, jitter * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rOff, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gOff, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bOff, 0.0).b;

    // Mids add color flash during chroma shifts
    let flash = mids * 0.08 * bleed * 10.0;
    var rgb = vec3<f32>(r, g, b) + vec3<f32>(flash, flash * 0.5, flash * 0.2);

    // ── Temporal film grain ──
    let grain = vhsGrain(vec2<f32>(global_id.xy), time, treble);
    rgb = rgb + grain * 0.08;

    // ── Scanlines ──
    let scan = vhsScanlines(uv.y, time, scanlineIntensity);
    rgb = rgb * scan;

    // ── Vignette ──
    let vig = vignette(validUV, vignetteStrength * 0.7);
    rgb = rgb * mix(0.5, 1.0, vig);

    // ── Analog warmth ──
    rgb = analogWarmth(rgb, warmthAmount);

    // ── Saturation roll-off in highlights ──
    rgb = saturationRolloff(rgb, saturationRoll);

    // ── Compression artifacts ──
    let artifact = compressionArtifacts(uv, time, compressionStr);
    rgb = rgb + vec3<f32>(artifact);

    // ── Noise bands ──
    let nBand = noiseBands(uv, time, noiseBandStr);
    rgb = rgb + vec3<f32>(nBand);

    let alpha = clamp((r + g + b) * 0.3 + bleed * 5.0 + bass * 0.05, 0.0, 1.0);

    // Premultiplied alpha
    let finalColor = clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.5));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor * alpha, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor * alpha, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}