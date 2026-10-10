// ═══════════════════════════════════════════════════════════════════
//  Mercury Temporal Mirror
//  Category: image
//  Features: audio-reactive, mouse-driven, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: true capillary wave (height + velocity wave equation, click rings travel on their own); Fresnel horizon reflection (glancing slopes mirror a cool-top / warm-floor studio gradient)
//  A packing: raw wave state (h height, v velocity, 1/pi validity tag, semantic alpha*0.8), never tone-mapped; C read back exactly as h,v (foreign/NaN C -> 0)
// ═══════════════════════════════════════════════════════════════════
// Stylized liquid-metal mirror with travelling capillary packets and click impacts.

#include "_prelude.wgsl"

// Written to A.z so a history left in C by a different shader (or an empty C) is recognised and ignored.
const STATE_TAG: f32 = 0.31830988;
// Wave-equation stiffness: stride-1 + stride-2 4-neighbour Laplacians. Stability needs
// 8*(K1+K2) + GRAVITY + press spring (0.2) < 4 -> 3.25 here; wave speed sqrt(K1 + 4*K2) ~ 1.1 px/frame.
const K1: f32 = 0.10;
const K2: f32 = 0.28;
const GRAVITY: f32 = 0.01;
// Height gradient (per pixel) -> surface slope, normalised by canvas height so the look is resolution independent.
const SLOPE_SCALE: f32 = 0.035;

fn historyLoad(pixel: vec2<i32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

fn pcgHash(v: u32) -> u32 {
    let state = v * 747796405u + 2891336453u;
    let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

fn isFinite(x: f32) -> bool {
    return (bitcast<u32>(x) & 0x7f800000u) != 0x7f800000u;
}

// (h, v) from C; anything not written by this shader, or non-finite, reads as a flat, still surface.
fn stateLoad(pixel: vec2<i32>) -> vec2<f32> {
    let c = historyLoad(pixel);
    if (!isFinite(c.x) || !isFinite(c.y) || !isFinite(c.z) || abs(c.z - STATE_TAG) > 1e-4) {
        return vec2<f32>(0.0);
    }
    return vec2<f32>(clamp(c.x, -1.0, 1.0), clamp(c.y, -0.5, 0.5));
}

// Travelling capillary packet: a cos carrier under a gaussian envelope six carriers long.
// HEAD fix: the envelope was pow(negative, 2.0) (NaN) and centred where sin(phase)=0, so the packet cancelled itself.
fn capillaryPacketAt(p: vec2<f32>, time: f32, viscosity: f32, treble: f32) -> f32 {
    let packetPhase = dot(p, normalize(vec2<f32>(0.78, 0.62))) * 34.0 - time * (8.0 + (1.0 - viscosity) * 9.0);
    let e = (fract(packetPhase / (6.28318 * 6.0)) - 0.5) / 0.12;
    return cos(packetPhase) * exp(-e * e) * (0.025 + treble * 0.06);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let px = 1.0 / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let viscosity = u.zoom_params.x;
    let reflectAmount = u.zoom_params.y;
    let impactAmount = u.zoom_params.z;
    let metallic = u.zoom_params.w;

    // HEAD fix: the integer "shear" advection translated the whole field 1-3 px every frame (faster than any
    // ripple could travel, dragging click rings off their click point); the wave equation below owns motion now.
    let prev = stateLoad(coord);
    let left = stateLoad(coord + vec2<i32>(-1, 0));
    let right = stateLoad(coord + vec2<i32>(1, 0));
    let top = stateLoad(coord + vec2<i32>(0, -1));
    let bottom = stateLoad(coord + vec2<i32>(0, 1));
    let left2 = stateLoad(coord + vec2<i32>(-2, 0)).x;
    let right2 = stateLoad(coord + vec2<i32>(2, 0)).x;
    let top2 = stateLoad(coord + vec2<i32>(0, -2)).x;
    let bottom2 = stateLoad(coord + vec2<i32>(0, 2)).x;
    let lap = left.x + right.x + top.x + bottom.x - 4.0 * prev.x;
    let lap2 = left2 + right2 + top2 + bottom2 - 4.0 * prev.x;
    let lapV = left.y + right.y + top.y + bottom.y - 4.0 * prev.y;

    let aspect = resolution.x / resolution.y;
    let mouseDist = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
    let mouseMask = smoothstep(0.24, 0.0, mouseDist);
    let mouseImpact = smoothstep(0.24, 0.0, mouseDist) * impactAmount * (0.25 + u.zoom_config.w * 1.5);
    let rainTrack = pow(0.5 + 0.5 * sin(uv.x * 119.0 + sin(uv.y * 17.0) - time * 7.0), 22.0) * audio.z * 0.035;

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        // Idea 1: the front is only a 0.3 s launch now; the wave equation carries the ring outward afterwards.
        if (age >= 0.0 && age < 0.3) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.20 + audio.x * 0.08));
            clickFront += sin(ring * 180.0) * (1.0 - smoothstep(0.0, 0.035, ring)) * (1.0 - age / 0.3);
        }
    }

    // ── Idea 1: true capillary wave ──────────────────────────────────
    // v += c^2 * lap(h) - gravity*h + viscous lap(v) + forces; v *= damping; h += v.
    // Viscosity slider -> velocity damping and viscous smoothing (also kills stride-2 checkerboard modes).
    let damping = mix(0.993, 0.95, viscosity);
    let viscousNu = mix(0.03, 0.15, viscosity);
    let pressForce = (mouseImpact * 0.20 - mouseMask * prev.x) * 0.2;    // held finger presses a bump that radiates as it moves
    // Treble rain falls as drops along the rain tracks: a hashed per-cell gate (15 slots/s) breaks the tracks' steady
    // slide, which otherwise pumps one resonant wavelength; the duty mean is removed so rain cannot lift the whole pool.
    let dropCell = vec2<u32>(floor(uv * vec2<f32>(aspect, 1.0) / 0.012));
    let dropSlot = u32(floor(max(time, 0.0) * 15.0));
    let dropDuty = audio.z * 0.35;
    let dropRoll = f32(pcgHash(dropCell.x ^ pcgHash(dropCell.y ^ pcgHash(dropSlot)))) / 4294967295.0;
    let dropGate = select(0.0, 1.0, dropRoll < dropDuty);
    // Sources are sized in uv but waves travel in pixels; normalise so 540p and 2160p pools ring alike (fit from the numpy sweep).
    let resNorm = clamp(540.0 / max(resolution.y, 1.0), 0.125, 4.0);
    let rainForce = (rainTrack * dropGate - audio.z * 0.035 * 0.12 * dropDuty) * 0.35 * pow(resNorm, 1.5);
    let clickForce = clickFront * impactAmount * 0.12 * 0.4 * pow(resNorm, 0.7);
    let accel = K1 * lap + K2 * lap2 - GRAVITY * prev.x + viscousNu * lapV + pressForce + rainForce + clickForce;
    let vel = clamp((prev.y + accel) * damping, -0.5, 0.5);
    let height = clamp(prev.x + vel, -1.0, 1.0);

    // Display surface = dynamic state + analytic travelling packet (linear superposition).
    let packetScale = 4.0;
    let capillaryPacket = capillaryPacketAt(uv, time, viscosity, audio.z) * packetScale;
    let hL = left.x + capillaryPacketAt(uv - vec2<f32>(px.x, 0.0), time, viscosity, audio.z) * packetScale;
    let hR = right.x + capillaryPacketAt(uv + vec2<f32>(px.x, 0.0), time, viscosity, audio.z) * packetScale;
    let hT = top.x + capillaryPacketAt(uv - vec2<f32>(0.0, px.y), time, viscosity, audio.z) * packetScale;
    let hB = bottom.x + capillaryPacketAt(uv + vec2<f32>(0.0, px.y), time, viscosity, audio.z) * packetScale;
    let surfaceH = height + capillaryPacket;
    let slope = vec2<f32>(hR - hL, hB - hT) * 0.5 * resolution.y * SLOPE_SCALE;

    let waveNormal = slope * (0.03 + reflectAmount * 0.07);
    let reflectUV = clamp(uv + waveNormal, vec2<f32>(0.0), vec2<f32>(1.0));
    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let reflectedA = textureSampleLevel(readTexture, u_sampler, reflectUV, 0.0).rgb;
    let reflectedB = textureSampleLevel(readTexture, u_sampler, clamp(reflectUV + waveNormal * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    var reflected = (reflectedA + reflectedB) * 0.5;

    // ── Idea 2: Fresnel horizon reflection ───────────────────────────
    // View straight down; reflect it off the surface normal. As the slope steepens the reflected ray tips
    // toward the horizon and (Schlick) stops seeing the image, picking up a vertical studio gradient instead.
    let n = normalize(vec3<f32>(-slope.x, -slope.y, 1.0));
    let r = vec3<f32>(2.0 * n.z * n.x, 2.0 * n.z * n.y, 2.0 * n.z * n.z - 1.0);
    let cosR = clamp(r.z, 0.0, 1.0);
    let g1 = 1.0 - cosR;
    let horizonFresnel = 0.02 + 0.98 * g1 * g1 * g1 * g1 * g1;
    let upScreen = -r.y / max(length(r.xy), 0.05);                           // +1 = ray heads to screen top; flat -> 0
    let coolTop = vec3<f32>(0.58, 0.70, 0.92);
    let warmFloor = vec3<f32>(0.52, 0.40, 0.28);
    let horizonBand = exp(-(r.z * 5.0) * (r.z * 5.0)) * 0.45;
    let studio = mix(warmFloor, coolTop, smoothstep(-0.8, 0.8, upScreen)) + vec3<f32>(0.95, 0.94, 0.9) * horizonBand;
    reflected = mix(reflected, studio, clamp(horizonFresnel, 0.0, 1.0));

    let metalTint = mix(vec3<f32>(0.65, 0.68, 0.72), vec3<f32>(0.84, 0.87, 0.92), metallic);
    var color = mix(input.rgb, reflected * metalTint, 0.25 + reflectAmount * 0.65);
    let specular = pow(clamp(0.5 + surfaceH * 0.8 - length(slope), 0.0, 1.0), 5.0) * (0.3 + audio.x * 0.7);
    color = max(color + vec3<f32>(0.95, 0.98, 1.0) * specular * reflectAmount, vec3<f32>(0.0));
    let waveEnergy = abs(surfaceH) + length(slope) * 0.5;
    let semanticAlpha = clamp(0.65 + waveEnergy * 1.6 + reflectAmount * 0.25, 0.5, 1.0);

    // ACES on the display only; A keeps the raw wave state.
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(color), semanticAlpha));
    textureStore(dataTextureA, coord, vec4<f32>(height, vel, STATE_TAG, semanticAlpha * 0.8));
    let generatedDepth = clamp(0.3 + waveEnergy * 0.4, 0.0, 0.95);
    textureStore(writeDepthTexture, coord, vec4<f32>(generatedDepth, 0.0, 0.0, 0.0));
}
