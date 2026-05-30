// ================================================================
//  Encaustic Wax
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, painterly
//  Complexity: Medium
//  Chunks From: encaustic-wax
//  Created: 2026-05-31
//  By: Copilot
// ================================================================

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
  zoom_params: vec4<f32>,  // x=BrushScale, y=MeltIntensity, z=PigmentDeposit, w=Relief
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let brushScale = mix(2.0, 16.0, u.zoom_params.x);
  let meltIntensity = mix(0.0, 0.09, u.zoom_params.y) * (1.0 + audio.x * 0.5);
  let pigmentDeposit = mix(0.1, 0.85, u.zoom_params.z);
  let relief = mix(0.04, 0.45, u.zoom_params.w);

  let flow = vec2<f32>(
    noise(uv * brushScale + vec2<f32>(time * 0.2, -time * 0.15)) - 0.5,
    noise(uv * brushScale * 1.3 + vec2<f32>(-time * 0.1, time * 0.25)) - 0.5
  );
  let mousePull = (mouse - uv) * vec2<f32>(aspect, 1.0);
  let pullMask = 1.0 - smoothstep(0.0, 0.55, length(mousePull));
  let displacedUV = clamp(uv + (flow + mousePull * pullMask) * meltIntensity / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let base = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  let waxNoise = noise(displacedUV * brushScale * 2.0 + vec2<f32>(0.0, time * 0.2));
  let ridge = smoothstep(0.45, 0.8, waxNoise) * relief;
  let waxTint = mix(vec3<f32>(0.95, 0.78, 0.42), vec3<f32>(1.0, 0.45, 0.25), waxNoise * 0.5 + audio.y * 0.2);
  let spec = ridge * ridge * (0.18 + audio.z * 0.4);

  var finalColor = base.rgb;
  finalColor = mix(finalColor, finalColor * 0.7 + waxTint * 0.55, pigmentDeposit * (0.25 + ridge));
  finalColor = finalColor + vec3<f32>(1.0, 0.96, 0.88) * spec;

  let finalAlpha = clamp(base.a + ridge * 0.22 + pullMask * 0.08, 0.08, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.22 + ridge * 0.72, 0.20), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(ridge, pigmentDeposit, pullMask, finalAlpha));
}
