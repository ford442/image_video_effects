// ═══════════════════════════════════════════════════════════════════
//  Conway Game of Life
//  Category: generative
//  Features: cellular-automata, neon, audio-reactive, mouse-interactive,
//    depth-aware, temporal-feedback, aces-tone-map, chromatic-aberration
//  Complexity: High
//  Created: 2026-05-31
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

fn cellState(tex: texture_2d<f32>, cell: vec2<i32>, cellSize: i32) -> f32 {
  let samplePix = cell * cellSize + cellSize / 2;
  return textureLoad(tex, samplePix, 0).r;
}

fn countNeighbors(tex: texture_2d<f32>, cell: vec2<i32>, cellSize: i32) -> f32 {
  var count = 0.0;
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if dx == 0 && dy == 0 { continue; }
      count += cellState(tex, cell + vec2<i32>(dx, dy), cellSize);
    }
  }
  return count;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = vec2<f32>(pixel) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let depthScale = mix(0.5, 1.5, depth);
  let cellSize = i32(max(4.0, mix(16.0, 4.0, p3 * depthScale)));
  let cell = pixel / cellSize;

  let prevState = cellState(dataTextureC, cell, cellSize);
  let neighbors = countNeighbors(dataTextureC, cell, cellSize);

  let ruleMorph = fract(time * p2 * 0.05);
  let golWeight = 1.0 - smoothstep(0.3, 0.7, ruleMorph);
  let dnWeight = smoothstep(0.3, 0.7, ruleMorph) * (1.0 - smoothstep(0.8, 1.0, ruleMorph));
  let hlWeight = smoothstep(0.8, 1.0, ruleMorph);

  let golBorn = step(2.99, neighbors) * step(neighbors, 3.01);
  let golSurvive = step(1.99, neighbors) * step(neighbors, 3.01) * prevState;
  let dnBorn = (step(2.99, neighbors) * step(neighbors, 3.01) + step(5.99, neighbors) * step(neighbors, 8.01)) * (1.0 - prevState);
  let dnSurvive = (step(2.99, neighbors) * step(neighbors, 3.01) + step(4.99, neighbors) * step(neighbors, 8.01)) * prevState;
  let hlBorn = (step(2.99, neighbors) * step(neighbors, 3.01) + step(5.99, neighbors) * step(neighbors, 6.01)) * (1.0 - prevState);
  let hlSurvive = (step(1.99, neighbors) * step(neighbors, 3.01) + step(5.99, neighbors) * step(neighbors, 6.01)) * prevState;

  let born = golBorn * golWeight + dnBorn * dnWeight + hlBorn * hlWeight;
  let survive = golSurvive * golWeight + dnSurvive * dnWeight + hlSurvive * hlWeight;
  let state = clamp(born + survive, 0.0, 1.0);

  let mDist = length(uv - mouse);
  let mouseSeed = step(mDist, 0.015 * depthScale) * f32(mouseDown);
  let audioSeed = step(hashf(time * 7.0 + uv.x * 100.0), bass * 0.08 * p1);
  let seedState = clamp(mouseSeed + audioSeed, 0.0, 1.0);
  let newState = max(state, seedState);

  let wasDead = 1.0 - prevState;
  let birthEvent = newState * wasDead;
  let deathEvent = (1.0 - newState) * prevState;
  let survival = newState * prevState;

  let caStr = 0.004 * (1.0 + bass) * depthScale;
  let birthR = birthEvent * (1.0 + caStr);
  let birthB = birthEvent * (1.0 - caStr * 0.5);

  var color = vec3<f32>(0.0);
  color += vec3<f32>(0.0, 0.85, 0.95) * birthR;
  color += vec3<f32>(0.9, 0.2, 0.7) * survival;
  color += vec3<f32>(0.95, 0.65, 0.1) * deathEvent * 0.3;

  let fadeDecay = 0.88 + p4 * 0.08;
  let fadeColor = prev.rgb * fadeDecay;
  color = max(color, fadeColor);

  let bloom = birthEvent * 0.25 * (1.0 + bass);
  color += vec3<f32>(0.6, 0.9, 1.0) * bloom;

  let activity = abs(newState - prevState);
  let caShift = activity * caStr * 2.0;
  color = vec3<f32>(color.r * (1.0 + caShift), color.g, color.b * (1.0 - caShift * 0.5));

  color = acesToneMap(color * 1.3);

  let alpha = newState * (activity + birthEvent * 0.5 + 0.1) * depth;

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(newState, 0.0, 0.0, 0.0));
}
