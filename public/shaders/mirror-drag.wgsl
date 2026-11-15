// ═══════════════════════════════════════════════════════════════════
//  Mirror Drag
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-trail, chromatic-ghost, audio-shatter, upgraded-rgba
//  Complexity: High
//  Chunks From: mirror-drag, bass_env, temporal-feedback
//  Created: 2024-01-01
//  Upgraded: 2026-05-31, 2026-11-15
//  Ideas: hinge crease; facet shade
//  A packing: linear trail RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let drag = u.zoom_params.x * bass_env(bass, mids);
    let mirror = u.zoom_params.y;
    let trailDecay = u.zoom_params.z;
    let shatterAmount = u.zoom_params.w;

    let mirroredUV = vec2<f32>(
        mix(uv.x, 1.0 - uv.x, mirror),
        uv.y
    );

    let mouseDiff = uv - mouse;
    let dragDistance = length(mouseDiff) * drag;
    let dragDir = select(vec2<f32>(0.0), mouseDiff / max(length(mouseDiff), 0.0001), length(mouseDiff) > 0.0001);

    let offset = dragDir * dragDistance * 0.1;
    let trailUV = clamp(mirroredUV - offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let current = textureSampleLevel(readTexture, u_sampler, trailUV, 0.0);

    // Temporal trail echo
    let historyCoord = vec2<i32>(clamp(vec2<f32>(mirroredUV * resolution), vec2<f32>(0.0), resolution - 1.0));
    let history = textureLoad(dataTextureC, historyCoord, 0);
    let decay = trailDecay * 0.9 + 0.05;
    let trail = mix(history * decay, current, isMouseDown * 0.1 + 0.05);

    // Chromatic ghost: R and B trail behind at different rates
    let rOffset = dragDir * dragDistance * 0.12;
    let bOffset = dragDir * dragDistance * 0.08;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(trailUV - rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(trailUV - bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let g = trail.g;

    let chromaColor = vec4<f32>(r, g, b, trail.a);

    // Audio shatter: treble breaks the mirror into angular shards
    let shardAngle = floor(atan2(mouseDiff.y, mouseDiff.x) * (4.0 + treble * 10.0)) / (4.0 + treble * 10.0);
    let shardDist = length(mouseDiff);
    let shardEdge = fract(shardDist * (10.0 + shatterAmount * 50.0 + bass * 20.0));
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(u.config.x - event.z, 0.0);
        clickFront += exp(-age * 1.7) * exp(-abs(length(uv - event.xy) - age * 0.4) * 60.0);
    }
    let facetRunner = sin(shardAngle * 18.0 + shardDist * 45.0 - u.config.x * (4.0 + mids * 5.0));
    let shatterGlow = smoothstep(0.9, 1.0, shardEdge) * (treble + clickFront) * shatterAmount;

    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + facetRunner * 2.0 + u.config.x);
    var finalRGB = chromaColor.rgb + spectral * (shatterGlow + abs(facetRunner) * shatterAmount * 0.06 * isMouseDown);

    // ── Idea 1: hinge crease ────────────────────────────────────────
    // The fold is where the straight plate and the mirrored plate disagree.
    // That seam is drawn on the axis, and it fades as Mirror Amount goes to 0.
    let plainUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let plain = textureSampleLevel(readTexture, u_sampler, plainUV, 0.0);
    let seam = length(plain.rgb - current.rgb);
    let onAxis = 1.0 - smoothstep(0.0, 0.045 + (1.0 - mirror) * 0.18, abs(uv.x - 0.5));
    let crease = clamp(seam * mirror * onAxis, 0.0, 1.0);
    finalRGB = mix(finalRGB, finalRGB * vec3<f32>(0.22, 0.26, 0.32), crease);
    finalRGB += vec3<f32>(0.75, 0.82, 0.95) * crease * 0.45;

    // ── Idea 2: facet shade ─────────────────────────────────────────
    // The shard angle already cuts the glass. Shade the face, not only the crack.
    let facetLit = 0.78 + 0.22 * sin(shardAngle + shardDist * 2.5);
    finalRGB *= mix(1.0, facetLit, shatterAmount);

    let alpha = clamp(chromaColor.a + shatterGlow + bass * 0.05 + crease * 0.25, 0.0, 1.0);
    let linearRGB = max(finalRGB, vec3<f32>(0.0));
    let shown = vec4<f32>(aces(linearRGB), alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), shown);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(linearRGB, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
