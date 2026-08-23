// ────────────────────────────────────────────────────────────────────────────────
//  Liquid Time Warp — Curl-Advected Temporal Feedback
//  Category: interactive-mouse
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, curl-advection, wipe-fronts, chromatic-aberration,
//            depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ────────────────────────────────────────────────────────────────────────────────
//  Temporal feedback advected by a flow field. Two structures replace the
//  original two-tap gradient-free noise flow:
//
//    1. Curl-noise advection banded by the FFT — the transport field is the
//       curl of a multi-octave noise potential, so it is divergence-free and
//       the history folds instead of piling up into saturated blobs. Each
//       octave's amplitude is driven by its own plasmaBuffer[1..8] bin, so bass
//       drives the broad sweep and treble the fine filigree. The old field was
//       two raw noise samples used directly as a velocity — that has non-zero
//       divergence, which is exactly what makes feedback loops bloom out.
//
//    2. Bounded click wipe fronts — clicks emit expanding rings that punch
//       fresh video through the accumulated history as they pass, capped at 50
//       ripples and ~2.5 s. Previously the only way to clear the buffer was to
//       hold the cursor still on one spot.
//
//  Also fixed: no audio at all (the shader ignored plasmaBuffer), no ripple
//  response, and history was read through the FILTERING sampler. dataTextureC
//  is rgba32float and `float32-filterable` is optional on this engine
//  (src/renderer/webgpu/device.ts), so that read is unsafe; advection now uses
//  exact textureLoad with a hand-rolled bilinear fetch.
// ────────────────────────────────────────────────────────────────────────────────

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,  // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Distortion, y=FlowSpeed, z=Scale, w=Decay
  ripples:     array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> vec2<f32> {
    let p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let pi = floor(p);
    let pf = fract(p);
    let w = pf * pf * (3.0 - 2.0 * pf);
    return mix(mix(dot(hash(pi + vec2<f32>(0.0, 0.0)), pf - vec2<f32>(0.0, 0.0)),
                   dot(hash(pi + vec2<f32>(1.0, 0.0)), pf - vec2<f32>(1.0, 0.0)), w.x),
               mix(dot(hash(pi + vec2<f32>(0.0, 1.0)), pf - vec2<f32>(0.0, 1.0)),
                   dot(hash(pi + vec2<f32>(1.0, 1.0)), pf - vec2<f32>(1.0, 1.0)), w.x), w.y);
}

// Curl of a noise potential: guaranteed divergence-free transport.
// The 0.08 factor renormalises the raw central difference (which reaches ~1/2e,
// about 16, for a [0,1] potential) back to the O(1) scale the original two-tap
// flow field had, so `distortAmt` keeps its tuned meaning.
fn curl(p: vec2<f32>) -> vec2<f32> {
    let e = 0.03;
    let dx = noise(p + vec2<f32>(e, 0.0)) - noise(p - vec2<f32>(e, 0.0));
    let dy = noise(p + vec2<f32>(0.0, e)) - noise(p - vec2<f32>(0.0, e));
    return vec2<f32>(dy, -dx) / (2.0 * e) * 0.08;
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  let m = clamp(1.0 - cosTheta, 0.0, 1.0);
  let m2 = m * m;
  return F0 + (1.0 - F0) * m2 * m2 * m;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

fn historyBilinear(p: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
    let maxC = dims - vec2<i32>(1);
    let f = fract(p);
    let i0 = vec2<i32>(floor(p));
    let s00 = textureLoad(dataTextureC, clamp(i0, vec2<i32>(0), maxC), 0);
    let s10 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0);
    let s01 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
    let s11 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0);
    return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(gid.xy);
    let dims = vec2<f32>(dimsI);
    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Params ───────────────────────────────────────────────────────────────
    let distortAmt = mix(0.002, 0.02, u.zoom_params.x) * (1.0 + bass * 0.5);
    let flowSpeed = mix(0.1, 2.0, u.zoom_params.y);
    let scale = mix(2.0, 10.0, u.zoom_params.z);
    let decay = mix(0.9, 0.995, u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let isMouseDown = step(0.5, u.zoom_config.w);

    // ── Structure 1: FFT-banded curl advection ───────────────────────────────
    // Three octaves, each amplified by its own spectrum bins: low bins sweep,
    // high bins stir the filigree.
    let lowBand  = (plasmaBuffer[1u].x + plasmaBuffer[2u].x) * 0.5;
    let midBand  = (plasmaBuffer[4u].x + plasmaBuffer[5u].x) * 0.5;
    let highBand = (plasmaBuffer[7u].x + plasmaBuffer[8u].x) * 0.5;

    var flow = curl(uv * scale + vec2<f32>(time * flowSpeed * 0.10, time * flowSpeed * 0.17))
             * (0.6 + lowBand * 1.6);
    flow += curl(uv * scale * 2.3 - vec2<f32>(time * flowSpeed * 0.21, time * flowSpeed * 0.13))
          * (0.3 + midBand * 1.1);
    flow += curl(uv * scale * 5.1 + vec2<f32>(time * flowSpeed * 0.33, -time * flowSpeed * 0.27))
          * (0.12 + highBand * 0.8);

    // ── Pointer: swirl on hover, push on hold ────────────────────────────────
    let mVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let mDist = length(mVec);
    let mRadius = 0.2;
    if (mDist < mRadius) {
        let force = 1.0 - mDist / mRadius;
        let dirN = normalize(mVec + vec2<f32>(1e-6));
        let push = dirN * force;
        let swirl = vec2<f32>(-mVec.y, mVec.x) * force * 2.0;
        flow += mix(swirl * 2.0, push * 5.0, isMouseDown);
    }

    // ── Structure 2: bounded click wipe fronts ───────────────────────────────
    var wipeFronts = 0.0;
    var frontGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.5) {
            let rDelta = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
            let r = max(length(rDelta), 1e-4);
            let front = r - age * 0.55;
            let env = exp(-front * front * 200.0) * exp(-age * 1.2);
            // The ring drags the flow outward and wipes history back to source.
            flow += (rDelta / r) * env * 3.0;
            wipeFronts += env;
            frontGlow += env * env;
        }
    }
    wipeFronts = min(wipeFronts, 1.0);
    frontGlow = min(frontGlow, 1.2);

    // ── Advect history (exact load, manual bilinear) ─────────────────────────
    let historyPx = (uv - flow * distortAmt) * dims;
    let historySample = historyBilinear(historyPx, dimsI);
    let historyColor = historySample.rgb;
    let historyAlpha = historySample.a;

    // ── Current plate, split along the flow direction ────────────────────────
    let flowMag = length(flow);
    let flowDir = normalize(flow + vec2<f32>(1e-6));
    let ca = (0.0008 + treble * 0.003) * clamp(flowMag * 0.3, 0.0, 1.0);
    let vR = textureSampleLevel(readTexture, u_sampler, uv + flowDir * ca, 0.0).r;
    let vG = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let vB = textureSampleLevel(readTexture, u_sampler, uv - flowDir * ca, 0.0).b;
    let videoColor = vec3<f32>(vR, vG.g, vB);

    // Fresh video is revealed under a held cursor and behind every wipe front.
    let wipeFactor = clamp(smoothstep(0.05, 0.0, mDist) * isMouseDown + wipeFronts, 0.0, 1.0);
    let keep = decay * (1.0 - wipeFactor);

    var finalColor = mix(videoColor, historyColor, keep);
    finalColor += vec3<f32>(0.55, 0.75, 1.0) * frontGlow * (0.35 + mids * 0.6);
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.2));
    finalColor = acesFilm(finalColor);

    // ── Semantic alpha ───────────────────────────────────────────────────────
    // Accumulated history reads as substance; wipes clear it back to the plate.
    let normal = normalize(vec3<f32>(-flow * distortAmt * 30.0, 1.0));
    let fresnel = schlickFresnel(max(0.0, normal.z), 0.02);
    let accumulated = clamp(historyAlpha * keep + clamp(flowMag * 0.04, 0.0, 0.4), 0.0, 1.0);
    let alpha = clamp(mix(vG.a, accumulated, 0.7) * (1.0 - wipeFactor * 0.5)
                      + frontGlow * 0.25 - fresnel * 0.1, 0.0, 1.0);

    let outColor = vec4<f32>(finalColor, alpha);
    textureStore(dataTextureA, coord, outColor);
    textureStore(writeTexture, coord, outColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
