// ═══════════════════════════════════════════════════════════════════
//  Percolation Threshold
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware,
//            upgraded-rgba, aces-tone-map, chromatic-aberration
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
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
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let coord = vec2<i32>(gid.xy);
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let latticeW = 80;
  let latticeH = 60;
  let pCritical = 0.5927 + (bass - 0.5) * 0.1 + (u.zoom_params.x - 0.5) * 0.15;
  let p = clamp(pCritical, 0.35, 0.85);
  let latticeZoom = mix(0.6, 1.4, u.zoom_params.y);
  let bloomAmt = mix(0.8, 2.0, u.zoom_params.z);
  let grainAmt = mix(0.0, 0.15, u.zoom_params.w);

  if (gid.x < u32(latticeW) && gid.y < u32(latticeH)) {
    let flatIdx = f32(gid.y * u32(latticeW) + gid.x);
    let seed = hash12(vec2<f32>(flatIdx, floor(time * 0.2)));
    let occupied = seed < p;
    let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
    var label = -1.0;
    if (occupied) {
      label = flatIdx;
      let n = textureLoad(dataTextureC, clamp(vec2<i32>(gid.xy) + vec2<i32>(0, -1), vec2<i32>(0), vec2<i32>(latticeW - 1, latticeH - 1)), 0).r;
      let s = textureLoad(dataTextureC, clamp(vec2<i32>(gid.xy) + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(latticeW - 1, latticeH - 1)), 0).r;
      let e = textureLoad(dataTextureC, clamp(vec2<i32>(gid.xy) + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(latticeW - 1, latticeH - 1)), 0).r;
      let w = textureLoad(dataTextureC, clamp(vec2<i32>(gid.xy) + vec2<i32>(-1, 0), vec2<i32>(0), vec2<i32>(latticeW - 1, latticeH - 1)), 0).r;
      if (n >= 0.0) { label = min(label, n); }
      if (s >= 0.0) { label = min(label, s); }
      if (e >= 0.0) { label = min(label, e); }
      if (w >= 0.0) { label = min(label, w); }
      if (prev.r >= 0.0) { label = min(label, prev.r); }
    }
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(label, select(0.0, 1.0, occupied), 0.0, 0.0));
    if (gid.x == 0u) { extraBuffer[gid.y] = label; }
    if (gid.x == u32(latticeW - 1)) { extraBuffer[u32(latticeH) + gid.y] = label; }
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    if (mouseDown && length(uv - mouse) < 0.02) {
      textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(flatIdx, 1.0, 0.0, 0.0));
    }
  }

  let zoomedUV = (uv - 0.5) * latticeZoom + 0.5;
  let siteX = min(i32(zoomedUV.x * f32(latticeW)), latticeW - 1);
  let siteY = min(i32(zoomedUV.y * f32(latticeH)), latticeH - 1);
  let siteCoord = vec2<i32>(siteX, siteY);
  let state = textureLoad(dataTextureC, siteCoord, 0);
  let label = state.r;
  let occupied = state.g > 0.5;

  if (!occupied) {
    let bg = vec3<f32>(0.02, 0.02, 0.04) * (1.0 + depth * 0.3);
    textureStore(writeTexture, coord, vec4<f32>(bg, 0.2 + depth * 0.2));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * 0.1, 0.0, 0.0, 0.0));
    return;
  }

  let hue = fract(hash12(vec2<f32>(label, floor(label * 0.01))) + 0.15);
  let jewel = clamp(abs(vec3<f32>(abs(hue * 6.0 - 3.0) - 1.0, 2.0 - abs(hue * 6.0 - 2.0), 2.0 - abs(hue * 6.0 - 4.0))), vec3<f32>(0.0), vec3<f32>(1.0));
  let sat = mix(jewel, vec3<f32>(1.0), 0.3);

  let nOcc = textureLoad(dataTextureC, clamp(siteCoord + vec2<i32>(0, -1), vec2<i32>(0), vec2<i32>(latticeW - 1, latticeH - 1)), 0).g > 0.5;
  let sOcc = textureLoad(dataTextureC, clamp(siteCoord + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(latticeW - 1, latticeH - 1)), 0).g > 0.5;
  let eOcc = textureLoad(dataTextureC, clamp(siteCoord + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(latticeW - 1, latticeH - 1)), 0).g > 0.5;
  let wOcc = textureLoad(dataTextureC, clamp(siteCoord + vec2<i32>(-1, 0), vec2<i32>(0), vec2<i32>(latticeW - 1, latticeH - 1)), 0).g > 0.5;
  let edgeCount = select(0, 1, !nOcc) + select(0, 1, !sOcc) + select(0, 1, !eOcc) + select(0, 1, !wOcc);

  var isSpanning = false;
  if (label >= 0.0) {
    for (var i: i32 = 0; i < latticeH; i = i + 1) {
      if (extraBuffer[i] == label) {
        for (var j: i32 = 0; j < latticeH; j = j + 1) {
          if (extraBuffer[u32(latticeH) + u32(j)] == label) {
            isSpanning = true;
            break;
          }
        }
        break;
      }
    }
  }

  var color = sat * 0.6;
  if (isSpanning) {
    color = sat * bloomAmt + vec3<f32>(0.3, 0.2, 0.5) * bloomAmt * 0.5;
  }
  color = color + vec3<f32>(0.5, 0.3, 0.8) * f32(edgeCount) * 0.12;
  let ca = smoothstep(0.0, 1.0, f32(edgeCount)) * 0.08 * (1.0 + bass * 0.5);
  color = vec3<f32>(color.r + ca, color.g, color.b - ca);
  color = color + hash12(uv * 500.0 + time) * grainAmt;

  color = acesToneMap(color * 1.1);
  let clusterProxy = 1.0 - f32(edgeCount) * 0.22;
  let alpha = clamp(clusterProxy * select(1.0, 2.2, isSpanning) * (0.4 + depth * 0.6), 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth * 0.5 + select(0.0, 0.35, isSpanning), 0.0, 0.0, 0.0));
}
