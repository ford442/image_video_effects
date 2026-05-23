// ═══════════════════════════════════════════════════════════════════
//  slime-mold-on-video-sg
//  Category: simulation
//  Features: temporal, video-driven, trail-feedback, subgroups
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

const WG_SIZE: u32 = 16u;

var<workgroup> tileTrail: array<f32, 256>;
var<workgroup> tileFood: array<f32, 256>;

fn lumaAt(uv: vec2<f32>) -> f32 {
  return dot(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn trailAt(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(dataTextureC, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
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
  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let centerTrail = textureLoad(dataTextureC, vec2<i32>(safeCoord), 0).r;
  let centerFood = lumaAt(uv);

  tileTrail[lidx] = centerTrail;
  tileFood[lidx] = centerFood;
  workgroupBarrier();

  let upIdx = select(lidx, lidx - WG_SIZE, lid.y > 0u);
  let dnIdx = select(lidx, lidx + WG_SIZE, lid.y < WG_SIZE - 1u);

  var trailL = subgroupShuffleUp(centerTrail, 1u);
  var trailR = subgroupShuffleDown(centerTrail, 1u);
  var foodL = subgroupShuffleUp(centerFood, 1u);
  var foodR = subgroupShuffleDown(centerFood, 1u);

  if (lid.x == 0u) {
    trailL = trailAt(uv - vec2<f32>(px.x, 0.0));
    foodL = lumaAt(uv - vec2<f32>(px.x, 0.0));
  }
  if (lid.x == WG_SIZE - 1u) {
    trailR = trailAt(uv + vec2<f32>(px.x, 0.0));
    foodR = lumaAt(uv + vec2<f32>(px.x, 0.0));
  }

  var trailD = tileTrail[upIdx];
  var trailU = tileTrail[dnIdx];
  var foodD = tileFood[upIdx];
  var foodU = tileFood[dnIdx];

  if (lid.y == 0u) {
    trailD = trailAt(uv - vec2<f32>(0.0, px.y));
    foodD = lumaAt(uv - vec2<f32>(0.0, px.y));
  }
  if (lid.y == WG_SIZE - 1u) {
    trailU = trailAt(uv + vec2<f32>(0.0, px.y));
    foodU = lumaAt(uv + vec2<f32>(0.0, px.y));
  }

  let trailDL = trailAt(uv + vec2<f32>(-px.x, -px.y));
  let trailDR = trailAt(uv + vec2<f32>(px.x, -px.y));
  let trailUL = trailAt(uv + vec2<f32>(-px.x, px.y));
  let trailUR = trailAt(uv + vec2<f32>(px.x, px.y));
  let blur = (centerTrail + trailL + trailR + trailD + trailU + trailDL + trailDR + trailUL + trailUR) / 9.0;
  let gradFood = vec2<f32>(foodR - foodL, foodU - foodD);
  let gradTrail = vec2<f32>(trailR - trailL, trailU - trailD);

  let jitter = vec2<f32>(
    sin(u.config.x * 0.9 + uv.y * 33.0),
    cos(u.config.x * 1.1 + uv.x * 29.0)
  ) * 0.015;

  let drift = normalize(gradFood * 2.3 + gradTrail * 1.2 + jitter + vec2<f32>(1e-4));
  let aheadUV = clamp(uv + drift * px * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
  let aheadTrail = trailAt(aheadUV);

  let follow = mix(0.05, 0.80, clamp(u.zoom_params.x, 0.0, 1.0));
  let decay = mix(0.88, 0.995, clamp(u.zoom_params.y, 0.0, 1.0));
  let foodGain = mix(0.01, 0.20, clamp(u.zoom_params.z, 0.0, 1.0));
  let glowGain = mix(0.25, 1.50, clamp(u.zoom_params.w, 0.0, 1.0));

  var deposit = max(centerFood - 0.25, 0.0) * foodGain;
  let mouseBoost = smoothstep(0.10, 0.0, length(uv - u.zoom_config.yz)) * u.zoom_config.w;
  deposit = deposit + mouseBoost * 0.12;

  let nextTrail = clamp(max(blur * decay, aheadTrail * follow) + deposit, 0.0, 1.0);

  if (inBounds) {
    let coord = vec2<i32>(gid.xy);
    textureStore(dataTextureA, coord, vec4<f32>(nextTrail, centerFood, drift.x * 0.5 + 0.5, drift.y * 0.5 + 0.5));

    let tendril = vec3<f32>(0.07, 0.95, 0.62) * nextTrail;
    let hot = vec3<f32>(1.0, 0.55, 0.20) * pow(nextTrail, 2.2) * glowGain;
    let finalColor = clamp(mix(base.rgb, base.rgb * 0.35 + tendril + hot, nextTrail), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  }
}
