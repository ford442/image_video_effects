// Fabric of Reality — one Jacobi constraint relaxation iteration
// Reads dataTextureC (positions), writes dataTextureA

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

const REST_LENGTH: f32 = 1.0;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let stiffness = mix(0.1, 0.99, u.zoom_params.x);
  let tearThreshold = mix(1.5, 4.0, u.zoom_params.y);

  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var pos = state.xy;
  let prevPos = state.zw;

  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let restLen = texelSize.x * REST_LENGTH;

  let leftUV = uv + vec2<f32>(-texelSize.x, 0.0);
  let rightUV = uv + vec2<f32>(texelSize.x, 0.0);
  let upUV = uv + vec2<f32>(0.0, -texelSize.y);
  let downUV = uv + vec2<f32>(0.0, texelSize.y);

  var leftPos = textureSampleLevel(dataTextureC, non_filtering_sampler, leftUV, 0.0).xy;
  var rightPos = textureSampleLevel(dataTextureC, non_filtering_sampler, rightUV, 0.0).xy;
  var upPos = textureSampleLevel(dataTextureC, non_filtering_sampler, upUV, 0.0).xy;
  var downPos = textureSampleLevel(dataTextureC, non_filtering_sampler, downUV, 0.0).xy;

  if (length(leftPos) < 0.001) { leftPos = leftUV; }
  if (length(rightPos) < 0.001) { rightPos = rightUV; }
  if (length(upPos) < 0.001) { upPos = upUV; }
  if (length(downPos) < 0.001) { downPos = downUV; }

  if (coord.x > 0u) {
    let delta = pos - leftPos;
    let dist = length(delta);
    if (dist > restLen && dist < tearThreshold * restLen) {
      let correction = (dist - restLen) / dist * 0.5 * stiffness;
      pos = pos - delta * correction;
    }
  }
  if (coord.x < size.x - 1u) {
    let delta = pos - rightPos;
    let dist = length(delta);
    if (dist > restLen && dist < tearThreshold * restLen) {
      let correction = (dist - restLen) / dist * 0.5 * stiffness;
      pos = pos - delta * correction;
    }
  }
  if (coord.y > 0u) {
    let delta = pos - upPos;
    let dist = length(delta);
    if (dist > restLen && dist < tearThreshold * restLen) {
      let correction = (dist - restLen) / dist * 0.5 * stiffness;
      pos = pos - delta * correction;
    }
  }
  if (coord.y < size.y - 1u) {
    let delta = pos - downPos;
    let dist = length(delta);
    if (dist > restLen && dist < tearThreshold * restLen) {
      let correction = (dist - restLen) / dist * 0.5 * stiffness;
      pos = pos - delta * correction;
    }
  }

  if (coord.y == 0u) {
    pos = uv;
  }

  pos = clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0));
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(pos, prevPos));
}
