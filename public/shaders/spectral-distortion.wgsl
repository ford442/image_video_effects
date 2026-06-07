// ═══════════════════════════════════════════════════════════════════
//  Spectral Distortion
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-persistence, glitch, audio-reactive, upgraded-rgba
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

fn noise(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn value_noise(st: vec2<f32>) -> f32 {
    let i = floor(st);
    let f = fract(st);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(noise(i + vec2<f32>(0.0, 0.0)),
                   noise(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(noise(i + vec2<f32>(0.0, 1.0)),
                   noise(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  var mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let separation = clamp(u.zoom_params.x * 0.1 * (1.0 + bass * 0.3), 0.0, 0.2);
  let warpScale = u.zoom_params.y * 20.0 + 1.0 + mids * 5.0;
  let mouseInf = u.zoom_params.z;
  let speed = u.zoom_params.w * 2.0;

  var warpStr = 0.02 + treble * 0.01;

  // Branchless mouse influence
  let mouseActive = step(0.0, mousePos.x);
  let aspect = resolution.x / max(resolution.y, 0.001);
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  let influenceRadius = 0.3;
  let influence = 1.0 - smoothstep(0.0, influenceRadius, dist);
  warpStr += influence * mouseInf * 0.1 * mouseActive;

  // Generate warp fields for R, G, B
  let t = time * speed;
  let nR = value_noise(uv * warpScale + vec2<f32>(t, t));
  let nG = value_noise(uv * warpScale + vec2<f32>(t + 10.0, -t));
  let nB = value_noise(uv * warpScale + vec2<f32>(-t, t + 5.0));

  let offR = vec2<f32>(nR - 0.5, value_noise(uv * warpScale + 100.0) - 0.5) * warpStr + vec2<f32>(separation, 0.0);
  let offG = vec2<f32>(nG - 0.5, value_noise(uv * warpScale + 200.0) - 0.5) * warpStr;
  let offB = vec2<f32>(nB - 0.5, value_noise(uv * warpScale + 300.0) - 0.5) * warpStr - vec2<f32>(separation, 0.0);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + offG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + offB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // Alpha: warp magnitude + chromatic separation drive spectral effect weight
  let warpMag = length(offR - offB);
  let luma = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(warpMag * 8.0 + separation * 6.0 + luma * 0.2, 0.0, 1.0);
  let finalColor = vec4<f32>(r, g, b, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
