// ═══════════════════════════════════════════════════════════════════
//  Langton's Ant
//  Category: generative
//  Features: cellular-automata, heat-map, audio-reactive, mouse-interactive,
//    depth-aware, temporal-feedback, aces-tone-map, chromatic-aberration
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
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


fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn heatColor(h: f32) -> vec3<f32> {
  let t = clamp(h * 0.25, 0.0, 1.0);
  let cols = array<vec3<f32>, 5>(
    vec3<f32>(0.05, 0.15, 0.55), vec3<f32>(0.15, 0.65, 0.85),
    vec3<f32>(0.85, 0.75, 0.15), vec3<f32>(0.85, 0.25, 0.10),
    vec3<f32>(0.95, 0.95, 0.90)
  );
  let idx = t * 4.0;
  let i = i32(clamp(idx, 0.0, 3.0));
  return mix(cols[i], cols[i + 1], fract(idx));
}

fn dirVec(d: i32) -> vec2<i32> {
  let dirs = array<vec2<i32>, 4>(vec2<i32>(1, 0), vec2<i32>(0, 1), vec2<i32>(-1, 0), vec2<i32>(0, -1));
  return dirs[d];
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = vec2<f32>(pixel) / resolution;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let p1 = u.zoom_params.x;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let gridSize = 128;
  let cellSize = i32(resolution.x / f32(gridSize));
  let cell = pixel / cellSize;
  let depthScale = mix(0.6, 1.4, depth);
  let scaledUV = (uv - 0.5) * depthScale + 0.5;
  let sCell = vec2<i32>(scaledUV * resolution) / cellSize;

  var state = prev.r;
  var heat = prev.g;
  let flipBoost = 1.0 + bass * 2.0 + p1;
  var isAntHere = 0.0;
  // ═══ CHUNK: multi-pass state packing — ant position/direction lives in dataTextureA, not writeTexture ═══
  var antEncoded = vec4<f32>(0.0);
  var isAntPixel = false;

  for (var a = 0; a < 3; a++) {
    let apx = a * cellSize;
    let antState = textureLoad(dataTextureC, vec2<i32>(apx, 0), 0);
    var ax = i32(antState.r * f32(gridSize));
    var ay = i32(antState.g * f32(gridSize));
    var adir = i32(antState.b * 4.0);

    if antState.a < 0.5 {
      let seeds = array<vec2<i32>, 3>(vec2<i32>(64, 64), vec2<i32>(43, 43), vec2<i32>(85, 85));
      ax = seeds[a].x; ay = seeds[a].y; adir = a;
    }
    if mouseDown && a == 0 {
      let mcell = vec2<i32>(mouse * resolution) / cellSize;
      ax = mcell.x % gridSize; ay = mcell.y % gridSize;
    }

    let dvec = dirVec(adir);
    let fcx = (ax - dvec.x + gridSize) % gridSize;
    let fcy = (ay - dvec.y + gridSize) % gridSize;
    if sCell.x == fcx && sCell.y == fcy { state = 1.0 - state; heat += flipBoost; }
    isAntHere += select(0.0, 1.0, sCell.x == ax && sCell.y == ay);

    if pixel.x == apx && pixel.y == 0 {
      isAntPixel = true;
      adir = (adir + select(3, 1, state > 0.5)) % 4;
      let nd = dirVec(adir);
      ax = (ax + nd.x + gridSize) % gridSize;
      ay = (ay + nd.y + gridSize) % gridSize;
      antEncoded = vec4<f32>(f32(ax) / 128.0, f32(ay) / 128.0, f32(adir) / 4.0, 1.0);
    }
  }

  if prev.a < 0.1 {
    state = step(0.55, hashf(f32(sCell.x) * 17.0 + f32(sCell.y) * 31.0 + p3 * 100.0));
    heat = state * 0.5;
  }

  heat = clamp(heat * (0.97 - p4 * 0.03), 0.0, 12.0);
  var color = heatColor(heat);
  color += vec3<f32>(0.9, 0.9, 0.85) * isAntHere;

  let caStr = 0.003 * (1.0 + bass) * depthScale + abs(heat - 3.0) * 0.0015;
  color = vec3<f32>(color.r * (1.0 + caStr), color.g, color.b * (1.0 - caStr * 0.5));
  color = acesToneMap(color * 1.2);

  let alpha = clamp(heat * 0.08 + isAntHere * 0.5, 0.0, 1.0) * depth;
  textureStore(writeTexture, pixel, applyGenerativePrimaryControls(vec4<f32>(color, alpha)));
  textureStore(writeDepthTexture, pixel, vec4<f32>(heat * 0.08, 0.0, 0.0, 0.0));

  // ═══ Persistent state: cell flip-state(.r), heat(.g), ant-here(.b) everywhere;
  //     ant position/direction encoding overrides at the 3 tracker pixels (apx, 0) ═══
  let cellStateOut = vec4<f32>(state, heat, isAntHere, 1.0);
  textureStore(dataTextureA, pixel, select(cellStateOut, antEncoded, isAntPixel));
}
