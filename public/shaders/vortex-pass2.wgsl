// ═══════════════════════════════════════════════════════════════
//  Fluid Vortex – Pass 2: Distortion Rendering
//  Category: distortion
//  Features: multi-pass-2, UV distortion, color grading, alpha compositing
//  Inputs: dataTextureC (velocity field from Pass 1), readTexture
//  Outputs: writeTexture (final RGBA), writeDepthTexture
// ═══════════════════════════════════════════════════════════════

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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let vortexStrength = u.zoom_params.x;

  let field = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let velocity = field.rg;
  let vorticity = field.b;
  let velMag = field.a;

  let displacementScale = mix(0.02, 0.15, vortexStrength);
  let displacedUV = uv + velocity * displacementScale;

  let swirlStrength = vorticity * 0.01 * vortexStrength;
  let toCenter = uv - vec2<f32>(0.5);
  let swirlRot = vec2<f32>(
    -toCenter.y * swirlStrength,
    toCenter.x * swirlStrength
  );
  let finalUV = displacedUV + swirlRot;

  var warpedColor = textureSampleLevel(readTexture, u_sampler, fract(finalUV), 0.0);

  let velocityGlow = smoothstep(0.0, 0.5, velMag) * 0.1 * vortexStrength;
  let vorticityColor = vec3<f32>(
    1.0 + sign(vorticity) * 0.1,
    1.0,
    1.0 - sign(vorticity) * 0.1
  );
  var finalRGB = warpedColor.rgb * mix(vec3<f32>(1.0), vorticityColor, velMag * 0.3);
  finalRGB = finalRGB * (1.0 + velocityGlow);

  let distortionMag = velMag + abs(vorticity) * 0.1;
  let scatteringLoss = distortionMag * 0.3 * vortexStrength;
  let vorticityAlpha = 1.0 - smoothstep(0.0, 0.5, abs(vorticity)) * 0.2;
  let finalAlpha = clamp(vorticityAlpha - scatteringLoss, 0.3, 1.0) * warpedColor.a;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, finalAlpha));

  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, fract(finalUV), 0.0);
  let depthModulation = 1.0 + velMag * 0.1 * vortexStrength;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthSample.r * depthModulation, 0.0, 0.0, 0.0));
}
