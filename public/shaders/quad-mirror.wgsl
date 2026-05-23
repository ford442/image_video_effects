// ═══════════════════════════════════════════════════════════════════
//  Quad Mirror — Batch D Upgrade
//  Category: geometric
//  Features: mouse-driven, geometry, upgraded-rgba, fbm-domain-warp,
//            audio-reactive, seam-warp
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

const TAU: f32 = 6.28318530718;
const MIN_ZOOM: f32 = 0.1;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * vec2<f32>(0.1031, 0.1030);
  let a = dot(pp, vec2<f32>(127.1, 311.7));
  let b = dot(pp + 1.0, vec2<f32>(269.5, 183.3));
  let c = sin(vec2<f32>(a, b));
  return fract(c * 43758.5453 + pp);
}

fn fbm2(p: vec2<f32>, t: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let h = hash22(pp + t * 0.1 * f32(i + 1));
    v += a * (h.x - 0.5);
    pp = pp * 2.3 + h.yx;
    a *= 0.5;
  }
  return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  let px = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let hOffset = (u.zoom_params.x - 0.5) * 0.4;
  let vOffset = (u.zoom_params.y - 0.5) * 0.4;
  let seamWarpAmt = u.zoom_params.z * 0.05;
  // Bass boosts rotation speed for beat-locked spin
  let rotation = u.zoom_params.w * TAU + time * 0.1 * (1.0 + bass * 0.3);

  // Treble → seam warp shimmer
  let warpShimmer = seamWarpAmt * (1.0 + treble * 0.5);

  // Mirror transform with animated rotation
  let rel = uv - mouse;
  let c = cos(rotation);
  let s = sin(rotation);
  let rx = rel.x * c - rel.y * s;
  let ry = rel.x * s + rel.y * c;

  let zoom = max(MIN_ZOOM, 0.5);
  var sampleUV = mouse - vec2<f32>(abs(rx + hOffset), abs(ry + vOffset)) / zoom;

  // FBM domain warp at seam boundaries (±5% around mirror lines)
  let seamH = abs(rx);
  let seamV = abs(ry);
  let nearSeamH = smoothstep(0.0, 0.05 * zoom, seamH);
  let nearSeamV = smoothstep(0.0, 0.05 * zoom, seamV);
  let nearSeam = max(1.0 - nearSeamH, 1.0 - nearSeamV);

  let warpX = fbm2(sampleUV * 20.0 + time, time * 0.5) * warpShimmer * nearSeam;
  let warpY = fbm2(sampleUV * 20.0 + vec2<f32>(5.2, 1.3), time * 0.5) * warpShimmer * nearSeam;
  sampleUV = sampleUV + vec2<f32>(warpX, warpY);

  var color = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Alpha: preserves src.a, reduces at seams proportional to warp amount
  let seamAlphaReduction = warpShimmer * nearSeam * 2.0;
  color.a = max(0.3, color.a - seamAlphaReduction);

  // Mids → saturation boost for audio-reactive colour pop
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let satBoost = 1.0 + mids * 0.4;
  color = vec4<f32>(mix(vec3<f32>(luma), color.rgb, satBoost), color.a);

  textureStore(writeTexture, px, color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, px, color);
}
