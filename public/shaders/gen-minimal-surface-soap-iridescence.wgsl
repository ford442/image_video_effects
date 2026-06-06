// ═══════════════════════════════════════════════════════════════════
//  Minimal Surface Soap Iridescence
//  Category: generative
//  Features: audio-reactive, mouse-driven, temporal, chromatic-film,
//            temporal-surface-memory, audio-caustics, depth-output
//  Complexity: High
//  Created: 2026-05-30
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}


const PI: f32 = 3.14159265;

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(vec3<f32>(h, h, h) + k) * 6.0 - vec3<f32>(3.0, 3.0, 3.0));
  return v * mix(vec3<f32>(k.x, k.x, k.x), clamp(p - vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 1.0)), s);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;

  let st = (uv - 0.5) * 4.0;
  let uParam = st.x;
  let vParam = st.y;

  let bonnet = time * 0.15 * (1.0 + bass) + p1 * PI;
  let cb = cos(bonnet);
  let sb = sin(bonnet);

  let coshv = cosh(vParam);
  let catX = coshv * cos(uParam);
  let catY = coshv * sin(uParam);
  let catZ = vParam;

  let helX = sinh(vParam) * cos(uParam);
  let helY = sinh(vParam) * sin(uParam);
  let helZ = uParam;

  let bubble = treble * sin(uParam * 3.0 + vParam * 5.0 + time * 2.0) * 0.3;
  var sx = catX * cb + helX * sb + bubble;
  var surfY = catY * cb + helY * sb;
  var sz = catZ * cb + helZ * sb;

  if (u.zoom_config.w > 0.5) {
    let dimple = length(uv - mouse);
    let dimpleStrength = exp(-dimple * dimple * 20.0) * 0.5;
    sz -= dimpleStrength;
  }

  let rotY = time * 0.1 + p2 * PI;
  let cy = cos(rotY);
  let sy = sin(rotY);
  let rx = sx * cy + sz * sy;
  let rz = -sx * sy + sz * cy;

  let depth = 1.0 / (3.0 + rz);
  let proj = vec2<f32>(rx, surfY) * depth;
  let screenPos = proj * 0.4 + 0.5;

  let ddx = cosh(vParam + 0.01) * cos(uParam) - catX;
  let ddy = coshv * cos(uParam + 0.01) - catX;
  let curvature = abs(ddx * ddy) * 4.0;
  let filmThick = 0.3 + mids * 0.5 + curvature * 0.4;

  // Chromatic film thickness: R/G/B see different optical paths
  let opticalPathR = (filmThick + 0.02 * bass) * 12.0 + rz * 0.2;
  let opticalPathG = filmThick * 12.0 + rz * 0.2;
  let opticalPathB = (filmThick - 0.02 * treble) * 12.0 + rz * 0.2;
  let hueR = fract(opticalPathR * 0.15);
  let hueG = fract(opticalPathG * 0.15);
  let hueB = fract(opticalPathB * 0.15);
  var color = vec3<f32>(hsv2rgb(hueR, 0.6 + mids * 0.3, 0.9).r,
                         hsv2rgb(hueG, 0.6 + mids * 0.3, 0.9).g,
                         hsv2rgb(hueB, 0.6 + mids * 0.3, 0.9).b);

  // Temporal surface memory: previous frame morphs blend in
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let morphTrail = mix(color, prev * 0.9, 0.05 + bass * 0.02);
  color = mix(color, morphTrail, 0.5);

  let caustic = pow(curvature, 2.0) * 2.0;
  color += vec3<f32>(0.4, 0.5, 0.6) * caustic * (0.5 + treble);

  let grad = length(vec2<f32>(ddx, ddy));
  color += vec3<f32>(0.2, 0.15, 0.3) * grad * filmThick;

  color = color * (2.51 * color + 0.03) / (color * (2.43 * color + 0.59) + 0.14);

  let alpha = clamp(filmThick * curvature * depth * 2.5, 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, applyGenerativePrimaryControls(vec4<f32>(color, alpha)));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
