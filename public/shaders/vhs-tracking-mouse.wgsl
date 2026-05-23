// ═══════════════════════════════════════════════════════════════════
//  VHS Tracking (Mouse)
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
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

fn rand(co: vec2<f32>) -> f32 {
    let seed = max(dot(co, vec2<f32>(12.9898, 78.233)), 0.001);
    return fract(sin(seed) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = vec2<f32>(u.zoom_config.y, select(0.5, u.zoom_config.z, u.zoom_config.z >= 0.0));

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let barHeight = u.zoom_params.x * 0.3 + 0.05;
    let strength = u.zoom_params.y * 0.1 * (1.0 + bass * 0.2 + mids * 0.1);
    let noiseAmt = u.zoom_params.z;
    let colorShift = u.zoom_params.w * 0.02;

    let distY = abs(uv.y - mousePos.y);
    let in_bar = distY < barHeight;
    let bar_intensity = smoothstep(barHeight, 0.0, distY) * f32(in_bar);

    let shift = sin(uv.y * 50.0 + time * 20.0) * strength * bar_intensity;
    let noiseShift = (rand(vec2<f32>(uv.y, time)) - 0.5) * strength * 2.0 * bar_intensity;
    let displacedUV = clamp(uv + vec2<f32>(shift + noiseShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleUV = select(uv, displacedUV, in_bar);

    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(colorShift, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(colorShift, 0.0), 0.0).b;
    var color = vec3<f32>(r, g, b);

    let n = rand(uv + vec2<f32>(time, time));
    let noiseValue = (n - 0.5) * noiseAmt * f32(in_bar);
    color = color + noiseValue;

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.5 + bar_intensity * 0.35 + luma * 0.15 + treble * 0.05, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, global_id.xy, finalRGBA);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
