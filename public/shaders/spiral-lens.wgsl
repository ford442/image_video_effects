// ═══════════════════════════════════════════════════════════════════
//  Spiral Lens — Batch D Upgrade
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal, depth-aware,
//            upgraded-rgba, archimedean-spiral, chromatic-dispersion
//  Created: 2026-05-10
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;

  // Parameters
  let spiralTightness = u.zoom_params.x * 4.0 + 1.0;
  let lensStrength = (u.zoom_params.y * 3.0 + 0.1) * (1.0 + bass * 0.4);
  let chromatic = u.zoom_params.z * 0.06;
  let rotationSpeed = u.zoom_params.w * 2.0;

  let asp = res.x / res.y;
  let dvec = (uv - mouse) * vec2<f32>(asp, 1.0);
  let dist = length(dvec);
  let angle = atan2(dvec.y, dvec.x);

  // Archimedean spiral UV unwrap
  let spiralAngle = angle + time * rotationSpeed;
  let spiralDist = spiralTightness * spiralAngle;
  let spiralUV = mouse + vec2<f32>(
    cos(spiralAngle) * spiralDist / asp,
    sin(spiralAngle) * spiralDist
  ) * 0.1;

  // Lens distortion toward spiral center
  let lensMask = smoothstep(0.5, 0.0, dist);
  let lensFactor = mix(1.0, 1.0 / max(lensStrength, 0.1), lensMask);
  let lensedUV = mouse + (uv - mouse) * lensFactor;

  let sampleUV = mix(lensedUV, spiralUV, lensMask * 0.3);

  // Chromatic dispersion along spiral radius
  let dir = select(vec2<f32>(0.0), dvec / max(dist, 0.0001), dist > 0.0001);
  let dirUV = dir / vec2<f32>(asp, 1.0);

  let rUV = sampleUV + dirUV * chromatic * (1.0 + dist * 2.0);
  let gUV = sampleUV + dirUV * chromatic * 0.3 * dist;
  let bUV = sampleUV - dirUV * chromatic * (1.0 + dist * 1.2);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var col = vec3<f32>(r, g, b);

  // Temporal feedback trail
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let fb = 0.12 * bass * lensMask;
  col = mix(col, prev * 0.96, fb);

  // Alpha: depth-layered — center of spiral more opaque
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = mix(0.5, 1.0, lensMask * (0.5 + depth * 0.5));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
