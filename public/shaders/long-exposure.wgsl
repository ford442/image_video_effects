// ═══════════════════════════════════════════════════════════════════
//  Long Exposure Light Painting
//  Category: temporal
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Description: Simulates an open camera shutter accumulating light over
//    time. Bright regions of each frame persist and blend into a glowing
//    exposure buffer; darker regions fade slowly, leaving luminous trails.
//    Mouse click resets the exposure. Bass brightens incoming frames for
//    punchier accumulation; mids control the glow bloom radius; treble
//    adds fine sparkle to the brightest traces.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=accumulation_speed, y=decay_rate, z=glow_radius, w=threshold

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=accum_speed, y=decay, z=glow_r, w=threshold
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / res;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Current camera frame
    let current  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let curRGB   = current.rgb * (1.0 + bass * 0.4);  // bass brightens incoming

    // Accumulated exposure from previous frame (stored in dataTextureC)
    let prevAccum = textureLoad(dataTextureC, coord, 0);
    let prevRGB   = prevAccum.rgb;

    // Threshold: only pixels brighter than threshold contribute
    let threshold  = 0.05 + u.zoom_params.w * 0.35;
    let luma       = luminance(curRGB);
    let aboveThresh = clamp((luma - threshold) / max(1.0 - threshold, 0.001), 0.0, 1.0);

    // Contribution: bright pixels accumulate; dim ones don't add
    let accumSpeed = 0.04 + u.zoom_params.x * 0.20;
    let contribution = curRGB * aboveThresh * accumSpeed * (1.0 + treble * 0.25);

    // Decay: accumulated buffer slowly fades
    let decayRate = 0.97 + u.zoom_params.y * 0.029;  // 0.97–0.999
    let decayed   = prevRGB * clamp(decayRate, 0.0, 0.999);

    // Mouse click resets the buffer (mouseDown drives to zero)
    let mouseDown  = u.zoom_config.w;
    let resetMix   = clamp(mouseDown * 0.15, 0.0, 1.0);  // gradual reset
    let afterReset = mix(decayed, vec3<f32>(0.0), resetMix);

    // Accumulate new contribution; clamp to avoid runaway brightness
    var accumulated = clamp(afterReset + contribution, vec3<f32>(0.0), vec3<f32>(1.5));

    // Glow bloom: simple 3x3 blur of accumulated buffer contributes a halo
    let glowR = max(0.002, u.zoom_params.z * 0.008) * res.x;
    let gOff  = glowR / res;
    var glow  = accumulated;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rgb;
    let glowAmt  = (0.1 + mids * 0.3) * u.zoom_params.z;
    let glowBlend = glow * (1.0 / 5.0) * glowAmt;
    accumulated   = clamp(accumulated + glowBlend, vec3<f32>(0.0), vec3<f32>(1.5));

    // Final output: tone-map accumulation back to [0,1] (Reinhard)
    let finalRGB = accumulated / (accumulated + vec3<f32>(1.0));

    // Alpha: bright trails are opaque; fresh dark areas stay transparent
    let accumLuma = luminance(finalRGB);
    let alpha     = clamp(accumLuma * 1.4 + bass * 0.08, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(accumulated, 1.0));  // store raw HDR for next frame
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
