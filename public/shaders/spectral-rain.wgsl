// ═══════════════════════════════════════════════════════════════════
//  Spectral Rain
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
// ═══════════════════════════════════════════════════════════════════
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,  // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=ChromaticStr, z=TrailLen, w=AngleControl
  ripples:     array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / max(dims.y, 1.0);

    // Mouse Controls
    var mouse = u.zoom_config.yz;
    let angleVal = (mouse.x - 0.5) * 2.0; // -1 to 1
    let speedVal = mouse.y * 2.0 + 0.5;   // 0.5 to 2.5

    let bass = plasmaBuffer[0].x;

    // Params
    let density = u.zoom_params.x * 20.0 + 5.0;
    let chromaticStr = u.zoom_params.y * 0.05 * (1.0 + bass * 0.4);
    let trailLen = u.zoom_params.z * 0.5 + 0.1;

    // Rotate UV for rain direction
    let angle = angleVal * mix(0.0, 1.5, u.zoom_params.w); // rads roughly
    let c = cos(angle);
    let s = sin(angle);
    let rotMat = mat2x2<f32>(c, -s, s, c);

    let rotUV = rotMat * (uv * vec2<f32>(aspect, 1.0));

    // Rain generation
    // We create grid cells
    let gridUV = rotUV * density;
    let gridID = floor(gridUV);
    let gridOffset = fract(gridUV);

    // Random speed per column
    let colSpeed = hash12(vec2<f32>(gridID.x, 0.0)) * 0.5 + 0.5;

    // Vertical movement
    let yPos = rotUV.y + time * speedVal * colSpeed;

    // Rain drop streaks
    // We use noise to determine if a drop is passing
    let dropNoise = fract(yPos * density * 0.1 + hash12(vec2<f32>(gridID.x, 10.0)) * 100.0);

    // Shape the drop: 1.0 at head, fading tail
    // Threshold it
    let drop = smoothstep(1.0 - trailLen, 1.0, dropNoise);

    // Apply displacement
    let displace = vec2<f32>(s, c) * drop * chromaticStr;

    let samplePos = clamp(uv + displace, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleNeg = clamp(uv - displace, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleNeg, 0.0).b;

    // Brighten where rain is
    let bright = drop * 0.1;

    // Luminance-based alpha with effect-intensity weighting
    let baseLum = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(drop * 0.6 + bright * 2.0 + length(displace) * 8.0 + baseLum * 0.15 + 0.1, 0.1, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(r + bright, g + bright, b + bright, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
