// ═══════════════════════════════════════════════════════════════════
//  WASM HLS Physarum Swarm
//  Category: generative
//  Features: agent-based, audio-reactive, mouse-driven, video-food,
//            upgraded-rgba, temporal-feedback, chromatic-trails
//  Complexity: High
//  Created: 2026-06-28
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

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash32(seed: u32) -> f32 {
  var x = seed;
  x ^= x >> 16u;
  x *= 0x7feb352du;
  x ^= x >> 15u;
  x *= 0x846ca68bu;
  x ^= x >> 16u;
  return f32(x) / f32(0xffffffffu);
}

fn sense(pos: vec2<f32>, angle: f32, sensorDist: f32, res: vec2<f32>) -> f32 {
  let dir = vec2<f32>(cos(angle), sin(angle));
  let sensorPos = pos + dir * sensorDist;
  let texCoord = vec2<i32>(sensorPos);
  if (texCoord.x < 0 || texCoord.y < 0 || texCoord.x >= i32(res.x) || texCoord.y >= i32(res.y)) {
    return 0.0;
  }
  let trail = textureLoad(dataTextureC, texCoord, 0).r;
  let uv = sensorPos / res;
  let foodColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let food = (foodColor.r + foodColor.g + foodColor.b) * 0.333;
  return trail + food * 2.5;
}

fn palette(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5, 0.5, 0.5);
  let c = vec3<f32>(1.0, 1.0, 1.0);
  let d = vec3<f32>(0.263, 0.416, 0.557);
  return a + b * cos(6.28318 * (c * t + d));
}

fn paletteChromatic(t: f32, audio: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5 + audio * 0.3, 0.5, 0.5 - audio * 0.2);
  let c = vec3<f32>(1.0, 1.0, 0.8);
  let d = vec3<f32>(0.1 + audio * 0.3, 0.4, 0.7 - audio * 0.2);
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.z, u.config.w);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let sensorAngle = mix(0.3, 1.2, u.zoom_params.x);
  let sensorDist = mix(5.0, 25.0, u.zoom_params.y);
  let decayRate = mix(0.85, 0.995, u.zoom_params.z);
  let depositAmount = mix(0.3, 2.0, u.zoom_params.w);

  let numAgents = u32(res.x) * u32(res.y);
  let agentIdx = u32(gid.y * u32(res.x) + gid.x);
  let bufBase = agentIdx * 4u;

  // Agent state: x, y, angle, alive
  if (extraBuffer[bufBase + 3u] == 0.0) {
    extraBuffer[bufBase + 0u] = hash32(agentIdx * 3u) * res.x;
    extraBuffer[bufBase + 1u] = hash32(agentIdx * 3u + 1u) * res.y;
    extraBuffer[bufBase + 2u] = hash32(agentIdx * 3u + 2u) * 6.28318;
    extraBuffer[bufBase + 3u] = 1.0;
  }

  var pos = vec2<f32>(extraBuffer[bufBase + 0u], extraBuffer[bufBase + 1u]);
  var angle = extraBuffer[bufBase + 2u];

  // Audio-reactive turn speed
  let turnSpeed = 0.5 + bass * 3.0 + mid * 1.5;
  let audioDeposit = depositAmount * (1.0 + bass * 2.0);

  // Sense in three directions
  let wF = sense(pos, angle, sensorDist, res);
  let wL = sense(pos, angle + sensorAngle, sensorDist, res);
  let wR = sense(pos, angle - sensorAngle, sensorDist, res);

  // Steering
  if (wF > wL && wF > wR) {
    // Straight
  } else if (wF < wL && wF < wR) {
    let rnd = hash32(agentIdx * 7u + u32(time * 1000.0));
    if (rnd > 0.5) { angle += turnSpeed * sensorAngle; }
    else { angle -= turnSpeed * sensorAngle; }
  } else if (wL > wR) {
    angle += turnSpeed * sensorAngle;
  } else {
    angle -= turnSpeed * sensorAngle;
  }

  // Mouse attraction/repulsion - screen top = UP, flip Y
  let mouseUV = u.zoom_config.yz;
  let mousePos = mouseUV * res;
  let distToMouse = distance(pos, mousePos);
  let mouseInfluence = 150.0;
  if (distToMouse < mouseInfluence) {
    let dirToMouse = normalize(mousePos - pos);
    let desiredAngle = atan2(dirToMouse.y, dirToMouse.x);
    let blend = 1.0 - distToMouse / mouseInfluence;
    angle = mix(angle, desiredAngle, blend * 0.3);
  }

  // Move
  let moveSpeed = 1.5 + treble * 1.0;
  let dir = vec2<f32>(cos(angle), sin(angle));
  pos += dir * moveSpeed;

  // Wrap bounds
  if (pos.x < 0.0) { pos.x += res.x; }
  if (pos.x >= res.x) { pos.x -= res.x; }
  if (pos.y < 0.0) { pos.y += res.y; }
  if (pos.y >= res.y) { pos.y -= res.y; }

  // Save state
  extraBuffer[bufBase + 0u] = pos.x;
  extraBuffer[bufBase + 1u] = pos.y;
  extraBuffer[bufBase + 2u] = angle;

  // Trail blur & decay (every pixel)
  var sum = vec3<f32>(0.0);
  var count = 0.0;
  for (var i = -1; i <= 1; i++) {
    for (var j = -1; j <= 1; j++) {
      let nCoord = coord + vec2<i32>(i, j);
      if (nCoord.x >= 0 && nCoord.y >= 0 && nCoord.x < i32(res.x) && nCoord.y < i32(res.y)) {
        sum += textureLoad(dataTextureC, nCoord, 0).rgb;
        count += 1.0;
      }
    }
  }
  let blurResult = sum / count;
  let diffused = blurResult * decayRate;

  // Deposit trail
  var agentAdded = vec3<f32>(0.0);
  if (i32(pos.x) == coord.x && i32(pos.y) == coord.y) {
    let t = time * 0.1 + bass * 2.0;
    agentAdded = paletteChromatic(t, bass) * audioDeposit;
  }

  let trailColor = clamp(diffused + agentAdded, vec3<f32>(0.0), vec3<f32>(1.0));
  textureStore(dataTextureA, coord, vec4<f32>(trailColor, 1.0));

  // Color mapping
  let trailDensity = textureLoad(dataTextureC, coord, 0).r;
  let chromaCol = paletteChromatic(trailDensity * 2.0 + time * 0.05, bass);
  let agentCol = vec4<f32>(chromaCol, 1.0);

  // Combine with video
  let uv = vec2<f32>(coord) / res;
  let vidColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let finalColor = mix(vidColor, agentCol, sat(trailDensity * 1.5));

  // Audio-reactive bloom
  let bloom = vec3<f32>(0.2, 0.1, 0.4) * bass * trailDensity * 0.5;
  var col = finalColor.rgb + bloom;

  // Temporal persistence (bass_env smoothing via extraBuffer tail)
  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  col = mix(col, prev * 0.94, 0.06);

  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = sat(luma * 0.7 + 0.2 + trailDensity * 0.3);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));

  let depthUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
