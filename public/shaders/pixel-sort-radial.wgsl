// ═══════════════════════════════════════════════════════════════════
//  Radial Pixel Stretch
//  Category: image
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-05-17
//  By: Shader Upgrade Swarm
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p;
  let k1 = vec3<f32>(0.3183099, 0.3678794, 0.7071068);
  let k2 = vec2<f32>(0.27182818, 0.57721566);
  pp = fract(pp * k1.xy + dot(pp, k1.yz) + k2);
  return fract(pp * (k1.z + dot(pp, k2)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));

  let stretchAmt = u.zoom_params.x;
  let threshold = u.zoom_params.y;
  let radius = 0.1 + u.zoom_params.z * 0.8;
  let direction = u.zoom_params.w;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let clicked = select(1.0, 2.5, u.zoom_config.w > 0.5);

  let aspect = resolution.x / max(resolution.y, 1.0);
  let mousePos = u.zoom_config.yz;
  let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));

  let breathe = radius * (1.0 + sin(time * 1.5) * 0.15);
  let influence = smoothstep(breathe, 0.0, dist);

  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let audioStretch = stretchAmt * (1.0 + bass * clicked);
  let stretchFactor = step(threshold, luma) * audioStretch * influence;
  let dirToMouse = normalize(mousePos - uv + 0.0001);
  let jitter = hash22(uv * 1000.0 + time) * 0.08 - 0.04;
  let dir = mix(dirToMouse + jitter, -dirToMouse + jitter, step(0.5, direction));

  let twistAngle = influence * (0.2 + mids * 0.6);
  let cs = cos(twistAngle);
  let sn = sin(twistAngle);
  let tangent = vec2<f32>(-dir.y * cs - dir.x * sn, dir.x * cs - dir.y * sn);

  let isActive = select(0.0, 1.0, influence > 0.001);
  let finalUV = mix(uv, uv - dir * stretchFactor * 0.2 + tangent * isActive, isActive);

  let caStrength = stretchFactor * 0.015;
  let rUV = finalUV + dir * caStrength;
  let bUV = finalUV - dir * caStrength;
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  let stretched = vec3<f32>(r, g, b);
  let bloom = max(dot(stretched, vec3<f32>(0.299, 0.587, 0.114)) - 0.8, 0.0) * 2.0;
  let alpha = mix(color.a, clamp(color.a + stretchFactor * 0.3 + bloom, 0.0, 1.0), isActive);

  let finalColor = vec4<f32>(mix(color.rgb, stretched, isActive), alpha);
  textureStore(writeTexture, coord, finalColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalColor);
}
