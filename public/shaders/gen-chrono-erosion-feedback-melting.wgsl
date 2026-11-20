// ═══════════════════════════════════════════════════════════════════════════════
//  Chrono-Erosion - Feedback Melting
//  Category: artistic
//  Description: Datamosh-like flow where video melts along a curl-noise
//               vector field with feedback decay and audio-driven turbulence.
//  Features: audio-reactive, temporal, feedback, mouse-driven, upgraded-rgba
//  Upgraded: 2026-11-20
//  Ideas: flow-lane persistence (erosion channels: Trail Decay made spatially varying, §12.1 tactic 4); macroblock motion carry (16 px block-centre flow vector, §12.2B)
//  A packing: display-colour history (HDR <= 1.5, pre-ACES); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.01;
    let n0 = noise(p + vec2<f32>(eps, 0.0) + t);
    let n1 = noise(p - vec2<f32>(eps, 0.0) + t);
    let n2 = noise(p + vec2<f32>(0.0, eps) + t);
    let n3 = noise(p - vec2<f32>(0.0, eps) + t);
    let dndx = (n0 - n1) / (2.0 * eps);
    let dndy = (n2 - n3) / (2.0 * eps);
    return vec2<f32>(dndy, -dndx);
}

// zoom_params: x=Trail Decay, y=Flow Intensity, z=Turbulence, w=Feedback Mix

// Macroblock edge in pixels (datamosh P-frame motion vectors are per 16x16 block).
const MB: f32 = 16.0;

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── _std/_std_sample.wgsl (verbatim): exact edge-clamped load + 4-load bilinear ──
// Rescue: HEAD read dataTextureC (rgba32float) through the filtering u_sampler.
fn loadClamped(tex: texture_2d<f32>, c: vec2<i32>) -> vec4<f32> {
  let dim = vec2<i32>(textureDimensions(tex));
  return textureLoad(tex, clamp(c, vec2<i32>(0), dim - vec2<i32>(1)), 0);
}

fn loadBilinear(tex: texture_2d<f32>, px: vec2<f32>) -> vec4<f32> {
  let q = px - 0.5;
  let i = vec2<i32>(floor(q));
  let f = fract(q);
  let a = loadClamped(tex, i);
  let b = loadClamped(tex, i + vec2<i32>(1, 0));
  let c = loadClamped(tex, i + vec2<i32>(0, 1));
  let d = loadClamped(tex, i + vec2<i32>(1, 1));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    // Rescue: pixel centre. HEAD used id/res (the pixel CORNER) for both the live
    // sample and the history read, so every frame of the loop shifted the feedback
    // half a texel up-left and blurred it 2x2 (diagonal drift + mush).
    let px = vec2<f32>(id.xy) + 0.5;
    let uv = px / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let audioOverall = plasmaBuffer[0].x + plasmaBuffer[0].y + plasmaBuffer[0].z;
    let aspect = res.x / max(res.y, 1.0);

    // Parameters
    let decay = u.zoom_params.x * 0.9 + 0.05;
    let flowIntensity = u.zoom_params.y * 0.05 + 0.005;
    let feedbackMix = u.zoom_params.w;

    // Per-band FFT turbulence: the frame is split into 8 strips and each strip's
    // melt turbulence is scaled by its own FFT energy, so different bands boil at
    // different energies instead of the whole frame moving as one.
    // Rescue: HEAD read plasmaBuffer[1..8].x, which the engine never uploads (only
    // plasmaBuffer[0] is written) so bandEnergy was always 0. The live FFT is
    // extraBuffer[5..132] (128 bins); strip b reads octave bin 2^b - 1 (0,1,3,..,127).
    let band = min(u32(uv.y * 8.0), 7u);
    let fftBin = (1u << band) - 1u;
    let bandEnergy = 0.25 * (extraBuffer[5u + fftBin] + extraBuffer[5u + min(fftBin + 1u, 127u)]);
    let turbulence = u.zoom_params.z * 2.0 * (1.0 + bandEnergy);

    // ── Idea 2: macroblock motion carry (§12.2B, datamosh) ──
    // Real moshed video drags whole 16x16 macroblocks by ONE motion vector. The curl
    // vector is also evaluated at the block centre; where the field is strong the
    // pixel's vector is pulled toward the block's, so fast streams tear into rigid
    // blocks while calm regions stay liquid. Stateless: no motion buffer needed.
    let curlPix = curlNoise(uv * 3.0, time * 0.1);
    let blockUv = (floor(vec2<f32>(id.xy) / MB) * MB + 0.5 * MB) / res;
    let curlBlk = curlNoise(blockUv * 3.0, time * 0.1);
    let blockCarry = smoothstep(0.3, 0.85, length(curlBlk)) * 0.75;

    // ── Idea 1: flow-lane persistence (erosion channels) ──
    // Trail Decay is one global weight at HEAD. The curl magnitude it already computed
    // marks the lanes where material actually streams; there the history keeps its trail
    // up to 35 % longer, so streaks run along the flow lanes (the channels the melt
    // erodes) while calm regions heal at exactly HEAD's rate. Scaled by the weight
    // itself, so Feedback Mix = 0 still means live-only.
    let lane = smoothstep(0.3, 0.9, length(curlPix));

    // Curl-noise flow field (block-carried where strong)
    var flow = mix(curlPix, curlBlk, blockCarry) * flowIntensity;

    // Mouse smudge. HEAD eased the cursor with a critically-damped spring whose state
    // lived in extraBuffer[133..138]; the engine re-uploads all 256 floats every frame
    // (audioDepth.ts writeExtraBuffer) so that state was zero each frame and the spring
    // re-initialised to the raw cursor: dead code. Pinned to the raw cursor (identical
    // behaviour, no fake state).
    let smudgePos = u.zoom_config.yz;

    // Mouse smudge (aspect-corrected so the influence stays circular)
    let uvAspect = uv * vec2<f32>(aspect, 1.0);
    let mouseAspect = smudgePos * vec2<f32>(aspect, 1.0);
    let mouseDelta = uvAspect - mouseAspect;
    let mouseDist = length(mouseDelta);
    let mouseInfluence = smoothstep(0.3, 0.0, mouseDist);
    let mouseDir = mouseDelta / max(mouseDist, 0.001);
    flow = flow + vec2<f32>(mouseDir.x / aspect, mouseDir.y) * mouseInfluence * 0.02;

    // Click melt vortices: each live ripple injects a decaying rotational flow
    // vortex at its click point, stirring the melt for ~2 seconds.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge > 0.0 && rippleAge < 2.0) {
            let rippleDelta = uvAspect - ripple.xy * vec2<f32>(aspect, 1.0);
            let rippleDist = length(rippleDelta);
            let vortexMask = smoothstep(0.2, 0.0, rippleDist);
            let tangent = vec2<f32>(-rippleDelta.y, rippleDelta.x) / max(rippleDist, 0.001);
            let vortex = tangent * exp(-rippleAge * 1.8) * 0.02 * vortexMask;
            flow = flow + vec2<f32>(vortex.x / aspect, vortex.y);
        }
    }

    // Audio turbulence spikes
    if (bass > 0.6) {
        let shock = bass * 0.03;
        let shockAngle = time * 7.0 + hash(uv * 10.0) * 6.28318;
        flow = flow + vec2<f32>(cos(shockAngle), sin(shockAngle)) * shock;
    }

    // Displaced feedback position in pixels (HEAD: clamp(uv + flow*(1+turb)) in uv)
    let displacedPx = clamp(px + flow * (1.0 + turbulence) * res, vec2<f32>(0.5), res - 0.5);

    // Read current frame and feedback (exact loads, no filtering sampler on the history)
    let currentS = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let current = currentS.rgb;
    let feedback = loadBilinear(dataTextureC, displacedPx).rgb;

    // Melt blend: Feedback Mix scales the decay-derived feedback weight.
    // Default 0.6 reproduces `decay` exactly; lower favors the live frame,
    // higher deepens the mosh.
    let meltBase = clamp(decay * (feedbackMix / 0.6), 0.0, 0.98);
    let meltW = clamp(meltBase * (1.0 + 0.35 * lane), 0.0, 0.98);
    let melted = mix(current, feedback, meltW);

    // Color shift based on flow magnitude
    let flowMag = length(flow) * 20.0;
    let shiftR = melted.r * (1.0 + flowMag * bass);
    let shiftG = melted.g * (1.0 + flowMag * 0.5);
    let shiftB = melted.b * (1.0 - flowMag * 0.3);

    var outCol = vec3<f32>(shiftR, shiftG, shiftB);

    // Audio-reactive color inversion on strong beats
    if (audioOverall > 0.7) {
        outCol = mix(outCol, vec3<f32>(1.0) - outCol, (audioOverall - 0.7) * 0.5);
    }

    outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.5));

    // Write feedback to dataTextureA for next frame (HDR colour history, pre-ACES)
    textureStore(dataTextureA, id.xy, vec4<f32>(outCol, 1.0));

    // Display: ACES on writeTexture only; alpha = source coverage united with melt energy
    let meltEnergy = clamp(meltW * (0.5 + flowMag), 0.0, 1.0);
    let alpha = clamp(currentS.a + (1.0 - currentS.a) * meltEnergy, 0.0, 1.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, id.xy, vec4<f32>(toneMapACES(outCol), alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
