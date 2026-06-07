// ═══════════════════════════════════════════════════════════════════
//  Scan Distort - Alpha Translucency Edition
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, temporal-feedback, upgraded-rgba
//  Complexity: High
//  Transform: Replaced RGB shift with unified displacement field.
//             Alpha encodes scanline distortion intensity * glitch probability.
//             Added temporal feedback via dataTextureC, bass envelope,
//             ripple system integration, and mouse-reactive scanlines.
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
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn quantize(color: vec3<f32>, levels: f32) -> vec3<f32> {
    return floor(color * levels) / levels;
}

fn blockEdgeFactor(uv: vec2<f32>, blockSize: f32) -> f32 {
    let blockUV = uv * blockSize;
    let fracUV = fract(blockUV);
    let edgeDist = min(min(fracUV.x, 1.0 - fracUV.x), min(fracUV.y, 1.0 - fracUV.y));
    return smoothstep(0.05, 0.0, edgeDist);
}

// ═══ Audio envelope (smooth attack/release) ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ═══ Tent alpha curve ═══
fn tentAlpha(x: f32) -> f32 {
    return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

// ═══ Glitch probability helper ═══
fn glitchProbability(time: f32, freq: f32) -> f32 {
    let framePhase = fract(time * freq);
    let seed = hash2(vec2<f32>(floor(time * freq), 0.0));
    return select(0.0, 1.0, framePhase < 0.1 && seed < 0.15);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;
    let bass = plasmaBuffer[0].x;
    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    let blockSize = 4.0 + u.zoom_params.x * 12.0;
    let quantLevel = 2.0 + u.zoom_params.y * 62.0;
    let mvVisibility = u.zoom_params.z;
    let glitchFreq = 0.1 + u.zoom_params.w * 2.0;

    // ─── Audio envelope with attack/release ───
    var prevEnv = 0.0;
    if (gid.x == 0u && gid.y == 0u) {
        prevEnv = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(0.0), 0.0).r;
    }
    let env = bass_env(prevEnv, bass, 0.8, 0.15);

    // Mouse drives glitch frequency when clicked
    let mouseGlitchBoost = select(0.0, 0.5, isMouseDown);
    let effectiveGlitchFreq = glitchFreq + mouseGlitchBoost;

    // Mouse Y modulates scanline density
    let mouseScanBoost = 1.0 + mouse.y * 0.5;

    // Mouse-driven scanline tear
    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    let lines = 100.0 * mouseScanBoost;
    let bendStr = 0.15;
    let speed = 3.0;

    let push = smoothstep(0.4, 0.0, dist);
    let audioBend = bendStr * (1.0 + env * 0.5);
    let vOffset = push * audioBend * sin(dist * 20.0 - time * 2.0);
    let scanVal = sin((uv.y + vOffset) * lines - time * speed);
    let scanLine = smoothstep(0.0, 1.0, scanVal);

    // ─── Ripple system integration for extra distortion bursts ───
    var rippleDisp = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = distance(uv, rPos);
            let rWave = sin(rDist * 40.0 - rElapsed * 8.0) * exp(-rElapsed * 1.5);
            rippleDisp = rippleDisp + rWave * smoothstep(0.3, 0.0, rDist);
        }
    }
    let totalVOffset = vOffset + rippleDisp * 0.05;

    // Unified displacement field (NO per-channel UV sampling)
    let displacement = vec2<f32>(totalVOffset * 0.1, totalVOffset);
    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));

    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Quantization with edge preservation
    let quantized = quantize(baseColor, quantLevel);
    let edgeDetect = abs(baseColor.r - quantized.r) + abs(baseColor.g - quantized.g) + abs(baseColor.b - quantized.b);
    let isEdge = step(0.1, edgeDetect);
    var color = mix(quantized, baseColor, isEdge * 0.3);

    // DCT block boundaries
    let edgeFactor = blockEdgeFactor(uv, blockSize);
    let edgeNoise = hash2(uv * 1000.0 + time) * 0.1;
    color = color * (1.0 - edgeFactor * 0.3) + vec3<f32>(edgeFactor * edgeNoise);
    let edgeTint = vec3<f32>(1.0, 0.98, 1.02);
    color = mix(color, color * edgeTint, edgeFactor * 0.5);

    // Motion vector visualization (simplified, unified)
    if (mvVisibility > 0.01) {
        let blockIdx = floor(uv * blockSize);
        let angle = sin(blockIdx.x * 0.5 + time * 0.5) * cos(blockIdx.y * 0.3 + time * 0.3) * 6.28318;
        let magnitude = 0.5 + 0.5 * sin(blockIdx.x * 0.7 + blockIdx.y * 0.4 + time * 0.8);
        let mv = vec2<f32>(cos(angle), sin(angle)) * magnitude * 0.02;
        let mvColor = vec3<f32>(0.5 + mv.x * 10.0, 0.5 + mv.y * 10.0, 0.3);
        let blockUV = fract(uv * blockSize) - 0.5;
        let arrowMask = smoothstep(0.15, 0.1, length(blockUV));
        color = mix(color, mvColor, arrowMask * mvVisibility * 0.5);
    }

    // Macroblock errors
    let blockIdx = floor(uv * blockSize);
    let blockHash = hash2(blockIdx * 0.1);
    let timeHash = hash2(vec2<f32>(floor(time * effectiveGlitchFreq), 0.0));
    if (blockHash < 0.02 && timeHash < 0.3) {
        let garble = hash3(vec3<f32>(uv * 50.0, time));
        color = vec3<f32>(garble, fract(garble * 1.5), fract(garble * 2.3));
    }

    // I-frame glitch
    let isGlitch = glitchProbability(time, effectiveGlitchFreq) > 0.5;
    if (isGlitch) {
        let glitchPattern = hash3(vec3<f32>(uv * 20.0, floor(time * effectiveGlitchFreq)));
        let shiftUV = uv + vec2<f32>(glitchPattern - 0.5, 0.0) * 0.1;
        let shiftedColor = textureSampleLevel(readTexture, u_sampler, shiftUV, 0.0).rgb;
        color = mix(color, shiftedColor, 0.5) + vec3<f32>(glitchPattern * 0.2);
    }

    // ─── Temporal feedback via dataTextureC ───
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let distortionMag = abs(totalVOffset) * 4.0;
    let feedbackMix = tentAlpha(distortionMag) * 0.15;
    color = mix(color, prevColor, feedbackMix);

    // Scanline darkening
    color = color * (0.8 + 0.2 * scanLine);

    // ─── Alpha = scanline distortion intensity * glitch probability ───
    let glitchProb = select(0.0, 1.0, isGlitch);
    let distortionIntensity = abs(totalVOffset) * 10.0;
    let alpha = clamp(distortionIntensity * 0.5 + glitchProb * 0.3 + env * 0.2, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

    if (gid.x == 0u && gid.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(env, 0.0, 0.0, 0.0));
    } else {
        textureStore(dataTextureA, gid.xy, vec4<f32>(color, alpha));
    }
}
