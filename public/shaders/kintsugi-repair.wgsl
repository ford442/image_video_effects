// ================================================================
//  Kintsugi Repair
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: kintsugi-repair
//  Created: 2026-05-30
//  By: Copilot
// ================================================================

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ShardSize, y=GoldWidth, z=ShatterAmount, w=GoldSparkle
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn voronoi(uv: vec2<f32>, scale: f32) -> vec4<f32> {
  let p = uv * scale;
  let i_st = floor(p);
  let f_st = fract(p);

  var minDist = 8.0;
  var idPoint = vec2<f32>(0.0);
  var cellCenter = vec2<f32>(0.0);

  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let point = hash22(i_st + neighbor);
      let anim = sin(u.config.x * 0.1 + 6.28318 * point) * 0.1;
      let diff = neighbor + point + anim - f_st;
      let dist = length(diff);
      if (dist < minDist) {
        minDist = dist;
        idPoint = point;
        cellCenter = diff;
      }
    }
  }

  var minEdgeDist = 8.0;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let point = hash22(i_st + neighbor);
      let anim = sin(u.config.x * 0.1 + 6.28318 * point) * 0.1;
      let diff = neighbor + point + anim - f_st;
      let toNeighbor = diff - cellCenter;
      if (dot(toNeighbor, toNeighbor) > 0.0001) {
        let edgeDist = dot(0.5 * (cellCenter + diff), normalize(toNeighbor));
        minEdgeDist = min(minEdgeDist, edgeDist);
      }
    }
  }

  return vec4<f32>(minDist, idPoint.x, idPoint.y, minEdgeDist);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let audio = plasmaBuffer[0].xyz;

  let scale = u.zoom_params.x * 20.0 + 3.0;
  let crackWidth = u.zoom_params.y * 0.10 + 0.001;
  let displacement = u.zoom_params.z * 0.06;
  let sparkleAmount = u.zoom_params.w;

  let uvCorr = vec2<f32>(uv.x * aspect, uv.y);
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let interaction = 1.0 - smoothstep(0.0, 0.45, mouseDist);
  let vor = voronoi(uvCorr, scale);
  let edgeDist = vor.w;
  let id = vor.yz;

  let crack = 1.0 - smoothstep(0.0, crackWidth * (1.0 + audio.z * 0.4), edgeDist);
  let halo = 1.0 - smoothstep(0.0, crackWidth * 4.0 + 0.01, edgeDist);
  let shift = (id - 0.5) * displacement * (0.70 + 0.60 * interaction + audio.x * 0.35);
  let uvDisplaced = clamp(uv + shift, vec2<f32>(0.0), vec2<f32>(1.0));

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uvDisplaced, 0.0).rgb;
  let sparklePhase = sin(dot(id, vec2<f32>(12.9898, 78.233)) * 6.28318 + u.config.x * (1.0 + 0.5 * audio.y));
  let sparkle = pow(abs(sparklePhase), mix(18.0, 6.0, clamp(sparkleAmount + audio.x * 0.35, 0.0, 1.0)));
  let goldBase = mix(vec3<f32>(0.82, 0.58, 0.16), vec3<f32>(1.0, 0.88, 0.35), halo);
  let lacquer = goldBase * (0.55 + 0.75 * crack + sparkle * (0.25 + 0.75 * sparkleAmount));
  let ceramicShade = mix(vec3<f32>(1.0), vec3<f32>(0.85, 0.80, 0.76), halo * 0.35);

  var finalColor = sourceColor * ceramicShade;
  finalColor = mix(finalColor, lacquer, crack);
  finalColor = finalColor + halo * (0.10 + 0.22 * audio.x + 0.12 * audio.z + 0.12 * interaction) * goldBase;

  let finalAlpha = clamp(0.88 + crack * 0.10 - displacement * halo * 0.40 + interaction * 0.04, 0.72, 1.0);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.30 + 0.70 * halo, crack * 0.35), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(crack, halo, sparkle, finalAlpha));
}
