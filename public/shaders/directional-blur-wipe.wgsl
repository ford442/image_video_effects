// ═══════════════════════════════════════════════════════════════════
//  Directional Blur Wipe
//  Category: image
//  Features: mouse-driven, audio-reactive, blur-wipe, depth-scatter, chromatic-offset, upgraded-rgba
//  Complexity: High
//  Chunks From: directional-blur-wipe, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
//  Upgraded: 2026-07-31 (wired Split Pos slider + per-sample chroma, sprung wipe, click flash)
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouseRaw = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // ── Spring-damper wipe anchor ───────────────────────────────────
    // The split line rides a critically-damped spring chasing the raw
    // cursor, so the wipe sweeps with weight instead of teleporting.
    // Persistent state lives in extraBuffer[133..137] ([0..4] reserved,
    // [5..132] = engine FFT bins): 133/134 = sprung position (uv),
    // 135/136 = spring velocity, 137 = last update time.
    var mouse = mouseRaw;
    var springVel = vec2<f32>(0.0, 0.0);
    let hasState = arrayLength(&extraBuffer) > 137u;
    if (hasState) {
        mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasState) {
        let prevTime = extraBuffer[137];
        let dt = clamp(time - prevTime, 0.001, 0.05);
        var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (prevTime <= 0.0) {
            // First touch: seed the spring at the cursor so it never snaps.
            sPos = mouseRaw;
            sVel = vec2<f32>(0.0, 0.0);
        }
        // Critically damped spring: stiffness = omega^2, damping = 2*omega.
        let omega = 10.0;
        let accel = (mouseRaw - sPos) * (omega * omega) - sVel * (2.0 * omega);
        sVel = sVel + accel * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = time;
    }
    // Spring overshoot energy: nudges the blur side while the line settles.
    let springEnergy = clamp(length(springVel) * 2.0, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthScatter = mix(0.7, 1.3, depth);

    let split_pos_param = u.zoom_params.x;
    let angle_param = u.zoom_params.y;
    let strength_param = u.zoom_params.z * bass_env(bass, mids);
    let samples_param = u.zoom_params.w;

    // Angle lean rides the SPRUNG y, so the wipe axis lags with the line.
    let angle = angle_param * 6.28 + (mouse.y - 0.5) * 3.14;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let normal = vec2<f32>(-dir.y, dir.x);

    // Split Pos slider: offsets the wipe line along its own normal.
    // Default 0.5 => (0.5 - 0.5) * 0.6 = 0 => line exactly on the cursor,
    // bit-identical to the pre-upgrade behaviour.
    let p_line = mouse + normal * (split_pos_param - 0.5) * 0.6;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let p_line_aspect = vec2<f32>(p_line.x * aspect, p_line.y);
    let dist = dot(uv_aspect - p_line_aspect, normal);

    // ── Click wipe flashes ──────────────────────────────────────────
    // Each live ripple (guarded) briefly brightens the wipe line in its
    // vicinity (~1.0s decay) and kicks the local blur strength, so a
    // click flashes the transition as it sweeps past.
    var clickGlow = 0.0;
    var clickKick = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 1.0) { continue; }
        let decay = 1.0 - age;
        let rp_aspect = vec2<f32>(rp.x * aspect, rp.y);
        // Proximity of the click point to the wipe line (along its normal).
        let rp_line_dist = abs(dot(rp_aspect - p_line_aspect, normal));
        let line_prox = 1.0 - smoothstep(0.0, 0.35, rp_line_dist);
        clickGlow = clickGlow + decay * decay * line_prox;
        // Radial kick around the click point on the blur side.
        let rp_px_dist = distance(uv_aspect, rp_aspect);
        clickKick = clickKick + decay * exp(-rp_px_dist * 6.0);
    }
    clickGlow = min(clickGlow, 2.0);
    clickKick = min(clickKick, 1.5);

    var color = vec4<f32>(0.0);
    if (dist < 0.0) {
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        // Echo the click flash faintly on the clean side of the line.
        color = color + vec4<f32>(clickGlow * 0.06, clickGlow * 0.05, clickGlow * 0.08, 0.0);
    } else {
        let num_samples = i32(samples_param * 50.0) + 5;
        let strength = strength_param * 0.05 * depthScatter * (1.0 + clickKick + springEnergy * 0.25);

        var accum = vec3<f32>(0.0);
        var weight = 0.0;

        // Chromatic offset: R and B sample at slightly different offsets per sample
        for (var i = 0; i < num_samples; i = i + 1) {
            let t = f32(i) / f32(num_samples - 1);
            let offset = dir * t * strength;
            let chroma = treble * 0.01 * t;

            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            // Per-sample chromatic dispersion: R leads, B trails along dir.
            let sampleRUV = clamp(sampleUV + dir * chroma, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleBUV = clamp(sampleUV - dir * chroma, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
            let rTap = textureSampleLevel(readTexture, u_sampler, sampleRUV, 0.0).r;
            let bTap = textureSampleLevel(readTexture, u_sampler, sampleBUV, 0.0).b;
            accum = accum + vec3<f32>(rTap, sampleColor.g, bTap);
            weight = weight + 1.0;
        }
        let blurRGB = accum / weight;

        // Per-channel blur for chromatic dispersion
        let rUV = clamp(uv + dir * strength * 1.1, vec2<f32>(0.0), vec2<f32>(1.0));
        let bUV = clamp(uv - dir * strength * 0.9, vec2<f32>(0.0), vec2<f32>(1.0));
        let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

        color = vec4<f32>(mix(blurRGB.r, r, 0.3), blurRGB.g, mix(blurRGB.b, b, 0.3), 1.0);

        // Bass drives blur-side brightness pulse
        color = color + vec4<f32>(bass * 0.1 * (dist * 0.5 + 0.5), bass * 0.05, 0.0, 0.0);

        let line_width = 0.005;
        if (dist < line_width) {
             color = color + vec4<f32>(0.2 + mids * 0.1, 0.15 + treble * 0.1, 0.1, 0.0);
        }

        // Click flash: widening glow band hugging the wipe line.
        let flash_width = line_width * (1.0 + clickGlow * 6.0);
        if (dist < flash_width) {
            let flash_fall = 1.0 - dist / max(flash_width, 1e-4);
            color = color + vec4<f32>(clickGlow * 0.35, clickGlow * 0.28, clickGlow * 0.18, 0.0) * flash_fall;
        }
    }

    let alpha = color.a;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color.rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color.rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
