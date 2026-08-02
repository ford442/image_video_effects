// ═══════════════════════════════════════════════════════════════════
//  Scan Slice
//  Category: interactive-mouse
//  Features: multi-slice, hyperbolic-decay, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-23
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Width, y=OffsetScale, z=Aberration, w=BgDimming
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let sliceWidthBase = u.zoom_params.x * 0.2 + 0.01;
    let offsetParam    = u.zoom_params.y;
    let aberration     = u.zoom_params.z * 0.03;
    let dimming        = clamp(u.zoom_params.w, 0.0, 1.0);

    let rawMouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Weighted scanner head motion in persistent-safe state slots.
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mouse = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
        mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
        var springPos = mouse;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 9.0;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    let sliceCount = i32(clamp(2.0 + bass * 5.0 + mouseDown * 3.0, 1.0, 7.0));
    var maxBand = 0.0;
    var bestOffset = 0.0;
    var bestIndex = 0.0;

    for (var i = 0; i < 7; i++) {
        let sliceIndex = f32(i) - 0.5 * f32(sliceCount - 1);
        let phase = sliceIndex * 0.07 * PHI;
        let center = mouse.x + phase * sin(time * 0.6 + sliceIndex);
        let width = sliceWidthBase * (1.0 - 0.08 * abs(sliceIndex));
        let dx = abs(uv.x - center);
        let band = max(0.0, 1.0 - dx / max(width, 1e-4));
        let bandSmooth = smoothstep(0.0, 1.0, band);

        let activeMask = select(0.0, 1.0, i < sliceCount);
        let effectiveBand = bandSmooth * activeMask;
        let isBetter = step(maxBand, effectiveBand);

        let candidateOffset = (mouse.y - 0.5) * (offsetParam * 2.0)
                            + sin(time * (1.0 + sliceIndex * 0.3)) * 0.05 * sliceIndex;

        maxBand = mix(maxBand, effectiveBand, isBetter);
        bestOffset = mix(bestOffset, candidateOffset, isBetter);
        bestIndex = mix(bestIndex, sliceIndex, isBetter);
    }

    // Clicks stamp short-lived independent scan slices at normalized ripple
    // positions. The strongest click band competes with the sprung slice bank.
    let aspect = resolution.x / max(resolution.y, 0.001);
    var clickGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        let safeAge = max(age, 0.0);
        let live = step(0.0, age) * (1.0 - step(1.5, age));
        let clickWidth = sliceWidthBase * (0.8 + safeAge * 0.5);
        let clickBand = smoothstep(0.0, 1.0, max(0.0, 1.0 - abs(uv.x - rp.x) * aspect / max(clickWidth, 0.001))) * exp(-safeAge * 1.8) * live;
        let clickIsBetter = step(maxBand, clickBand);
        let clickOffset = (rp.y - 0.5) * (offsetParam * 2.0) + sin(safeAge * 16.0 + rp.x * 11.0) * 0.04;
        maxBand = mix(maxBand, clickBand, clickIsBetter);
        bestOffset = mix(bestOffset, clickOffset, clickIsBetter);
        bestIndex = mix(bestIndex, f32(ri % 7u) - 3.0, clickIsBetter);
        clickGlow = max(clickGlow, clickBand);
    }

    let sampleUV = clamp(uv + vec2<f32>(0.0, bestOffset), vec2<f32>(0.0), vec2<f32>(1.0));
    let abAmt = aberration * (0.4 + maxBand * 0.6);
    let rUV = clamp(sampleUV + vec2<f32>(abAmt, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(sampleUV - vec2<f32>(abAmt, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    let sliceBin = (u32(abs(bestIndex)) % 8u) + 1u;
    let sliceVoice = plasmaBuffer[sliceBin].x;
    let palettePhase = fract(bestIndex * 0.15 + 0.5 + time * 0.05);
    let palette = 0.55 + 0.45 * cos(2.0 * PI * (palettePhase + vec3<f32>(0.0, 0.33, 0.67)));
    var sliceCol = vec3<f32>(r, g, b);
    sliceCol = mix(sliceCol, sliceCol * (0.6 + palette * (0.7 + sliceVoice * 0.2)), maxBand * 0.3);
    let edge = pow(maxBand, 8.0);
    sliceCol = sliceCol + vec3<f32>(0.4, 0.7, 1.0) * edge * (0.6 + mids * 0.12 + treble * 0.18 + clickGlow * 0.2);

    let bgCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let gray = dot(bgCol, vec3<f32>(0.299, 0.587, 0.114));
    let desat = mix(bgCol, vec3<f32>(gray), dimming);
    let bgFinal = desat * (1.0 - dimming * 0.6);

    let isSlice = step(0.001, maxBand);
    var finalColor = mix(bgFinal, sliceCol, isSlice);
    let peak = max(max(finalColor.r, finalColor.g), finalColor.b);
    finalColor = max(finalColor, vec3<f32>(0.0)) * min(1.0, 1.8 / max(peak, 0.001));

    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.5 + maxBand * 0.4 + luma * 0.2, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
