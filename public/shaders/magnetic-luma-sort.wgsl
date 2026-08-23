// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn get_luma(color: vec3<f32>) -> f32 {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
    return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

// Persistent spring state lives in extraBuffer[133..138] (shader-owned region
// is [133..255]; [0..4] reserved, [5..132] = engine FFT bins):
//   [133] = smoothed magnet x, [134] = smoothed magnet y
//   [135] = spring velocity x, [136] = spring velocity y
//   [137] = last frame timestamp, [138] = initialization flag
// Every invocation integrates the SAME previous state, so all threads agree on
// the result; only thread (0,0) writes the advanced state back.

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let pullStrength = u.zoom_params.x * 0.05; // Scaling for reasonable speed
    // Bass loosens the sort: beats lower the effective luma threshold.
    let threshold = u.zoom_params.y * (1.0 - bass * 0.3);
    let decay = u.zoom_params.z;
    let repel = step(0.5, u.zoom_params.w); // 0 or 1

    // --- Critically-damped spring attractor ---
    // The raw mouse stays the spring TARGET; the magnet itself glides.
    let time = u.config.x;
    let rawMouse = u.zoom_config.yz;
    let hasSpring = arrayLength(&extraBuffer) >= 139u;
    var prevTime = time;
    var initialized = false;
    if (hasSpring) { prevTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
    let dt = clamp(time - prevTime, 0.001, 0.05);

    var magnetPos = rawMouse;
    var magnetVel = vec2<f32>(0.0);
    if (hasSpring) {
        magnetPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        magnetVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    }
    if (!initialized) {
        // First frame after init: snap to the cursor so we don't glide in from origin.
        magnetPos = rawMouse;
        magnetVel = vec2<f32>(0.0, 0.0);
    }

    // Critical damping: accel = omega^2 * (target - pos) - 2 * omega * vel.
    let omega = 14.0;
    let springAccel = omega * omega * (rawMouse - magnetPos) - 2.0 * omega * magnetVel;
    magnetVel = magnetVel + springAccel * dt;
    magnetPos = magnetPos + magnetVel * dt;

    if (hasSpring && global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = magnetPos.x;
        extraBuffer[134] = magnetPos.y;
        extraBuffer[135] = magnetVel.x;
        extraBuffer[136] = magnetVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    var mousePos = magnetPos;
    let aspect = resolution.x / resolution.y;

    // Vector to mouse
    var dirToMouse = mousePos - uv;
    dirToMouse.x *= aspect;
    let dist = length(dirToMouse);

    var dir = normalize(dirToMouse);
    if (dist < 0.001) { dir = vec2(0.0, 0.0); }

    if (repel > 0.5) {
        dir = -dir;
    }

    // Read current image source
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = get_luma(srcColor.rgb);

    // Read history (trail)
    // We want to sample the history from "upstream".
    // If pixels move towards mouse, we (at current pixel) look AWAY from mouse to see what's coming.
    // Movement speed depends on luma. Brighter = faster.

    var speed = 0.0;
    if (luma > threshold) {
        speed = pullStrength * (luma - threshold) / (1.0 - threshold + 0.001);
    }

    // Per-row read-only FFT voice lives in engine slots [5..132].
    let band = min(u32(uv.y * 128.0), 127u);
    var fftVoice = 0.0;
    if (arrayLength(&extraBuffer) >= 133u) { fftVoice = clamp(extraBuffer[5u + band], 0.0, 1.0); }
    speed = speed * (1.0 + bass * 0.35 + mids * 0.2 + treble * 0.15 + fftVoice * 0.4);

    // Dampen speed by distance? Maybe infinite reach is better.
    // Let's dampen slightly so the edge of screen doesn't pull too hard if mouse is center.
    // speed *= smoothstep(0.0, 0.1, dist);

    // Main pull vector (before the offset is applied).
    var pull = dir * speed;

    // Click vortex pulses: each live ripple adds a decaying second attractor at
    // its click point, stirring the flow. Composed with the main pull here.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge < 0.0 || rippleAge > 3.0) { continue; }

        var dirToRipple = ripple.xy - uv;
        dirToRipple.x *= aspect;
        let rippleDist = length(dirToRipple);

        var rippleDir = vec2<f32>(0.0, 0.0);
        if (rippleDist > 0.001) { rippleDir = normalize(dirToRipple); }
        if (repel > 0.5) { rippleDir = -rippleDir; }

        // Smoothstep falloff over a ~0.25 radius, decaying with exp(-age * 2).
        let falloff = smoothstep(0.25, 0.0, rippleDist);
        let pulse = exp(-rippleAge * 2.0);
        pull = pull + rippleDir * (speed * falloff * pulse);
    }

    let offset = -pull;

    // Sample history at the upstream position
    let historyUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let historyDims = vec2<i32>(textureDimensions(dataTextureC));
    let historyColor = textureLoad(dataTextureC, historyCoord(historyUV, historyDims), 0);

    // Combine
    // If we are just moving the image, we should primarily see the history moving.
    // But we need to inject the new frame's content otherwise it fades out or is empty initially.
    // A common "trail" technique is max(current, history * decay).

    // Let's try a blend:
    // The "moved" content is history. The "source" is the current video frame.
    // If we only use history, the video won't update.
    // So we mix current frame into history.

    // (Dead finalColor experiment removed: the mix/max candidates above were
    // computed and then thrown away - `mixed` below was always what won.)

    // To make it look like "sorting" or "smearing", we heavily favor the displaced history
    // but we clamp it so it doesn't blow out.

    // Alternative: If the pixel is bright enough to move, it "leaves" its spot and "arrives" at the next.
    // This is hard in a gather-based shader.
    // Gather approach: I am pixel P. Who arrived here?
    // The pixel at P + offset (away from mouse) arrived here if it was moving towards mouse.

    // Let's stick to the feedback loop approach.
    // New Value = (Old Value at Upstream P) * Decay + (Current Input) * Blend

    let mixed = mix(srcColor, historyColor, decay);
    let trailEnergy = clamp(length(mixed.rgb - srcColor.rgb) * 1.5 + speed * 7.0, 0.0, 1.0);
    let alpha = clamp(srcColor.a + (1.0 - srcColor.a) * trailEnergy, 0.0, 1.0);
    let display = vec4<f32>(acesToneMap(max(mixed.rgb, vec3<f32>(0.0))), alpha);

    // If luma is low, we don't move history much?
    // Actually, if luma is low (speed 0), offset is 0. So we sample history at current UV.
    // This results in a standard feedback trail.

    textureStore(writeTexture, vec2<i32>(global_id.xy), display);
    textureStore(dataTextureA, global_id.xy, display);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
