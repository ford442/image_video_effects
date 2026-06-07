// ═══════════════════════════════════════════════════════════════════
//  atmos_volumetric_fog
//  Category: atmospheric
//  Features: upgraded-rgba, depth-aware, physical-transmittance, volumetric-fog,
//            audio-reactive, aces-tone-map, temporal-feedback, chromatic-aberration,
//            mouse-light, shockwave, video-luma, bass-envelope
//  Upgraded: 2026-06-07
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

fn physicalTransmittance(baseColor: vec3<f32>, opticalDepth: f32, absorptionCoeff: vec3<f32>) -> vec3<f32> {
  let transmittance = exp(-absorptionCoeff * opticalDepth);
  return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
  return 1.0 - exp(-density * thickness);
}

fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAlpha = mix(0.2, 1.0, depth);
  return mix(1.0, depthAlpha, depthWeight);
}

fn calculateFogAlpha(uv: vec2<f32>, opticalDepth: f32, density: f32, params: vec4<f32>) -> f32 {
  let volAlpha = volumetricAlpha(density, opticalDepth);
  let depthAlpha = depthLayeredAlpha(uv, params.z);
  return clamp(volAlpha * depthAlpha, 0.0, 1.0);
}

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    value += amplitude * noise(p * frequency);
    frequency *= 2.0;
    amplitude *= 0.5;
  }
  return value;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let rawBass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let bass = bass_env(prev.r, rawBass, 0.8, 0.15);

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let fogDensity = u.zoom_params.x * 3.0 * (1.0 + bass * 0.3);
  let fogHeight = u.zoom_params.y;
  let depthWeight = u.zoom_params.z;
  let fogColorShift = u.zoom_params.w + mids * 0.1;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Mouse light source for god rays
  let lightDir = mouse - uv;
  let lightDist = length(lightDir);
  let godRay = pow(max(dot(normalize(lightDir), vec2<f32>(0.0, -1.0)), 0.0), 4.0);
  let lightGlow = exp(-lightDist * lightDist * 6.0) * (0.5 + bass * 0.5);

  // Click shockwave clears fog
  let shockDist = length(uv - mouse);
  let shockClear = exp(-shockDist * shockDist * 20.0) * mouseDown;

  // Fog density with mids-driven evolution
  let fogUV = uv * 3.0 + vec2<f32>(time * 0.02 * (1.0 + mids * 0.3), 0.0);
  let noiseVal = fbm(fogUV, 4) * (1.0 + treble * 0.2);
  let heightFog = exp(-uv.y / max(fogHeight, 0.01));
  let density = max(0.0, fogDensity * heightFog * (0.5 + noiseVal * 0.5) - shockClear * 2.0);

  let fogColor = vec3<f32>(
    0.7 + fogColorShift * 0.2,
    0.75 + fogColorShift * 0.1,
    0.85
  );

  let bgSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Video luma-keyed emission
  let luma = dot(bgSample.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let vidEmission = smoothstep(0.6, 1.0, luma) * vec3<f32>(0.3, 0.25, 0.2);

  let opticalDepth = density * (1.0 + (1.0 - depth));

  let absorptionCoeff = vec3<f32>(0.3, 0.4, 0.5);
  let transmitted = physicalTransmittance(bgSample.rgb + vidEmission, opticalDepth, absorptionCoeff);

  // God ray scattering
  let scatter = fogColor * godRay * lightGlow * density * 0.5;

  let alpha = calculateFogAlpha(uv, opticalDepth, density, u.zoom_params);
  var finalColor = mix(transmitted, fogColor + scatter, alpha * 0.7);
  finalColor = mix(finalColor, prev.rgb * 0.95, 0.03 + bass * 0.01);

  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);

  finalColor = acesToneMap(finalColor * 1.1);

  // Alpha encodes fog density + interaction intensity
  let interaction = lightGlow * 0.3 + shockClear * 0.5;
  let finalAlpha = clamp(alpha + interaction, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(bass, density, interaction, finalAlpha));
}
