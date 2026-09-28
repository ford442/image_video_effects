// ═══════════════════════════════════════════════════════════════════
//  Silk Flow Advection
//  Category: image
//  Features: audio-reactive, upgraded-rgba, mouse-driven, click-reactive, held-drag, temporal
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: watered-silk moiré (moiré antique); held-pointer gathering with radial pleats
//  A packing: xy velocity, z flowEnergy, w alpha (raw sim state; C read back as velocity)
// ═══════════════════════════════════════════════════════════════════
// Image colours are advected along a living curl-noise flow (Grok,
// 2026-06-01). Flow (x) = curl strength, Silk (y) = softness + thread
// fineness, Breath (z) = zero-mean sway + colour breathing, Disturb (w) =
// mouse finger, click plucks and held gathering. Audio: bass -> flow,
// mids -> curl drift / colour breath, treble -> breath + thread glint.

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=Flow, y=Silk, z=Breath, w=Disturb
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let a = hash21(i); let b = hash21(i + vec2<f32>(1,0));
    let c = hash21(i + vec2<f32>(0,1)); let d = hash21(i + vec2<f32>(1,1));
    let u = f*f*(3.0-2.0*f);
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}

// Returns (curl.xy, psi). psi is the stream function the curl is taken of,
// recovered for free from the four taps; its iso-lines are the streamlines.
fn curlNoise(p: vec2<f32>, t: f32) -> vec3<f32> {
    let e = 0.08;
    let n1 = valueNoise(p + vec2<f32>(0, e) + t);
    let n2 = valueNoise(p + vec2<f32>(e, 0) + t);
    let n3 = valueNoise(p - vec2<f32>(0, e) + t);
    let n4 = valueNoise(p - vec2<f32>(e, 0) + t);
    return vec3<f32>(vec2<f32>(n1 - n3, n4 - n2) * 0.6, (n1 + n2 + n3 + n4) * 0.25);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1 — watered-silk moiré (moiré antique). Two fine rib gratings in
// pixel units (periods >= 3 px, never fract(uv*res)). The second, "pressed"
// layer is detuned and its phase is pushed by the flow's stream function, so
// the low-frequency beat of the pair runs along the streamlines of the local
// velocity (grad psi is perpendicular to vel) and flows as psi evolves.
// q is the flow-mapped pixel position, so the ribs bend with the advection.
// Returns (threads, watermark): threads = mean of the two layers (no sum
// frequency, so nothing above ~0.33 cycles/px), whose envelope is the beat;
// watermark = the analytic beat itself.
fn wateredSilk(q: vec2<f32>, psi: f32, time: f32, fineness: f32) -> vec2<f32> {
    let tau = 6.2831853;
    let ribAxis = vec2<f32>(0.1736, 0.9848);             // near-vertical rib spacing axis (~10 deg twill)
    let period = mix(5.0, 3.0, fineness);               // silk (y) -> finer threads
    let s = dot(q, ribAxis);
    let ribA = cos(tau * s / period);
    let pressedPhase = s / (period * 1.035) + psi * 4.0 + time * 0.06;
    let ribB = cos(tau * pressedPhase);
    // Beat term alone (difference frequency) = the watermark contour field.
    let watermark = cos(tau * (s / period - pressedPhase));
    return vec2<f32>(0.5 * (ribA + ribB), watermark);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let flowAmt = u.zoom_params.x * (0.7 + bass * 0.35);
    let silk = u.zoom_params.y * 0.9 + 0.2;
    let breath = u.zoom_params.z * (0.6 + treble * 0.5);
    let disturb = u.zoom_params.w;

    let mousePress = u.zoom_config.w;
    let aspect = res.x / max(res.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Raw cursor (UV, y=0 top). HEAD's extraBuffer[133..138] spring was inert
    // (buffer re-zeroed every frame => always snapped to the raw cursor).
    let mouse = u.zoom_config.yz;
    let held = select(0.0, 1.0, mousePress > 0.5);

    // Previous advection state — exact texel load of rgba32float history.
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    let previousVelocity = clamp(prev.xy, vec2<f32>(-0.08), vec2<f32>(0.08));

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Living silk curl flow field
    let curlPsi = curlNoise(uv * (3.5 + silk * 2.5), time * 0.04 + mids * 0.03);
    let curl = curlPsi.xy;
    let psi = curlPsi.z;
    let breathWave = sin(uv.x * 4.0 + time * 1.2) * cos(uv.y * 3.0 - time * 0.7) * breath * 0.018;
    // Breath rise/fall is zero-mean now (HEAD's constant -breath*0.011 was a
    // static whole-image shift that stretched the bottom edge).
    let breathLift = -breath * 0.011 * sin(time * 0.45 + uv.x * 1.3);

    var liveVelocity = curl * flowAmt * 0.022 + vec2<f32>(breathWave, breathLift);

    // Mouse finger disturbance stays circular on wide canvases and safely
    // maps its aspect-space direction back into UV velocity.
    let mouseDeltaAspect = (uv - mouse) * aspectVec;
    let md = length(mouseDeltaAspect);
    if (md < 0.32) {
        let push = (1.0 - smoothstep(0.0, 0.3, md)) * disturb * (0.8 + mousePress * 1.6);
        let mouseDir = (mouseDeltaAspect / max(md, 0.001)) / aspectVec;
        liveVelocity += mouseDir * push * -0.035;
    }

    // Idea 2 — held-pointer gathering. While held, the fabric bunches toward
    // the pointer: extra inward velocity (enters the C-smoothed state, so the
    // gather builds over frames) plus radial pleats — an integer number of
    // angular folds around the pointer, twisting slightly with radius.
    let gatherReach = 1.0 - smoothstep(0.05, 0.38, md);
    let gather = held * disturb * gatherReach * smoothstep(0.015, 0.07, md);
    let toPointerUV = -(mouseDeltaAspect / max(md, 0.001)) / aspectVec;
    let pleatAngle = atan2(mouseDeltaAspect.y, mouseDeltaAspect.x) * 13.0 + md * 18.0;
    let pleatHeight = cos(pleatAngle);                   // +1 ridge, -1 trough
    let pleatSlope = -sin(pleatAngle);                   // d(height)/d(angle)
    let pleatTangentUV = vec2<f32>(-mouseDeltaAspect.y, mouseDeltaAspect.x) / max(md, 0.001) / aspectVec;
    liveVelocity += toPointerUV * gather * 0.03;

    // Clicks pluck the silk with alternating tangent waves.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let clickVec = (uv - ripple.xy) * aspectVec;
            let clickDistance = length(clickVec);
            let tangentAspect = vec2<f32>(-clickVec.y, clickVec.x) / max(clickDistance, 0.001);
            let tangentUV = tangentAspect / aspectVec;
            let pluck = sin(clickDistance * 32.0 - age * 10.0)
                * exp(-age * 1.8) * smoothstep(0.34, 0.0, clickDistance);
            let directionSign = select(-1.0, 1.0, (ri % 2u) == 0u);
            liveVelocity += tangentUV * pluck * directionSign * disturb * 0.025;
        }
    }

    // The velocity state written to A is now actually consumed from C. This
    // temporal smoothing is raw state math, not display-color feedback.
    let velocityResponse = clamp(0.38 + flowAmt * 0.18 + mousePress * 0.12, 0.25, 0.75);
    let vel = clamp(mix(previousVelocity, liveVelocity, velocityResponse), vec2<f32>(-0.08), vec2<f32>(0.08));

    // Pleat depth follows how much the fabric has actually gathered (the
    // inward component of the history velocity from C).
    let inwardPrev = max(dot(previousVelocity * aspectVec, -mouseDeltaAspect / max(md, 0.001)), 0.0);
    let pleatDepth = gather * (0.45 + 0.55 * smoothstep(0.0, 0.035, inwardPrev));

    // Advect sample position; the gather adds a sampling pull (content drawn
    // in toward the pointer) and folds the image tangentially into the pleats.
    let pleatPull = -toPointerUV * pleatDepth * 0.045 * (0.75 + 0.25 * pleatHeight)
        + pleatTangentUV * pleatSlope * pleatDepth * 0.006;
    let advUV = clamp(uv - vel * 1.8 + pleatPull, vec2<f32>(0.0), vec2<f32>(1.0));
    let carried = textureSampleLevel(readTexture, u_sampler, advUV, 0.0);

    // Silk filtering (soft, luxurious)
    let silkBlend = mix(input.rgb, carried.rgb, 0.55 + silk * 0.35);

    // Idea 1 — watered silk replaces HEAD's isotropic valueNoise weave (whose
    // audio voice read plasmaBuffer[1..8], always zero). Ribs are sampled at
    // the flow-mapped pixel so they bend with the carried image; the two rib
    // layers give fine threads that fade in and out along the watermark, and
    // the beat term lifts the sheen where the pressed ribs line up.
    // Multiplicative: it shades the photo rather than overlaying colour.
    let fineness = u.zoom_params.y;
    let ribQ = (uv - vel * 1.8 + pleatPull) * res;   // same flow map as the photo, incl. gathering
    let moire = wateredSilk(ribQ, psi, time, fineness);
    let threadGlint = 1.0 + treble * 0.35;
    let silkStrength = (0.02 + 0.045 * fineness) * threadGlint;
    var col = silkBlend * (1.0 + silkStrength * (0.55 * moire.x + 0.8 * moire.y));

    // Idea 2 shading — pleats: lit ridges / dark troughs, plus a side light
    // (from the upper-left) across each fold's slope.
    let lightSide = dot(pleatTangentUV * aspectVec, normalize(vec2<f32>(-0.6, -0.8)));
    let pleatShade = 1.0 + pleatDepth * (0.16 * pleatHeight + 0.1 * pleatSlope * lightSide);
    col *= pleatShade;

    // Gentle color breathing from audio
    let breathColor = vec3<f32>(0.98, 0.96, 0.92) + vec3<f32>(0.04, 0.02, -0.03) * sin(time * 0.6 + mids * 1.2) * breath * 0.3;
    col *= breathColor;
    col = max(col, vec3<f32>(0.0));
    let display = acesToneMap(col * 0.92);

    // Semantic alpha — higher where flow is active (beautiful motion trails when stacked)
    let flowEnergy = length(vel) * 28.0 + breath * 0.4 + pleatDepth * 0.3;
    let semantic_alpha = clamp(0.62 + flowEnergy * 0.55, 0.5, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(display, semantic_alpha));

    // Store velocity field for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(vel.x, vel.y, flowEnergy, semantic_alpha));

    let d = clamp(0.25 + flowEnergy * 0.35, 0.0, 0.92);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
