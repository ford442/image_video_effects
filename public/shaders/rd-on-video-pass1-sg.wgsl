// ═══════════════════════════════════════════════════════════════════
//  rd-on-video-pass1-sg
//  Category: simulation
//  Features: multi-pass-1, temporal, video-driven, subgroups
// ═══════════════════════════════════════════════════════════════════

enable subgroups;

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

// Short bootstrap window for cold-start seeding; zero-state check below
// also re-seeds when this pass is loaded after startup.
const RESET_TIME: f32 = 0.1;

var<workgroup> tileA: array<f32, 256>;
var<workgroup> tileB: array<f32, 256>;

fn loadState(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(dataTextureC, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(
  @builtin(global_invocation_id) gid: vec3<u32>,
  @builtin(local_invocation_id) lid: vec3<u32>,
  @builtin(local_invocation_index) lidx: u32,
) {
  let res = u.config.zw;
  let inBounds = gid.x < u32(res.x) && gid.y < u32(res.y);
  let safeCoord = vec2<u32>(min(gid.x, u32(res.x) - 1u), min(gid.y, u32(res.y) - 1u));
  let uv = (vec2<f32>(safeCoord) + 0.5) / res;
  let px = 1.0 / res;
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

  var state = textureLoad(dataTextureC, vec2<i32>(safeCoord), 0);
  var a = state.r;
  var b = state.g;
  if (u.config.x < RESET_TIME || (a < 0.001 && b < 0.001)) {
    let seed = smoothstep(0.2, 0.85, luma);
    a = 1.0 - seed * 0.35;
    b = seed * 0.65;
  }

  tileA[lidx] = a;
  tileB[lidx] = b;
  workgroupBarrier();

  let leftA = subgroupShuffleUp(a, 1u);
  let rightA = subgroupShuffleDown(a, 1u);
  let leftB = subgroupShuffleUp(b, 1u);
  let rightB = subgroupShuffleDown(b, 1u);

  let upIdx = select(lidx, lidx - 16u, lid.y > 0u);
  let dnIdx = select(lidx, lidx + 16u, lid.y < 15u);

  var lA = leftA;
  var rA = rightA;
  var lB = leftB;
  var rB = rightB;

  if (lid.x == 0u) {
    let s = loadState(uv - vec2<f32>(px.x, 0.0));
    lA = s.r;
    lB = s.g;
  }
  if (lid.x == 15u) {
    let s = loadState(uv + vec2<f32>(px.x, 0.0));
    rA = s.r;
    rB = s.g;
  }

  var dA = tileA[upIdx];
  var uA = tileA[dnIdx];
  var dB = tileB[upIdx];
  var uB = tileB[dnIdx];

  if (lid.y == 0u) {
    let s = loadState(uv - vec2<f32>(0.0, px.y));
    dA = s.r;
    dB = s.g;
  }
  if (lid.y == 15u) {
    let s = loadState(uv + vec2<f32>(0.0, px.y));
    uA = s.r;
    uB = s.g;
  }

  let lapA = lA + rA + dA + uA - 4.0 * a;
  let lapB = lB + rB + dB + uB - 4.0 * b;

  let feedBase = mix(0.015, 0.070, clamp(u.zoom_params.x, 0.0, 1.0));
  let killBase = mix(0.030, 0.080, clamp(u.zoom_params.y, 0.0, 1.0));
  let diffusionScale = mix(0.75, 1.40, clamp(u.zoom_params.z, 0.0, 1.0));
  let dt = mix(0.60, 1.20, clamp(u.zoom_params.w, 0.0, 1.0));

  let drive = smoothstep(0.10, 0.90, luma);
  let feed = feedBase + drive * 0.020;
  let kill = killBase - drive * 0.012;

  a = clamp(a + ((1.00 * diffusionScale) * lapA - a * b * b + feed * (1.0 - a)) * dt, 0.0, 1.0);
  b = clamp(b + ((0.45 * diffusionScale) * lapB + a * b * b - (kill + feed) * b) * dt, 0.0, 1.0);

  if (inBounds) {
    let coord = vec2<i32>(gid.xy);
    textureStore(dataTextureA, coord, vec4<f32>(a, b, luma, 1.0));
    textureStore(writeTexture, coord, src);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  }
}
