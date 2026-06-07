// ═══════════════════════════════════════════════════════════════════
//  Spiral Lens v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: spiral-lens
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
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

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, 0.0, 1.0);

  let spiralTightness = u.zoom_params.x * 4.0 + 1.0;
  let lensStrength = (u.zoom_params.y * 3.0 + 0.1) * (1.0 + bass * 0.5);
  let chromatic = u.zoom_params.z * 0.055 * (1.0 + mids * 1.0);
  let rotationSpeed = u.zoom_params.w * 2.5 * (1.0 + treble * 0.6);

  let aspect = resolution.x / resolution.y;
  let dvec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dvec);
  let angle = atan2(dvec.y, dvec.x);

  let logSpiral = spiralTightness * log(max(dist, 0.0001)) + time * rotationSpeed;
  let archSpiral = spiralTightness * angle + time * rotationSpeed;
  let spiralBlend = smoothstep(0.0, 0.5, bass);
  let spiralAngle = mix(archSpiral, logSpiral, spiralBlend);
  let spiralDist = spiralTightness * spiralAngle;

  let spiralUV = mouse + vec2<f32>(cos(spiralAngle) * spiralDist / aspect, sin(spiralAngle) * spiralDist) * 0.1;

  let barrel = dist * dist * lensStrength * 0.4;
  let pincushion = -dist * lensStrength * 0.15;
  let lensWarp = mix(barrel, pincushion, smoothstep(0.0, 1.0, u.zoom_params.y));
  let lensMask = smoothstep(0.5, 0.0, dist);
  let lensFactor = mix(1.0, 1.0 / max(lensStrength * 0.5 + 0.1, 0.1), lensMask);
  let lensedUV = mouse + (uv - mouse) * lensFactor + normalize(dvec + vec2<f32>(0.0001)) * lensWarp * lensMask / vec2<f32>(aspect, 1.0);

  let sampleUV = mix(lensedUV, spiralUV, lensMask * 0.25);

  let dir = select(vec2<f32>(0.0), dvec / max(dist, 0.0001), dist > 0.0001);
  let dirUV = dir / vec2<f32>(aspect, 1.0);
  let caScale = chromatic * (1.0 + dist * 2.5);

  let rUV = clamp(sampleUV + dirUV * caScale, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(sampleUV + dirUV * caScale * 0.3 * dist, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(sampleUV - dirUV * caScale * (1.0 + dist * 0.8), vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var col = vec3<f32>(r, g, b);

  let rainbowEdge = smoothstep(0.35, 0.05, abs(fract(dist * 6.0 - time * 0.3) - 0.5)) * lensMask;
  let rainbow = vec3<f32>(1.0 - dist, 0.5 + sin(dist * 12.0) * 0.5, dist) * rainbowEdge * mids;

  let caustic = hash21(vec2<f32>(floor(dist * 30.0), floor(angle * 8.0 + time * 2.0))) * lensMask * bass;
  let causticLight = vec3<f32>(0.9, 0.95, 1.0) * caustic * 0.35;

  let bloomCenter = exp(-dist * dist * 8.0) * lensStrength * 0.25;
  let bloom = vec3<f32>(1.0, 0.92, 0.78) * bloomCenter * (0.5 + treble * 0.5);

  let focalLength = mix(0.02, 0.15, depth);
  let dof = smoothstep(focalLength, focalLength * 3.0, abs(dist - lensMask * 0.25));
  col = mix(col, col * 0.75, dof);

  let armPhase = spiralAngle * 0.5;
  let armGlow = smoothstep(0.08, 0.0, abs(fract(armPhase) - 0.5)) * lensMask * mids * 0.3;
  let armDetail = sin(armPhase * 6.28318 + dist * 20.0) * 0.5 + 0.5;
  let armColor = vec3<f32>(0.7 + armDetail * 0.2, 0.9, 1.0 - armDetail * 0.15) * armGlow;

  let finalColor = aces_tone_map(col + rainbow + causticLight + bloom + armColor);

  let edgeIntensity = rainbowEdge + caustic + armGlow;
  let alpha = clamp(lensStrength * edgeIntensity * depth + lensMask * 0.12 + bloomCenter * 0.1, 0.08, 1.0);
  let outDepth = clamp(depth + lensMask * 0.04 - dof * 0.06, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(lensStrength, edgeIntensity, lensMask, alpha));
}
