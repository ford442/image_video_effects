// ═══════════════════════════════════════════════════════════════════
//  Data Stream — Batch 61
//  Matrix data strips: hex glyphs, cyber palette, capped ripples,
//  held turbulence, ACES.
//  Upgraded: 2026-10-27
//  Ideas: leading head on each falling cell; column dropout
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn cyberPalette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(1.0) * t + vec3<f32>(0.0, 0.33, 0.67)));
}

fn glyphMask(cellUV: vec2<f32>, id: f32) -> f32 {
  let bar = step(0.25, cellUV.x) * step(cellUV.x, 0.75) * step(0.15, cellUV.y);
  let dot = step(length(cellUV - vec2<f32>(0.5)), 0.2);
  return max(bar, dot * step(fract(id * 0.41), 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let speed = max(u.zoom_params.x * (1.0 + bass * 0.3), 0.001); // Flow Speed
    let density = max(u.zoom_params.y, 0.001); // Strip Density
    let turbulence = clamp(u.zoom_params.z, 0.0, 1.0); // Mouse turbulence
    let glow = clamp(u.zoom_params.w, 0.0, 1.0); // Digital Glow

    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 0.001);
    let held = u.zoom_config.w > 0.5;

    // extraBuffer is cleared by the CPU every frame, so the old spring
    // never left the pointer. The wake is the cursor.
    let mousePos = u.zoom_config.yz;

    // Aspect-correct interaction keeps the wake circular on wide canvases.
    let dist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let interactRadius = 0.3 * select(1.0, 1.3, held);
    let interact = smoothstep(interactRadius, 0.0, dist) * turbulence;

    // Create Strips
    let numStrips = 20.0 + density * 100.0;
    let stripIdx = floor(uv.x * numStrips);

    // Random per strip
    let rand = fract(sin(stripIdx * 12.9898) * 43758.5453);

    // Vertical Flow
    // plasmaBuffer[1..] is never uploaded. Strips take turns on the three live bands.
    let stripBand = u32(abs(stripIdx)) % 3u;
    let fftStrip = select(select(bass, mids, stripBand == 1u), treble, stripBand == 2u) * (0.65 + 0.35 * rand);
    let flowSpeed = (rand * 0.5 + 0.5) * speed * 0.5 * (1.0 + fftStrip * 0.28);
    // Mouse slows down or speeds up flow? Or deflects?
    // Let's make mouse create a "wake" that pushes pixels sideways

    var clickWake = 0.0;
    var clickGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let safeAge = max(age, 0.0);
        let live = step(0.0, age) * (1.0 - step(1.6, age));
        let clickVec = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
        let clickDist = length(clickVec);
        let ring = 1.0 - smoothstep(0.018, 0.065, abs(clickDist - safeAge * 0.34));
        let wave = ring * exp(-safeAge * 1.7) * live;
        clickWake += wave * sin(uv.y * 24.0 + rp.x * 19.0 + safeAge * 8.0);
        clickGlow = max(clickGlow, wave);
    }

    let xOffset = interact * sin(uv.y * 10.0 + time * 5.0) * 0.05 + clickWake * turbulence * 0.045;

    var sampleUV = uv;
    sampleUV.x = sampleUV.x + xOffset;
    sampleUV.y = sampleUV.y - time * flowSpeed; // Flow down

    // Wrap Y
    sampleUV.y = fract(sampleUV.y);

    // Glitch effect on strips (branchless)
    sampleUV.y = sampleUV.y + select(0.0, sin(time * 10.0) * 0.01, rand > 0.8);

    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Digital artifacts
    let blockY = floor(uv.y * 50.0);
    let noise = fract(sin(dot(vec2<f32>(stripIdx, blockY), vec2<f32>(12.9898, 78.233))) * 43758.5453);

    // Green tint / glow
    let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let digitalColor = vec3<f32>(0.0, lum * 1.5, lum * 0.2); // Green matrix style

    // Random "bright" characters
    let brightThreshold = 0.98 - treble * 0.04 - fftStrip * 0.035;
    let bright = step(brightThreshold, noise * (sin(time * 2.0 + stripIdx) * 0.5 + 0.5));

    let finalRGB = mix(color.rgb, digitalColor, glow);
    let gridSize = vec2<f32>(24.0 + density * 40.0, (24.0 + density * 40.0) * aspect);
    let cellUV = fract(uv * gridSize);
    let glyph = glyphMask(cellUV, stripIdx + time * 0.1);
    // ── Idea 1: leading head. The fall is downward, so the bottom of the
    // cell is the bright head and the top is the tail.
    let head = mix(0.22, 1.0, smoothstep(0.05, 0.92, cellUV.y));
    // ── Idea 2: column dropout, scaled by Turbulence.
    let dropSeed = fract(sin(stripIdx * 91.7 + floor(time * 2.5) * 13.1) * 43758.5453);
    let dropout = step(0.965, dropSeed) * turbulence;
    var outputColor = finalRGB + vec3<f32>(0.0, bright * glow * head + clickGlow * glow * 0.65, clickGlow * glow * 0.12);
    outputColor = mix(outputColor, outputColor + cyberPalette(stripIdx * 0.05 + time * 0.03) * 0.25, glyph * glow * 0.4 * head);
    outputColor = outputColor * (1.0 - dropout * 0.88);
    outputColor = acesToneMap(outputColor * (0.95 + bass * 0.08));

    // Alpha: digital glow and stream brightness drive compositing weight
    let streamLuma = dot(outputColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(glow * 0.5 + bright * 0.3 + streamLuma * 0.3, 0.0, 1.0);

    let outColor = vec4<f32>(outputColor, alpha);

    textureStore(writeTexture, coord, outColor);

    // Passthrough depth
    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
