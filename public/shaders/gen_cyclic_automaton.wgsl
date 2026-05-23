// ═══════════════════════════════════════════════════════════════════
//  Greenberg-Hastings Excitable Automaton
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven, temporal
//  Complexity: Medium
//  Scientific: Greenberg-Hastings excitable media with cardinal-wave triggering, refractory cooling, and bass-driven spontaneous ignition
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn clampCoord(p: vec2<i32>, size: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0, 0), size - vec2<i32>(1, 1));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn decodeState(v: f32, numStates: i32) -> i32 {
  return clamp(i32(floor(v * f32(numStates) + 0.5)), 0, numStates - 1);
}

fn loadState(coord: vec2<i32>, size: vec2<i32>, numStates: i32) -> i32 {
  return decodeState(textureLoad(dataTextureC, clampCoord(coord, size), 0).r, numStates);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let size = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x;

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let numStates = i32(round(mix(4.0, 24.0, u.zoom_params.x)));
  let spontaneousBase = mix(0.0001, 0.012, u.zoom_params.y);
  let bloomStrength = mix(0.15, 0.8, u.zoom_params.z);
  let cooldownBoost = mix(0.85, 1.25, u.zoom_params.w);

  let currentState = loadState(coord, size, numStates);
  let n = loadState(coord + vec2<i32>(0, -1), size, numStates);
  let s = loadState(coord + vec2<i32>(0, 1), size, numStates);
  let e = loadState(coord + vec2<i32>(1, 0), size, numStates);
  let w = loadState(coord + vec2<i32>(-1, 0), size, numStates);
  let ne = loadState(coord + vec2<i32>(1, -1), size, numStates);
  let nw = loadState(coord + vec2<i32>(-1, -1), size, numStates);
  let se = loadState(coord + vec2<i32>(1, 1), size, numStates);
  let sw = loadState(coord + vec2<i32>(-1, 1), size, numStates);

  let cardFiring = select(0, 1, n == 1) + select(0, 1, s == 1) + select(0, 1, e == 1) + select(0, 1, w == 1);
  let allFiring = cardFiring + select(0, 1, ne == 1) + select(0, 1, nw == 1) + select(0, 1, se == 1) + select(0, 1, sw == 1);

  let mouse = u.zoom_config.yz;
  let mouseMask = (1.0 - smoothstep(0.0, 0.11, distance(uv, mouse))) * u.zoom_config.w;
  let rand = hash21(vec2<f32>(f32(coord.x), f32(coord.y)) + vec2<f32>(time * 31.1, time * 17.3));
  let spontaneousProb = spontaneousBase * (0.2 + bass * 4.2);
  let ignite = (cardFiring > 0) || (rand < spontaneousProb) || (mouseMask > 0.02);

  let isResting = currentState == 0;
  let isFiring = currentState == 1;
  let isRefractory = currentState >= 2;
  let refractoryNext = select(currentState + 1, 0, currentState >= numStates - 1);

  var nextState = currentState;
  nextState = select(nextState, 1, isResting && ignite);
  nextState = select(nextState, 2, isFiring);
  nextState = select(nextState, refractoryNext, isRefractory);

  let firingMask = select(0.0, 1.0, nextState == 1);
  let refractoryMask = select(0.0, 1.0, nextState >= 2);
  let refractoryProgress = clamp(f32(max(nextState - 2, 0)) / max(1.0, f32(numStates - 2)), 0.0, 1.0);
  let neighborGlow = f32(allFiring) / 8.0;
  let bloom = neighborGlow * bloomStrength;

  let restColor = vec3<f32>(0.01, 0.03, 0.10) + vec3<f32>(0.10, 0.18, 0.34) * bloom * 0.18;
  let firingColor = mix(vec3<f32>(1.0, 0.93, 0.56), vec3<f32>(1.0, 1.0, 1.0), smoothstep(0.4, 1.0, bass + mouseMask));
  let refractoryColor = mix(vec3<f32>(0.18, 0.98, 1.0), vec3<f32>(0.03, 0.12, 0.45), refractoryProgress * cooldownBoost);

  var generatedColor = mix(restColor, refractoryColor, refractoryMask);
  generatedColor = mix(generatedColor, firingColor, firingMask);
  generatedColor += vec3<f32>(1.0, 0.96, 0.72) * bloom * 0.4;
  generatedColor += vec3<f32>(0.16, 0.44, 1.0) * bloom * (1.0 - firingMask) * 0.28;
  generatedColor += vec3<f32>(0.08, 0.12, 0.22) * smoothstep(0.2, 1.0, mids) * (1.0 - refractoryMask) * 0.15;

  let opacity = 0.92;
  let finalColor = mix(inputColor.rgb, generatedColor, opacity);
  let finalAlpha = max(inputColor.a, 0.85 + firingMask * 0.15);
  let depthSignal = max(firingMask, (1.0 - refractoryProgress) * refractoryMask);
  let finalDepth = mix(inputDepth, clamp(0.16 + depthSignal * 0.72 + bloom * 0.22 + treble * 0.06, 0.0, 1.0), 0.88);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(f32(nextState) / f32(numStates), firingMask, refractoryProgress, bloom));
  textureStore(dataTextureB, coord, vec4<f32>(f32(cardFiring) / 4.0, spontaneousProb * 20.0, mouseMask, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
