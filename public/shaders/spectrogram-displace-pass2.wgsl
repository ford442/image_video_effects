// ═════════════════════════════════════════════════════════════════════════════
//  Spectrogram Displace – Pass 2: Displacement & Compositing
//  Category: image
//  Features: multi-pass-2, image displacement, color grading, vignette
//  Inputs: dataTextureC (spectrogram field from Pass 1), readTexture
//  Outputs: writeTexture (final RGBA), writeDepthTexture
// ═════════════════════════════════════════════════════════════════════════════

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  if (coord.x >= dim.x || coord.y >= dim.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let field = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let spectroColor = field.rgb;
  let magnitude = field.a;

  let effectiveMag = select(u.zoom_params.z, 1.0, u.zoom_params.z < 0.01);

  let src = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  let freqFactor = 1.0 - uv.y;
  let displacementX = magnitude * (src.r - src.b) * 50.0 * effectiveMag;
  let displacementY = magnitude * (src.g - 0.5) * 30.0 * effectiveMag * freqFactor;
  let waveDisp = sin(uv.y * 20.0 + u.config.x * 3.0) * magnitude * 10.0;

  var displacedX = i32(coord.x) + i32(displacementX + waveDisp);
  var displacedY = i32(coord.y) + i32(displacementY);
  displacedX = (displacedX + i32(dim.x)) % i32(dim.x);
  displacedY = (displacedY + i32(dim.y)) % i32(dim.y);

  let displacedColor = textureLoad(readTexture, vec2<i32>(displacedX, displacedY), 0);

  let blendFactor = magnitude * 0.3;
  var finalColor = displacedColor.rgb;
  finalColor = finalColor + spectroColor * magnitude * 0.5 * effectiveMag;

  let lowFreqBoost = select(1.0 + magnitude * 0.2, 1.0, uv.y > 0.7);
  let highFreqBoost = select(1.0 + magnitude * 0.1, 1.0, uv.y < 0.3);
  finalColor = finalColor * vec3<f32>(lowFreqBoost, 1.0, highFreqBoost);

  let vignette = 1.0 - magnitude * 0.3;
  finalColor = finalColor * vignette;
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(finalColor, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
