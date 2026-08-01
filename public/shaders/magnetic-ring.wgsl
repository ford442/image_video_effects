// ═══════════════════════════════════════════════════════════════════
//  Magnetic Ring
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, magnetic-field, particle-trails, upgraded-rgba
//  Complexity: High
//  Chunks From: magnetic-ring, bass_env, hash21
//  Upgraded: 2026-05-31
//  Interactivist pass: 2026-07-31 — sprung magnet center (extraBuffer
//  [133..138]), click flux shockwaves, per-ring FFT voices
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let baseRadius = mix(0.02, 0.45, u.zoom_params.x);
    let strength = u.zoom_params.y * bass_env(bass, mids);
    let pulseSpeed = mix(0.5, 8.0, u.zoom_params.z);
    let ringThickness = mix(0.01, 0.18, u.zoom_params.w);

    // ── Priority 1: spring-damper the ring center ─────────────────────
    // The raw cursor is only the spring TARGET; the ring system drags
    // after it like a real magnet. Persistent state (extraBuffer, engine
    // reserves [0..4], FFT bins [5..132], shader state in [133..255]):
    //   [133..134] sprung center position, [135..136] spring velocity,
    //   [137] init flag, [138] last integration time.
    if (global_id.x == 0u && global_id.y == 0u) {
        var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[137] < 0.5) {
            sPos = mousePos;
            sVel = vec2<f32>(0.0, 0.0);
        }
        let dt = clamp(time - extraBuffer[138], 0.0005, 0.05);
        let omega = 9.0; // critically damped: zeta = 1
        let sAcc = omega * omega * (mousePos - sPos) - 2.0 * omega * sVel;
        sVel = sVel + sAcc * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }
    // All threads ride the sprung center (≤1 frame of slack IS the drag).
    let magnetPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let magnetLag = length(magnetPos - mousePos);

    // Aspect correction is applied to the SPRUNG position, not raw mouse.
    let dVec = uv - magnetPos;
    let dVecAspect = vec2<f32>(dVec.x * aspect, dVec.y);
    let dist = length(dVecAspect);
    let safeDir = dVecAspect / max(dist, 0.001);
    let pulse = sin(time * pulseSpeed * bass_env(bass, mids) - dist * 20.0) * 0.5 + 0.5;

    // Multiple concentric rings for field line effect — each ring now
    // throbs on its OWN spectrum voice (bass/mids/treble neighbours)
    // instead of sharing the single global pulse.
    let rings = 3.0;
    var ringMask = 0.0;
    var fieldLines = 0.0;
    var voiceGlow = vec3<f32>(0.0, 0.0, 0.0);
    for (var i: f32 = 0.0; i < rings; i = i + 1.0) {
      let r = baseRadius * (1.0 + i * 0.6);
      let m = 1.0 - smoothstep(0.0, ringThickness, abs(dist - r));
      ringMask = ringMask + m;
      let fieldAngle = atan2(dVecAspect.y, dVecAspect.x) + i * 1.047;
      let fl = smoothstep(0.0, 0.05, abs(fract(fieldAngle * 8.0 / (i + 1.0)) - 0.5)) * m;
      fieldLines = fieldLines + fl;
      // Per-ring FFT voice: ring i listens to plasmaBuffer[i + 1].x and
      // runs its pulse at its own rate (z slider stays the global speed).
      let voice = plasmaBuffer[u32(i) + 1u].x;
      let ringPulse = sin(time * pulseSpeed * (0.7 + voice * 0.8) - dist * 20.0 + i * 2.094) * 0.5 + 0.5;
      let voiceHue = vec3<f32>(0.25 + 0.25 * i, 0.45 + mids * 0.1, 0.75 - 0.15 * i);
      voiceGlow = voiceGlow + voiceHue * m * (0.25 + ringPulse * 0.75) * (0.5 + voice * 1.2);
    }

    // ── Click flux shockwaves ─────────────────────────────────────────
    // Each live click ripple adds a temporary fourth ring expanding from
    // its click point at radius age*0.4 (~1.5s fade), plus a local pulse
    // boost, so clicks fire flux surges across the field.
    var shockBoost = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri: u32 = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 1.5) {
            let rdAspect = vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y);
            let rDist = length(rdAspect);
            let decay = 1.0 - age / 1.5;
            let band = 1.0 - smoothstep(0.0, ringThickness * 1.5, abs(rDist - age * 0.4));
            ringMask = ringMask + band * decay * decay;
            shockBoost = shockBoost + decay * exp(-rDist * 3.0);
        }
    }
    ringMask = clamp(ringMask, 0.0, 1.0);

    let displacement = safeDir * ringMask * strength * (0.03 + pulse * 0.04);
    let offsetUV = vec2<f32>(displacement.x / aspect, displacement.y);

    let baseUV = clamp(uv + offsetUV, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let rgbOffset = offsetUV * (0.35 + strength * 0.85);
    let rUV = clamp(uv + rgbOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let gUV = baseUV;
    let bUV = clamp(uv - rgbOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let gColor = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    // Magnetic lag energizes the field; hash21 grain keeps lines alive.
    let grain = hash21(vec2<f32>(global_id.xy) * 0.013 + vec2<f32>(time * 0.7, -time * 0.31));
    let lagGlow = 1.0 + magnetLag * 2.5 + shockBoost * 0.9;
    let ringGlow = vec3<f32>(0.2 + treble * 0.1, 0.4 + mids * 0.1, 0.7) * ringMask * (0.3 + pulse * 0.7);
    let fieldGlow = vec3<f32>(0.1, 0.8, 1.0) * fieldLines * pulse * 0.5 * (0.85 + grain * 0.3);
    let shockGlow = vec3<f32>(0.9, 0.6, 1.0) * shockBoost * ringMask * 0.6;
    let finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        gColor.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    ) + ringGlow * lagGlow + voiceGlow + fieldGlow + shockGlow;

    let alpha = clamp(gColor.a * 0.45 + ringMask * 0.3 + bass * 0.05 + fieldLines * 0.1 + shockBoost * 0.15, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + ringMask * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
