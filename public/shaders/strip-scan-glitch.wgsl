// ═══════════════════════════════════════════════════════════════════
//  Strip Scan Glitch
//  Category: interactive-mouse
//  Features: audio-reactive, upgraded-rgba, mouse-driven, held-drag
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: vertical-blanking seam (each strip's wrap shows a black blanking bar with sync-pulse ticks and a soft smear on the rows either side); held brake (holding drags the strips under the cursor to a freeze-frame halt with treble flutter, releasing back to speed); speed-streak ghost (fast strips leave a short vertical smear read from C along their scroll direction)
//  A packing: pre-ACES linear display RGB + source-derived alpha; C read back as colour (brake freeze + streak taps)
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
  config: vec4<f32>,              // x=time, y=clickCount, z=resX, w=resY
  zoom_config: vec4<f32>,         // x=zoomTime, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,         // x=Strip Count, y=Scroll Speed, z=Glitch Jitter, w=RGB Split
  ripples: array<vec4<f32>, 50>,
};

fn hash11(x: f32) -> f32 { return fract(sin(x * 12.9898) * 43758.5453); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Full-RGB wrapped sample of the source at a per-strip scrolled position.
fn sampleWrapped(uvIn: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, non_filtering_sampler, fract(uvIn), 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);

    // Parameters
    // x: Strip Count (10 - 300)
    // y: Speed (Vertical scroll speed)
    // z: Jitter (Horizontal glitchiness)
    // w: RGB Split (Chromatic aberration)
    let stripCountParam = u.zoom_params.x;
    let speedParam = u.zoom_params.y;
    let jitterParam = u.zoom_params.z;
    let rgbSplitParam = u.zoom_params.w;

    let mouseX = u.zoom_config.y;
    let mouseY = u.zoom_config.z;
    let held = u.zoom_config.w > 0.5;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

    // Mix mouseX into strip count for interactive density (clamped: HEAD extrapolated past 300).
    let stripCount = mix(10.0, 300.0, clamp(stripCountParam + (mouseX * 0.5) + mids * 0.15, 0.0, 1.0));
    let speed = ((speedParam - 0.5) * 4.0 + (mouseY - 0.5) * 4.0) * (1.0 + bass * 0.5);
    let time = u.config.x;
    // Wrapped clock: speed*time is only ever used through fract(), so a 600 s wrap keeps the
    // product in a range where f32 still resolves sub-texel phase.
    let tWrap = time - floor(time / 600.0) * 600.0;

    // Quantize X to create strips
    let stripIdx = floor(uv.x * stripCount);
    let stripCenterU = (stripIdx + 0.5) / stripCount;
    let stripHash = hash11(stripIdx);

    // Brighter strips scan faster (sampled at the strip's centre column).
    let stripBrightness = textureSampleLevel(readTexture, non_filtering_sampler, vec2<f32>(stripCenterU, 0.5), 0.0).g;
    let brightScan = 0.6 + stripBrightness * 0.8;
    let stripSpeed = speed * (0.5 + 0.5 * stripHash) * brightScan;   // screen heights per second
    let yScroll = fract(stripSpeed * tWrap);                          // per-strip wrapped phase
    let yOffset = yScroll + sin(uv.y * 10.0 + time) * 0.05 * jitterParam;

    // Horizontal Jitter (Glitch): bass lowers the threshold so beats tear more strips loose.
    let jitter = (fract(sin(time * 10.0 + stripIdx) * 43758.5453) - 0.5) * 2.0;
    var xOffset = 0.0;
    if (abs(jitter) > (1.0 - jitterParam * 0.8 - bass * 0.15)) {
        xOffset = jitter * 0.02 * jitterParam * (1.0 + bass);
    }

    // Final UVs per channel for RGB split (max 2% shift)
    let split = rgbSplitParam * 0.02;
    let uvR = vec2<f32>(uv.x + xOffset + split, uv.y + yOffset);
    let uvG = vec2<f32>(uv.x + xOffset,         uv.y + yOffset);
    let uvB = vec2<f32>(uv.x + xOffset - split, uv.y + yOffset);

    let sampleR = sampleWrapped(uvR);
    let sampleG = sampleWrapped(uvG);
    let sampleB = sampleWrapped(uvB);

    var finalColor = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);

    // Alpha: blend from each channel sample; strips with high jitter have corrupted alpha.
    let jitterAlphaMod = 1.0 - abs(jitter) * jitterParam * 0.2;
    var finalAlpha = (sampleR.a + sampleG.a + sampleB.a) / 3.0 * jitterAlphaMod;
    if (stripHash > 0.9) { finalAlpha = finalAlpha * 0.8; }
    finalAlpha = clamp(finalAlpha, 0.0, 1.0);

    // IDEA 1 — vertical-blanking seam. The wrap point of the strip (source v crossing 1 -> 0) is a
    // signal rollover: a black blanking bar of a few lines with bright sync-pulse ticks along it,
    // and the picture smears vertically on the rows just before and after the bar as the
    // "field" settles. The seam only exists on strips that actually scroll.
    let sv = fract(uvG.y);
    let seamDist = min(sv, 1.0 - sv);                               // source-space distance to the wrap
    let seamPresent = smoothstep(0.0, 0.05, abs(stripSpeed));
    let barHalf = 0.006;
    let bar = (1.0 - smoothstep(barHalf * 0.6, barHalf, seamDist)) * seamPresent;
    let smear = smoothstep(0.045, barHalf, seamDist) * seamPresent;
    if (smear > 0.001) {
        // 2-tap vertical smear along the scroll direction (the picture ahead of the seam drags).
        let dir = sign(stripSpeed + 1e-4);
        let s1 = sampleWrapped(uvG + vec2<f32>(0.0, dir * 0.012)).rgb;
        let s2 = sampleWrapped(uvG + vec2<f32>(0.0, dir * 0.026)).rgb;
        finalColor = mix(finalColor, (finalColor + s1 + s2) / 3.0, smear * 0.85);
    }
    // Sync-pulse ticks: short bright dashes spaced along the bar, phase hashed per strip.
    let tickPhase = fract(uv.x * stripCount * 5.0 + stripHash * 3.0);
    let tick = step(0.55, tickPhase) * step(tickPhase, 0.85) * (1.0 - smoothstep(0.0, barHalf * 0.45, seamDist));
    finalColor = mix(finalColor, vec3<f32>(0.0), bar);
    finalColor += vec3<f32>(0.85, 0.95, 0.9) * tick * bar * 0.9;
    finalAlpha = max(finalAlpha, bar);

    // Bass fires a scanline bar sweeping down the frame (Gaussian written as x*x; pow(neg) is NaN).
    let scanY = fract(time * 0.35);
    let dy = uv.y - scanY;
    let scanBar = exp(-(dy * dy) * 900.0) * bass;
    finalColor = finalColor + vec3<f32>(0.3, 0.9, 0.7) * scanBar * 0.8;
    finalAlpha = clamp(finalAlpha + scanBar * 0.3, 0.0, 1.0);

    // C history (pre-ACES linear display RGB from last frame).
    let prev = clamp(textureLoad(dataTextureC, coord, 0), vec4<f32>(0.0), vec4<f32>(4.0));

    // IDEA 3 — speed-streak ghost. Fast strips drag a short vertical smear behind them: two exact
    // C taps up-stream of the scroll direction, weighted by the strip's own speed so slow strips
    // stay crisp. Mixed (not added) so the feedback cannot run away.
    let streakAmt = clamp(abs(stripSpeed) * 0.22, 0.0, 0.55);
    if (streakAmt > 0.01) {
        let dpx = i32(sign(stripSpeed)) * 4;   // screen y is 0 at top; scrolling +v moves content up
        let ya = clamp(coord.y + dpx, 0, i32(resolution.y) - 1);
        let yb = clamp(coord.y + dpx * 2, 0, i32(resolution.y) - 1);
        let g1 = textureLoad(dataTextureC, vec2<i32>(coord.x, ya), 0).rgb;
        let g2 = textureLoad(dataTextureC, vec2<i32>(coord.x, yb), 0).rgb;
        let ghost = clamp((g1 * 0.65 + g2 * 0.35), vec3<f32>(0.0), vec3<f32>(4.0));
        finalColor = mix(finalColor, max(finalColor, ghost * 0.9), streakAmt);
    }

    // IDEA 2 — held brake. While the pointer is held, the strips near the cursor column are
    // dragged to a halt: the display holds last frame's picture from C (a freeze frame) in
    // proportion to an aspect-weighted distance from mouse X, and treble flutter lets single
    // fresh frames slip through as the head chatters. Releasing hands the strips straight back
    // to their scroll speed since the freeze only ever lived in C.
    var brake = 0.0;
    if (held) {
        let dx = abs(stripCenterU - mouseX) * aspect;
        brake = 1.0 - smoothstep(0.05, 0.42, dx);
        let flutter = step(0.75, hash11(floor(time * 24.0) + stripIdx * 0.37)) * treble * 0.6;
        brake = clamp(brake * (1.0 - flutter), 0.0, 0.97);
    }
    finalColor = mix(finalColor, prev.rgb, brake);
    finalAlpha = mix(finalAlpha, prev.a, brake * 0.9);

    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(4.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(finalColor), finalAlpha));

    // Pass through depth
    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
