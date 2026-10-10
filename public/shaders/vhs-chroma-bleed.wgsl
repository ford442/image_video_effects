// ═══════════════════════════════════════════════════════════════════
//  VHS Chroma Bleed — Authentic Tape Degradation Edition
//  Category: image
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: colour-under bandwidth (7-tap Y/C split, delayed chroma plane); cross-colour rainbow crawl; chroma loss in dropout rows
//  A packing: ACES display RGB + source alpha (no C read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

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

// Vignette (base guarded: pow of a negative base is NaN, so square by hand)
fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let center = uv - vec2<f32>(0.5);
    let r = length(center) * 1.4142;
    let x = max(1.0 - r * strength, 0.0);
    return x * x;
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

// Y / CbCr split used by the colour-under path (BT.601 weights).
fn rgbToYcc(c: vec3<f32>) -> vec3<f32> {
    let y = dot(c, vec3<f32>(0.299, 0.587, 0.114));
    return vec3<f32>(y, (c.b - y) * 0.564, (c.r - y) * 0.713);
}

fn yccToRgb(ycc: vec3<f32>) -> vec3<f32> {
    let y = ycc.x;
    let cb = ycc.y;
    let cr = ycc.z;
    return vec3<f32>(y + 1.403 * cr, y - 0.344 * cb - 0.714 * cr, y + 1.773 * cb);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let texel = 1.0 / resolution;

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
    let bleedWidth = u.zoom_params.w;   // raw slider: colour-under bandwidth scale

    // Audio-reactive jitter: bass drives line dropout, treble adds micro-jitter.
    // The row hash is re-rolled ~24x/s so dropout rows flicker instead of sitting still.
    let lineHash = hash21(vec2<f32>(floor(time * 24.0), uv.y * resolution.y));
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
    let gSample = textureSampleLevel(readTexture, u_sampler, gOff, 0.0);
    let g = gSample.g;
    let b = textureSampleLevel(readTexture, u_sampler, bOff, 0.0).b;
    let srcAlpha = gSample.a;

    // Mids add color flash during chroma shifts
    let flash = mids * 0.08 * bleed * 10.0;
    var rgb = vec3<f32>(r, g, b) + vec3<f32>(flash, flash * 0.5, flash * 0.2);

    // ── IDEA 1: colour-under bandwidth ──
    // A colour-under recording keeps luma at full bandwidth but squeezes chroma through a
    // ~0.6 MHz channel and demodulates it a few pixels late. Split the R/B-bled picture into
    // Y and CbCr, replace the chroma with a 7-tap horizontal box of the source taken to the
    // RIGHT of the luma position (delay + tap spacing both scale with Bleed Width), and keep
    // the sharp Y. Colour then spills past every vertical edge like a real Y/C tape.
    let ownYcc = rgbToYcc(rgb);
    let chromaDelay = (2.5 + bleedStrength * 1.5) * bleedWidth * texel.x;
    let tapStep = (1.4 + bleedWidth * 1.2) * texel.x;
    var chromaSum = vec2<f32>(0.0);
    var tapLuma = vec3<f32>(0.0);   // x = tap 2, y = tap 3 (centre), z = tap 4 — for the cross-colour gradient
    for (var i = 0; i < 7; i = i + 1) {
        let tapUV = clamp(gOff + vec2<f32>(chromaDelay + f32(i - 3) * tapStep, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let tapYcc = rgbToYcc(textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb);
        chromaSum += tapYcc.yz;
        if (i == 2) { tapLuma.x = tapYcc.x; }
        if (i == 3) { tapLuma.y = tapYcc.x; }
        if (i == 4) { tapLuma.z = tapYcc.x; }
    }
    let softChroma = chromaSum / 7.0;
    let colourUnderMix = clamp(0.45 + bleedWidth * 0.2, 0.0, 0.9);
    var ycc = vec3<f32>(ownYcc.x, mix(ownYcc.yz, softChroma, colourUnderMix));

    // ── IDEA 2: cross-colour rainbow crawl ──
    // Fine horizontal luma detail sits in the chroma sub-carrier band on tape, so the decoder
    // reads it as a false colour whose hue rotates slowly with time and row. |dY/dx| from the
    // neighbouring chroma taps gates the leak; the hue wheel drifts at ~0.7 rad/s.
    let lumaGrad = abs(tapLuma.z - tapLuma.x) / max(2.0 * tapStep * resolution.x, 1.0) * 6.0;
    let crossColour = smoothstep(0.10, 0.45, lumaGrad) * (0.10 + bleedStrength * 0.05) * bleedWidth;
    let hueAng = time * 0.7 + uv.y * 28.0 + uv.x * 6.0;
    ycc.y += cos(hueAng) * crossColour;
    ycc.z += sin(hueAng) * crossColour;

    // ── IDEA 3: chroma loss in dropout rows ──
    // A tracking dropout kills the colour-under carrier before it kills luma: the row goes
    // grey, starting from a ragged left edge (each row has its own hashed start column with
    // a little per-frame jitter) and then staying grey to the right edge. A few rows drop
    // even at rest; bass pushes the rate up alongside the existing luma dropout.
    let rowKey = floor(uv.y * resolution.y);
    let chromaDropRow = step(1.0 - 0.025 - bass * 0.15, lineHash);
    let edgeStart = hash21(vec2<f32>(rowKey, 7.0)) * 0.35;
    let edgeRag = (hash21(vec2<f32>(rowKey, floor(time * 24.0))) - 0.5) * 0.06;
    let chromaDrop = chromaDropRow * smoothstep(edgeStart + edgeRag - 0.01, edgeStart + edgeRag + 0.01, uv.x);
    ycc = vec3<f32>(ycc.x, ycc.yz * (1.0 - chromaDrop));

    rgb = yccToRgb(ycc);

    // ── Temporal film grain (Noise slider scales it: default 0.2 → HEAD's 0.08) ──
    let grain = vhsGrain(vec2<f32>(global_id.xy), time, treble);
    rgb = rgb + grain * jitterAmt * 0.4;

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

    // Semantic alpha: the tape carries the source's transparency.
    let alpha = clamp(srcAlpha, 0.0, 1.0);

    let display = acesToneMap(max(rgb, vec3<f32>(0.0)));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(display, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
