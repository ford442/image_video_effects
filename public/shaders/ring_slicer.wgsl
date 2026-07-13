// ═══════════════════════════════════════════════════════════════════
//  Ring Slicer
//  Category: distortion
//  Features: polar-warp, mouse-driven, ring-rotation, upgraded-rgba
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  var mousePos = u.zoom_config.yz;
  let time = u.config.x;

  // Params (normalized before use)
  let density = mix(2.0, 22.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let speed = (clamp(u.zoom_params.y, 0.0, 1.0) - 0.5) * 4.0;
  let chaos = clamp(u.zoom_params.z, 0.0, 1.0);
  let mouseInfluence = clamp(u.zoom_params.w, 0.0, 1.0);

  var center = vec2<f32>(0.5, 0.5);
  let aspect = resolution.x / max(resolution.y, 0.001);

  if (mouseInfluence > 0.1 && mousePos.x >= 0.0) {
      center = mix(center, mousePos, mouseInfluence);
  }

  var dVec = uv - center;
  dVec.x *= aspect;

  let r = length(dVec);
  let a = atan2(dVec.y, dVec.x);

  let ringIndex = floor(r * density);

  let direction = select(-1.0, 1.0, (ringIndex % 2.0) == 0.0);

  let randFactor = hash12(vec2<f32>(ringIndex, 1.0));
  let chaosSpeed = mix(1.0, 0.5 + randFactor * 2.0, chaos);

  let angleOffset = time * speed * direction * chaosSpeed;

  let newAngle = a + angleOffset;

  let newX = r * cos(newAngle);
  let newY = r * sin(newAngle);

  let warpedUV = vec2<f32>(newX / aspect, newY) + center;

  let finalUV = fract(warpedUV);

  var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  let ringPos = fract(r * density);
  let edgeWidth = 0.05 * chaos;
  if (edgeWidth > 0.0 && (ringPos < edgeWidth || ringPos > 1.0 - edgeWidth)) {
     color += vec4<f32>(0.1, 0.2, 0.3, 0.0) * chaos * 5.0;
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), color);

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
