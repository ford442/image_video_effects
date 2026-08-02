// ═══════════════════════════════════════════════════════════════════
//  Mirror Dimension
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, click-spin
//  Complexity: Medium
//  Upgraded: 2026-05-17
//  Batch-22 upgrade: 2026-07-31 — spring-damped symmetry center,
//  click spin kicks, per-segment FFT shimmer, treble seam glow.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 0.001);

    // ── Spring-damped symmetry center ────────────────────────────────
    // The fracture point no longer snaps to the cursor: a critically
    // damped spring (zeta = 1) chases the RAW mouse, so the center of
    // symmetry drifts smoothly into place. Raw mouse stays the target.
    // State lives in extraBuffer[133..138] (reserved: [0..4], FFT: [5..132]).
    let mouseActive = step(0.001, u.zoom_config.y); // branchless gate on RAW mouse
    let springTarget = mix(vec2<f32>(0.5, 0.5), u.zoom_config.yz, mouseActive);
    if (global_id.x == 0u && global_id.y == 0u) {
        var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[137] < 0.5) {
            // First frame: start AT the target so we don't lurch in from (0,0).
            sPos = springTarget;
            sVel = vec2<f32>(0.0, 0.0);
        }
        let dt = clamp(time - extraBuffer[138], 0.0005, 0.05);
        let omega = 5.0; // low stiffness = slow drift; zeta = 1 (critical, no wobble)
        let sAcc = omega * omega * (springTarget - sPos) - 2.0 * omega * sVel;
        sVel = sVel + sAcc * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }
    // Every thread rides the sprung center (<=1 frame of slack IS the lag).
    let center = vec2<f32>(extraBuffer[133], extraBuffer[134]);

    // Params (saved-preset contract: ids, defaults, mapping order unchanged)
    let segments  = floor(mix(2.0, 12.0, u.zoom_params.x));
    let baseRotSpeed = mix(-1.0, 1.0, u.zoom_params.y);
    // Bass modulates rotation speed
    let rotSpeed  = baseRotSpeed * (1.0 + bass * 0.5);
    let offsetVal = u.zoom_params.z;
    // Mids modulate zoom intensity
    let zoom      = mix(0.5, 2.0, u.zoom_params.w) * (1.0 + mids * 0.15);

    // Center UV and correct aspect
    var p = uv - 0.5;
    p.x *= aspect;

    // Branchless mouse offset: apply when zoom_config.y > 0
    let m = (center - 0.5) * vec2<f32>(aspect, 1.0);
    p -= m * mouseActive;

    // Polar coords
    let r = length(p);
    var a = atan2(p.y, p.x);

    // Animate rotation
    a += u.config.x * rotSpeed;

    // ── Click mirror spins ───────────────────────────────────────────
    // Each live ripple is a one-way spin impulse: exp(-age * 2.0) * 2.0
    // radians, signed by a hash of the click position, so clicks whirl
    // the kaleidoscope and the whirl relaxes over ~2 seconds.
    var spinKick = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0) { continue; }
        let h = fract(sin(dot(rp.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        let dir = select(-1.0, 1.0, h >= 0.5);
        spinKick += dir * exp(-age * 2.0) * 2.0;
    }
    a += spinKick;

    // Segment angle
    let segmentAngle = 3.14159265 * 2.0 / max(segments, 1.0);

    // Segment index from the PRE-FOLD angle (drives per-segment FFT shimmer).
    // fract() keeps the modulo positive even for negative angles.
    let segIdx = u32(fract(floor(a / segmentAngle) / 8.0) * 8.0);

    // Branchless modulo into [0, segmentAngle] using fract — handles negatives
    a = fract(a / segmentAngle) * segmentAngle;

    // Triangle fold (mirror half of the segment)
    a = abs(a - segmentAngle * 0.5);

    // Convert back to cartesian
    var uv_new = vec2<f32>(cos(a), sin(a)) * r;

    // Offset and zoom
    uv_new += vec2<f32>(offsetVal * 0.1);
    uv_new *= zoom;

    // Un-correct aspect and un-center
    uv_new.x /= aspect;
    uv_new += 0.5;

    // Clamp displaced UV before sampling
    let uv_clamped = clamp(uv_new, vec2<f32>(0.0), vec2<f32>(1.0));

    var sampled = textureSampleLevel(readTexture, u_sampler, uv_clamped, 0.0);

    // ── Per-segment FFT shimmer ──────────────────────────────────────
    // Each folded segment pulses to its own spectrum bin: ±8% brightness.
    let segEnergy = plasmaBuffer[segIdx + 1u].x;
    sampled = vec4<f32>(sampled.rgb * (1.0 + (segEnergy - 0.5) * 0.16), sampled.a);

    // Meaningful alpha: encodes radial position + fold angle closeness + bass energy
    let foldCloseness = 1.0 - clamp(a / max(segmentAngle * 0.5, 0.001), 0.0, 1.0);
    let radialFactor  = clamp(1.0 - r * 0.8, 0.0, 1.0);
    let alpha = clamp(radialFactor * 0.5 + foldCloseness * 0.3 + bass * 0.2, 0.0, 1.0);

    // Treble seam glow: the mirror fold lines light up with the highs,
    // tracing the kaleidoscope's skeleton as the music brightens.
    let seamGlow = pow(foldCloseness, 6.0) * treble * 0.45;
    let glowColor = vec3<f32>(0.9, 0.95, 1.0) * seamGlow;

    let finalColor = vec4<f32>(sampled.rgb + glowColor, alpha);

    textureStore(writeTexture, coord, finalColor);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
