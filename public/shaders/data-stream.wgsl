// ═══════════════════════════════════════════════════════════════════
//  Data Stream
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  By: Phase A Upgrade Swarm
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Speed, y=Density, z=Turbulence, w=Glow
  ripples: array<vec4<f32>, 50>,
};

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

    // Spring-following wake center in persistent-safe slots [133..138].
    let rawMouse = u.zoom_config.yz;
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mousePos = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
        mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
        var springPos = mousePos;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 8.5;
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

    // Aspect-correct interaction keeps the wake circular on wide canvases.
    let dist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let interactRadius = 0.3;
    let interact = smoothstep(interactRadius, 0.0, dist) * turbulence;

    // Create Strips
    let numStrips = 20.0 + density * 100.0;
    let stripIdx = floor(uv.x * numStrips);

    // Random per strip
    let rand = fract(sin(stripIdx * 12.9898) * 43758.5453);

    // Vertical Flow
    let stripBin = (u32(abs(stripIdx)) % 8u) + 1u;
    let fftStrip = plasmaBuffer[stripBin].x;
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
    var outputColor = finalRGB + vec3<f32>(0.0, bright * glow + clickGlow * glow * 0.65, clickGlow * glow * 0.12);
    let outputPeak = max(max(outputColor.r, outputColor.g), outputColor.b);
    outputColor *= min(1.0, 1.8 / max(outputPeak, 0.001));

    // Alpha: digital glow and stream brightness drive compositing weight
    let streamLuma = dot(outputColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(glow * 0.5 + bright * 0.3 + streamLuma * 0.3, 0.0, 1.0);

    let outColor = vec4<f32>(outputColor, alpha);

    textureStore(writeTexture, coord, outColor);

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
