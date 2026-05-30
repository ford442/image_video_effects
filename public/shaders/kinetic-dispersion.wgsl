// ═══════════════════════════════════════════════════════════════════
//  Kinetic Dispersion
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, curl-dispersion, shockwave, block-scatter, upgraded-rgba
//  Complexity: High
//  Chunks From: kinetic-dispersion, curl2D, hash12, bass_env
//  Created: 2026-05-10
//  Upgraded: 2026-05-31
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = hash12(p + vec2<f32>(eps, 0.0) + t * 0.1);
  let n2 = hash12(p - vec2<f32>(eps, 0.0) + t * 0.1);
  let n3 = hash12(p + vec2<f32>(0.0, eps) + t * 0.1);
  let n4 = hash12(p - vec2<f32>(0.0, eps) + t * 0.1);
  let dy = (n1 - n2) / (2.0 * eps);
  let dx = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dx, -dy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let sensitivity = u.zoom_params.x * 50.0 * bass_env(bass, mids);
    let scatter = u.zoom_params.y * 0.1;
    let aberration = u.zoom_params.z * 0.05 * (1.0 + treble * 0.5);
    let granularity = max(1.0, u.zoom_params.w * 50.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthScatter = mix(1.3, 0.7, depth);

    let mouseDist = distance(uv, mouse);
    let velocity = (1.0 - smoothstep(0.0, 0.3, mouseDist)) * bass_env(bass, mids);
    let intensity = clamp(velocity * sensitivity, 0.0, 1.0);

    let blockUV = floor(uv * u.config.zw / granularity) * granularity / u.config.zw;
    let safeTime = max(time, 0.001);
    let rnd = hash12(blockUV + vec2<f32>(safeTime * 10.0, safeTime * 20.0));

    let curl = curl2D(blockUV * 3.0, time * 0.2) * intensity * 0.02;
    let displacement = (rnd - 0.5) * intensity * scatter * depthScatter + curl.x;
    let rgbSplit = intensity * aberration * depthScatter;

    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement - rgbSplit, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement + rgbSplit, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var color = vec3<f32>(r, g, b);
    let noise = hash12(uv * safeTime);
    color = mix(color, vec3<f32>(noise), intensity * 0.2);

    // Audio shockwave on bass hits
    let shock = sin(mouseDist * 30.0 - time * 10.0) * exp(-mouseDist * 2.0) * bass * 0.5;
    color = color + vec3<f32>(shock * 0.3, shock * 0.5, shock * 0.7);

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.5 + intensity * 0.35 + luma * 0.15 + bass * 0.1, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, coords, finalRGBA);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
