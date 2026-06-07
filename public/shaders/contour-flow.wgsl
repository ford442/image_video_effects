// ═══════════════════════════════════════════════════════════════════
//  Contour Flow
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: contour-flow
//  Upgraded: 2026-05-30
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let flowSpeed = u.zoom_params.x * 4.0 * (1.0 + bass * 0.4);
    let flowLength = u.zoom_params.y * 0.06;
    let mouseRadius = u.zoom_params.z * 0.5 + 0.01;
    let edgeSensitivity = u.zoom_params.w * 4.0 + 1.0;

    let texel = vec2<f32>(1.0) / resolution;
    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb;
    let t  = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, -texel.y), 0.0).rgb;
    let l  = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
    let c  = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let r  = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, texel.y), 0.0).rgb;
    let b  = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, texel.y), 0.0).rgb;

    let grayTL = dot(tl, vec3<f32>(0.299, 0.587, 0.114));
    let grayT  = dot(t,  vec3<f32>(0.299, 0.587, 0.114));
    let grayTR = dot(tr, vec3<f32>(0.299, 0.587, 0.114));
    let grayL  = dot(l,  vec3<f32>(0.299, 0.587, 0.114));
    let grayR  = dot(r,  vec3<f32>(0.299, 0.587, 0.114));
    let grayBL = dot(bl, vec3<f32>(0.299, 0.587, 0.114));
    let grayB  = dot(b,  vec3<f32>(0.299, 0.587, 0.114));
    let grayBR = dot(br, vec3<f32>(0.299, 0.587, 0.114));

    let gx = -grayTL - 2.0 * grayT - grayTR + grayBL + 2.0 * grayB + grayBR;
    let gy = -grayTL - 2.0 * grayL - grayBL + grayTR + 2.0 * grayR + grayBR;

    let gradMag = length(vec2<f32>(gx, gy));
    let edgeStrength = smoothstep(0.05, 0.25, gradMag * edgeSensitivity);

    let flowDir = normalize(vec2<f32>(-gy, gx) + vec2<f32>(0.0001));

    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let mouseFactor = smoothstep(mouseRadius, 0.0, dist);
    let vortex = vec2<f32>(-distVec.y, distVec.x) / max(dist * dist + 0.001, 0.001);

    let turbulence = sin(uv.x * 8.0 + time * flowSpeed) * cos(uv.y * 6.0 - time * flowSpeed * 0.7);
    let viscosity = mix(0.3, 1.0, depth);

    let advectDir_base = flowDir * (gradMag * edgeSensitivity + 0.15) * flowLength * viscosity;
    var advectDir = advectDir_base + vortex * mouseFactor * 0.02;
    advectDir += vec2<f32>(turbulence * bass * 0.01, turbulence * bass * 0.008);

    let advectUV = clamp(uv - advectDir, vec2<f32>(0.0), vec2<f32>(1.0));
    let advected = textureSampleLevel(readTexture, u_sampler, advectUV, 0.0);

    let streakDir = normalize(advectDir + vec2<f32>(0.0001));
    let streakUV1 = clamp(advectUV + streakDir * texel * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
    let streakUV2 = clamp(advectUV - streakDir * texel * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
    let streak1 = textureSampleLevel(readTexture, u_sampler, streakUV1, 0.0).rgb;
    let streak2 = textureSampleLevel(readTexture, u_sampler, streakUV2, 0.0).rgb;
    let streaks = (streak1 + streak2) * 0.5 * edgeStrength * (1.0 + mids);

    let flowMag = length(advectDir) * 20.0;
    let velocityColor = mix(vec3<f32>(0.1, 0.3, 0.9), vec3<f32>(1.0, 0.2, 0.1), clamp(flowMag, 0.0, 1.0));

    var rgb = mix(advected.rgb, advected.rgb * velocityColor * 1.3, edgeStrength * 0.4);
    rgb += streaks * vec3<f32>(0.5, 0.7, 1.0) * treble;
    rgb += velocityColor * edgeStrength * flowMag * 0.15;

    rgb = aces_tonemap(rgb * (1.0 + bass * 0.1));

    let alpha = clamp(flowMag * edgeStrength + advected.a * 0.4 + mouseFactor * 0.15, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth + edgeStrength * 0.05, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(rgb, alpha));
}
