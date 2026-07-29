// ═══════════════════════════════════════════════════════════════════
//  Neural Nexus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: neural-nexus
//  Upgraded: 2026-05-30 → swarm b18 (click bursts, spring cursor, FFT voices)
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ── Persistent shader state in extraBuffer[133..255] ONLY ──────────
// [0..4] reserved, [5..132] = engine FFT bins (never touched here).
//   [133] = sprung cursor x      [134] = sprung cursor y
//   [135] = cursor velocity x    [136] = cursor velocity y
const STATE_POS_X: u32 = 133u;
const STATE_POS_Y: u32 = 134u;
const STATE_VEL_X: u32 = 135u;
const STATE_VEL_Y: u32 = 136u;
const SPRING_OMEGA: f32 = 12.0;   // critically damped: c = 2 * omega
const FIXED_DT: f32 = 0.0166667;  // 60 Hz fixed step keeps it stable

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

// Critically-damped spring step (semi-implicit Euler, fixed dt).
// Returns vec4(newPos.xy, newVel.xy) eased toward targetPos.
fn springStep(pos: vec2<f32>, vel: vec2<f32>, targetPos: vec2<f32>) -> vec4<f32> {
    let accel = (targetPos - pos) * (SPRING_OMEGA * SPRING_OMEGA) - vel * (2.0 * SPRING_OMEGA);
    let newVel = vel + accel * FIXED_DT;
    let newPos = pos + newVel * FIXED_DT;
    return vec4<f32>(newPos, newVel);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let density = clamp(u.zoom_params.x, 0.5, 4.0);
    let signalSpeed = clamp(u.zoom_params.y, 0.0, 4.0);
    let decayRate = clamp(u.zoom_params.z, 0.05, 2.5);
    let branches = clamp(u.zoom_params.w, 1.0, 8.0);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // ── Spring-dampered cursor: signals glide instead of snapping ──
    var springState = vec4<f32>(
        extraBuffer[STATE_POS_X], extraBuffer[STATE_POS_Y],
        extraBuffer[STATE_VEL_X], extraBuffer[STATE_VEL_Y]
    );
    // First frame after zero-init: snap to the raw cursor so we don't
    // sweep in from (0,0) corner on load.
    if (all(springState == vec4<f32>(0.0)) && dot(rawMouse, rawMouse) > 0.0001) {
        springState = vec4<f32>(rawMouse, 0.0, 0.0);
    }
    let nextSpring = springStep(springState.xy, springState.zw, rawMouse);
    // Single-thread writeback avoids a redundant write storm.
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[STATE_POS_X] = nextSpring.x;
        extraBuffer[STATE_POS_Y] = nextSpring.y;
        extraBuffer[STATE_VEL_X] = nextSpring.z;
        extraBuffer[STATE_VEL_Y] = nextSpring.w;
    }
    let mousePos = clamp(springState.xy, vec2<f32>(0.0), vec2<f32>(1.0));

    var activity = 0.0;
    var sparks = 0.0;
    let nodeCount = 5u + u32(density * 2.0);

    for (var i: u32 = 0u; i < nodeCount; i = i + 1u) {
        let seed = f32(i) * 17.23;
        let neuronPos = vec2<f32>(
            hash(vec2<f32>(seed, 0.13)),
            hash(vec2<f32>(seed, 9.71))
        );
        // ── Per-neuron FFT voice: each neuron listens to its own bin ──
        let voiceBin = u32(hash(vec2<f32>(seed, 4.17)) * 8.0) % 8u + 1u;
        let voice = clamp(plasmaBuffer[voiceBin].x, 0.0, 1.0);
        let toNeuron = uv - neuronPos;
        let dist = max(length(toNeuron), 0.001);
        let connectionDist = distance(neuronPos, mousePos);
        let signalPhase = time * (3.0 + bass * 6.0) - connectionDist * (2.5 + signalSpeed * 2.0) * 6.0;
        let pulse = sin(signalPhase) * exp(-connectionDist * (1.5 + decayRate)) * (0.55 + 0.9 * voice);
        let angle = atan2(toNeuron.y, toNeuron.x);
        let dendrite = 0.5 + 0.5 * cos(angle * branches + time * (1.2 + treble * 3.0) + seed);
        let aura = pulse * dendrite / (dist * (2.5 + density) + 0.35);
        activity += aura;
        sparks += exp(-dist * (20.0 + treble * 15.0)) * (0.3 + 0.7 * abs(pulse));
    }

    // ── Click synapse bursts: each live ripple fires a temporary neuron ──
    // A click injects an expanding, decaying (~2s) pulse wave into the field.
    var clickBurst = 0.0;
    var clickSparks = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r: u32 = 0u; r < rippleCount; r = r + 1u) {
        let ripple = u.ripples[r];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.0) {
            continue;
        }
        // Decay slider also shortens/lengthens the burst tail.
        let fade = exp(-age * (2.0 + decayRate));
        let toClick = uv - ripple.xy;
        let clickDist = max(length(toClick), 0.001);
        // Signal Speed slider drives how fast the shockwave expands.
        let waveFront = age * (0.35 + signalSpeed * 0.2);
        let ring = sin((clickDist - waveFront) * 40.0) * exp(-abs(clickDist - waveFront) * 12.0);
        let strength = 0.6 + 0.4 * clamp(ripple.w, 0.0, 1.0);
        clickBurst += ring * fade * strength / (clickDist * 4.0 + 0.6);
        clickSparks += exp(-clickDist * 24.0) * fade * strength * 0.8;
    }
    activity += clickBurst;
    sparks += clickSparks;

    let mouseDist = distance(uv, mousePos);
    let mousePulse = sin(mouseDist * (16.0 + treble * 12.0) - time * (7.0 + bass * 4.0)) *
        exp(-mouseDist * (3.0 + density)) * (0.3 + bass * 0.7);

    let totalActivity = activity + mousePulse;
    let sampleUV = clamp(
        uv + vec2<f32>(totalActivity * 0.025, activity * 0.015 + mousePulse * 0.01),
        vec2<f32>(0.001, 0.001),
        vec2<f32>(0.999, 0.999)
    );
    let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let electricBlue = vec3<f32>(0.05, 0.45 + treble * 0.15, 1.0) * max(totalActivity, 0.0);
    let synapsePurple = vec3<f32>(0.9, 0.15, 1.0) * max(-totalActivity, 0.0) * 0.65;
    let warmSparks = vec3<f32>(1.0, 0.7 + mids * 0.2, 0.25) * sparks * (0.12 + bass * 0.08);
    // Cyan flash riding the click shockwave so bursts read as fresh firings.
    let clickGlow = vec3<f32>(0.35, 0.85, 1.0) * max(clickBurst, 0.0) * 0.45;
    let finalColor = baseColor.rgb + electricBlue + synapsePurple + warmSparks + clickGlow;
    let alpha = clamp(baseColor.a * 0.38 + abs(totalActivity) * 0.28 + sparks * 0.2 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + abs(totalActivity) * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(totalActivity, sparks, mousePulse, alpha));
}
