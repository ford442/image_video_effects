// ═══════════════════════════════════════════════════════════════════
//  Spectral Waves
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, image, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  Upgraded: 2026-08-02 - sprung wave origin, click wave trains,
//            per-ring FFT voices (swarm b27, Visualist pass)
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RippleFreq, y=WaveSpeed, z=Intensity, w=ChromaticSplit
  ripples: array<vec4<f32>, 50>, // xy=click pos (uv), z=click time, w=unused
};

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.50, 0.49, 0.52) +
           vec3<f32>(0.48, 0.44, 0.42) *
           cos(6.28318 * (vec3<f32>(1.0, 0.82, 0.58) * t + vec3<f32>(0.06, 0.30, 0.54)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / u.config.zw;
    let aspect = u.config.z / u.config.w;
    let time = u.config.x;

    // Engine FFT: plasmaBuffer[0] = (bass, mids, treble, level)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Slider params (JSON contract: frequency/speed/amplitude/aberration)
    let frequency = 10.0 + u.zoom_params.x * 90.0;
    let speed = u.zoom_params.y * 5.0;
    let maxAmplitude = u.zoom_params.z * 0.1 * (1.0 + bass * 0.3 + treble * 0.15);
    let aberration = u.zoom_params.w * 0.05;

    // ── Sprung wave origin ─────────────────────────────────────────
    // Critically-damped spring eases the ripple epicenter toward the
    // raw cursor so the water glides instead of snapping. Persistent
    // state lives in extraBuffer[133..137] ([0..4] reserved, [5..132]
    // = engine FFT bins): [133]=pos.x [134]=pos.y [135..136]=velocity,
    // [137]=initialized flag.
    let rawMouse = u.zoom_config.yz;
    var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        springPos = rawMouse; // first frame: snap, don't glide from corner
    }
    let springOmega = 9.0;
    let springDt = 1.0 / 60.0;
    let springDecay = exp(-springOmega * springDt);
    let springDelta = springPos - rawMouse;
    let springTemp = (springVel + springOmega * springDelta) * springDt;
    let newVel = (springVel - springOmega * springTemp) * springDecay;
    let newPos = rawMouse + (springDelta + springTemp) * springDecay;
    // Deterministic: every thread integrates the same state locally;
    // thread (0,0) alone persists it back for the next frame.
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = newPos.x;
        extraBuffer[134] = newPos.y;
        extraBuffer[135] = newVel.x;
        extraBuffer[136] = newVel.y;
        extraBuffer[137] = 1.0;
    }
    let mousePos = newPos;

    // Aspect-corrected space keeps the rings circular on wide canvases
    let uv_c = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_c = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = distance(uv_c, mouse_c);

    let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = getLuminance(centerColor);

    // Dual-wave construction: primary ripple + bass-phased echo
    let wave = sin(dist * frequency - time * speed);
    let echoWave = sin(dist * frequency * 0.47 + time * speed * 0.72 + bass * 3.0);
    let crest = smoothstep(0.58, 1.0, wave) + smoothstep(0.74, 1.0, echoWave) * 0.55;
    var displacement = (wave * 0.78 + echoWave * 0.22) * maxAmplitude * (0.35 + luma * 0.95);

    // ── Click wave trains ──────────────────────────────────────────
    // Each live ripple splashes an expanding, decaying train of rings
    // from its click point (~2s life), composed with the main wave
    // BEFORE the chromatic taps so clicks visibly splash rings.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let click = u.ripples[i];
        let rippleAge = time - click.z;
        if (rippleAge < 0.0 || rippleAge > 2.0) { continue; }
        let click_c = vec2<f32>(click.x * aspect, click.y);
        let distR = distance(uv_c, click_c);
        let ringFade = 1.0 - smoothstep(1.6, 2.0, rippleAge);
        let falloff = exp(-distR * 3.0) * ringFade;
        let train = sin(distR * frequency * 0.8 - rippleAge * 8.0) *
                    exp(-rippleAge * 1.5) * maxAmplitude * 0.8;
        displacement = displacement + train * falloff * (0.35 + luma * 0.95);
    }

    // 3-tap chromatic aberration along the safe radial direction
    let safeDirCorrected = (uv_c - mouse_c) / max(dist, 0.001);
    let safeDir = safeDirCorrected / vec2<f32>(aspect, 1.0);
    let uv_r = clamp(uv - safeDir * displacement * (1.0 + aberration), vec2<f32>(0.0), vec2<f32>(1.0));
    let uv_g = clamp(uv - safeDir * displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let uv_b = clamp(uv - safeDir * displacement * (1.0 - aberration), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    // ── Per-ring FFT voices ────────────────────────────────────────
    // Radial distance quantized into 8 rings; each ring's crest glow
    // rides its own spectrum bin, so the spectrum ripples outward
    // spatially instead of pulsing the whole image at once.
    let ring = u32(clamp(dist * 8.0, 0.0, 7.99));
    let ringVoice = plasmaBuffer[(ring % 8u) + 1u].x * 0.35;

    // HDR assembly: displaced image + spectral caustics + bass glow
    var hdr = vec3<f32>(r, g, b);
    let spectral = palette(wave * 0.18 + dist * 0.7 - time * 0.04 + mids * 0.2);
    let caustic = pow(crest, 2.6) * (0.35 + luma) * (1.0 + treble * 0.8) + pow(crest, 2.0) * ringVoice;
    hdr = hdr * (0.94 + crest * 0.2) + spectral * caustic * 1.55;
    hdr = hdr + vec3<f32>(0.16, 0.28, 0.8) * pow(max(0.0, 1.0 - dist * 1.8), 3.0) * bass * 0.55;

    // Radial vignette + IGN dither, then ACES tonemap
    let radial = length(uv - vec2<f32>(0.5)) * 1.414;
    hdr = hdr * mix(1.06, 0.72, smoothstep(0.45, 1.0, radial));
    let dither = (ign(vec2<f32>(global_id.xy) + time * 19.0) - 0.5) / 255.0;
    let finalColor = clamp(aces(hdr * 1.18) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    let wave_pos = clamp(wave * 0.5 + 0.5, 0.0, 1.0);
    let hdr_luma = getLuminance(hdr);
    let alpha = clamp(0.16 + wave_pos * 0.18 + pow(max(0.0, hdr_luma - 0.55), 2.0) * 2.8, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // PREMULTIPLIED output: rgb is already scaled by alpha
    let finalRGBA = vec4<f32>(finalColor * alpha, alpha);

    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, coords, finalRGBA); // display color, same premultiplied value
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
