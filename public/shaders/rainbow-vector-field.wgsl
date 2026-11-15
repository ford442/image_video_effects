// ═══════════════════════════════════════════════════════════════════
//  Rainbow Vector Field
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: ring leading crest; angular spokes; held pointer swirl
//  A packing: ACES display RGBA. Depth is a displacement strength
// ═══════════════════════════════════════════════════════════════════
//  Pass 1 of 2 — feeds prismatic-feedback-loop.wgsl
//  Polar rainbow, outward spectral rings, displacement in depth.

#include "_prelude.wgsl"

fn custom_custom_mod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let center = vec2<f32>(0.5, 0.5);
    let delta = uv - center;
    let angle = atan2(delta.y, delta.x);
    let dist = length(delta);

    let mouseDist = length(uv - mousePos);
    let mouseWave = sin(mouseDist * u.zoom_params.x - time * 4.0) * (0.2 + held * 0.8) * 0.35;

    // ── Idea 3: held pointer swirl ─────────────────────────────────
    // The polar angle bends inside the pointer disk while the button
    // is down. Rings stay circular; the hue and the spokes follow.
    let swirl = exp(-mouseDist * mouseDist * 14.0) * held * 1.1;
    let spun = angle + swirl;

    let ringPhase = dist * (18.0 + mids * 12.0) - time * 2.0;
    let rings = sin(ringPhase) * 0.5 + 0.5;
    let ringBand = pow(rings, 3.0) * bass * 0.6;
    // ── Idea 1: ring leading crest ─────────────────────────────────
    // phase grows with distance, so cos > 0 is the side the ring
    // reaches first. Same ringPhase as the existing band.
    let crest = pow(max(cos(ringPhase), 0.0), 12.0);

    let freq = u.zoom_params.x * (1.0 + mids * 0.4);
    let hue = (spun + dist * freq * 2.0 + time * 0.5 + mouseWave + ringBand) / (2.0 * 3.14159);
    let hueFract = fract(hue);

    let h = hueFract * 6.0;
    let c = u.zoom_params.z * (1.0 + bass * 0.4);
    let x = c * (1.0 - abs(custom_custom_mod(h, 2.0) - 1.0));

    var rainbow = vec3<f32>(0.0);
    if (h < 1.0) { rainbow = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rainbow = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rainbow = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rainbow = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rainbow = vec3<f32>(x, 0.0, c); }
    else { rainbow = vec3<f32>(c, 0.0, x); }

    let saturation = mix(0.3, 1.0, u.zoom_params.y);
    rainbow = mix(vec3<f32>(length(rainbow)), rainbow, saturation);

    rainbow += vec3<f32>(ringBand * 0.9, ringBand * 0.5, ringBand) * (0.4 + bass * 0.8);
    rainbow += vec3<f32>(0.9, 0.95, 1.0) * crest * (0.12 + bass * 0.2);

    // ── Idea 2: angular spokes ─────────────────────────────────────
    // Frequency still means "how fine". The spokes are the direction
    // of the polar field, hidden in the exact centre.
    let spokeN = mix(6.0, 16.0, clamp(freq / 12.0, 0.0, 1.0));
    let spoke = pow(0.5 + 0.5 * cos(spun * spokeN), 18.0) * smoothstep(0.02, 0.12, dist);
    rainbow += vec3<f32>(1.0) * spoke * (0.06 + treble * 0.12);

    let brightness = dot(rainbow, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(brightness * (0.55 + bass * 0.35) + ringBand + crest * 0.25, 0.0, 1.0);
    let mapped = aces(max(rainbow, vec3<f32>(0.0)));
    let finalOut = vec4<f32>(mapped, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalOut);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalOut);

    let displacement = brightness * u.zoom_params.w * (1.0 + bass * 0.35) + mouseWave * 2.0 + crest * u.zoom_params.w;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(displacement, 0.0, 0.0, 0.0));
}
