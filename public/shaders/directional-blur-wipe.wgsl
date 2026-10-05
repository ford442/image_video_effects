// ═══════════════════════════════════════════════════════════════════
//  Directional Blur Wipe
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: wipe-front ramp; shutter-weighted comet kernel; long-exposure highlight streaks
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Wipe anchor = raw pointer. HEAD's extraBuffer[133..137] spring was dead:
    // the buffer is re-uploaded with zeros there every frame, so every pixel
    // but (0,0) anchored the line at the top-left corner.
    let mouse = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthScatter = mix(0.7, 1.3, depth);

    let split_pos_param = u.zoom_params.x;
    let angle_param = u.zoom_params.y;
    let strength_param = u.zoom_params.z * bass_env(bass, mids);
    let samples_param = u.zoom_params.w;

    // Angle lean rides the pointer y.
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

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var color = vec4<f32>(0.0);
    if (dist < 0.0) {
        color = src;
        // Echo the click flash faintly on the clean side of the line.
        color = color + vec4<f32>(clickGlow * 0.06, clickGlow * 0.05, clickGlow * 0.08, 0.0);
    } else {
        let num_samples = i32(samples_param * 50.0) + 5;
        // Idea 1: wipe-front ramp — the smear builds over a short ramp past
        // the seam, so the clean side flows into the blur as a moving front.
        let ramp = smoothstep(0.0, 0.08, dist);
        let strength = strength_param * 0.05 * depthScatter * (1.0 + clickKick) * ramp;

        var accum = vec3<f32>(0.0);
        var weight = 0.0;

        // Chromatic offset: R and B sample at slightly different offsets per sample
        for (var i = 0; i < num_samples; i = i + 1) {
            let t = f32(i) / f32(num_samples - 1);
            // Shutter curve front-loads the taps, so stretch the reach to keep
            // the overall smear length close to HEAD's flat box.
            let offset = dir * t * strength * 1.35;
            let chroma = treble * 0.01 * t * ramp;

            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            // Per-sample chromatic dispersion: R leads, B trails along dir.
            let sampleRUV = clamp(sampleUV + dir * chroma, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleBUV = clamp(sampleUV - dir * chroma, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
            let rTap = textureSampleLevel(readTexture, u_sampler, sampleRUV, 0.0).r;
            let bTap = textureSampleLevel(readTexture, u_sampler, sampleBUV, 0.0).b;
            let tap = vec3<f32>(rTap, sampleColor.g, bTap);
            // Idea 2: shutter-weighted comet kernel — heavy head, tapering tail.
            let shutter = 0.15 + 0.85 * (1.0 - t) * (1.0 - t);
            // Idea 3: long-exposure highlight streaks — bright taps weigh more,
            // so highlights drag into light trails across the blurred side.
            let tapLuma = dot(tap, vec3<f32>(0.299, 0.587, 0.114));
            let streak = 1.0 + 2.5 * smoothstep(0.6, 1.0, tapLuma) * ramp;
            let w = shutter * streak;
            accum = accum + tap * w;
            weight = weight + w;
        }
        let blurRGB = accum / weight;

        // Per-channel blur for chromatic dispersion
        let rUV = clamp(uv + dir * strength * 1.1, vec2<f32>(0.0), vec2<f32>(1.0));
        let bUV = clamp(uv - dir * strength * 0.9, vec2<f32>(0.0), vec2<f32>(1.0));
        let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

        color = vec4<f32>(mix(blurRGB.r, r, 0.3), blurRGB.g, mix(blurRGB.b, b, 0.3), mix(src.a, 1.0, ramp));

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

    // ACES on display RGB; semantic alpha = clean-side transmission, blurred
    // coverage, seam/flash boost.
    let rgb = acesToneMap(max(color.rgb, vec3<f32>(0.0)));
    let seam = 1.0 - smoothstep(0.0, 0.005 * (1.0 + clickGlow * 6.0), abs(dist));
    let alpha = clamp(color.a + seam * 0.25, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
