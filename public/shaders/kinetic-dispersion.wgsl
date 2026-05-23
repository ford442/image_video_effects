// ═══════════════════════════════════════════════════════════════════
//  Kinetic Dispersion
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let sensitivity = u.zoom_params.x * 50.0;
    let scatter = u.zoom_params.y * 0.1;
    let aberration = u.zoom_params.z * 0.05;
    let granularity = max(1.0, u.zoom_params.w * 50.0);

    let mouseDist = distance(uv, mouse);
    let velocity = (1.0 - smoothstep(0.0, 0.3, mouseDist)) * (1.0 + bass * 0.3 + mids * 0.15);
    let intensity = clamp(velocity * sensitivity, 0.0, 1.0);

    let blockUV = floor(uv * u.config.zw / granularity) * granularity / u.config.zw;
    let safeTime = max(time, 0.001);
    let rnd = hash12(blockUV + vec2<f32>(safeTime * 10.0, safeTime * 20.0));

    let displacement = (rnd - 0.5) * intensity * scatter;
    let rgbSplit = intensity * aberration;

    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement - rgbSplit, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement + rgbSplit, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var color = vec3<f32>(r, g, b);
    let noise = hash12(uv * safeTime);
    color = mix(color, vec3<f32>(noise), intensity * 0.2);

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.5 + intensity * 0.35 + luma * 0.15, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let finalRGBA = vec4<f32>(color, alpha);

    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, coords, finalRGBA);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
