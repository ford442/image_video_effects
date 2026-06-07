// ═══════════════════════════════════════════════════════════════════
//  FitzHugh-Nagumo Excitable Media
//  Category: generative
//  Features: upgraded-rgba, aces-tone-map, depth-aware, audio-reactive, mouse-driven, temporal, hue-preserve-clamp, ign-dither
//  Complexity: High
//  Scientific: Dual-mode excitable media with FitzHugh-Nagumo action waves and Gray-Scott fallback kinetics
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

fn loadState(coord: vec2<i32>, size: vec2<i32>) -> vec2<f32> {
  return textureLoad(dataTextureC, clampCoord(coord, size), 0).rg;
}

fn laplacian(coord: vec2<i32>, size: vec2<i32>) -> vec2<f32> {
  let c = loadState(coord, size);
  let n = loadState(coord + vec2<i32>(0, -1), size);
  let s = loadState(coord + vec2<i32>(0, 1), size);
  let e = loadState(coord + vec2<i32>(1, 0), size);
  let w = loadState(coord + vec2<i32>(-1, 0), size);
  let ne = loadState(coord + vec2<i32>(1, -1), size);
  let nw = loadState(coord + vec2<i32>(-1, -1), size);
  let se = loadState(coord + vec2<i32>(1, 1), size);
  let sw = loadState(coord + vec2<i32>(-1, 1), size);
  return (n + s + e + w) * 0.2 + (ne + nw + se + sw) * 0.05 - c;
}

fn saturate(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hue-preserve-clamp (from AGENTS.md) ═══
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, maxLum / max(l, 1e-4));
}

// ═══ CHUNK: ign-dither (from AGENTS.md) ═══
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
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

  let fitzMode = smoothstep(0.45, 0.55, u.zoom_params.w);
  let pulseStrength = mix(0.25, 1.3, u.zoom_params.z);
  let mouseRadius = mix(0.035, 0.13, u.zoom_params.x);

  let prev = textureLoad(dataTextureC, coord, 0);
  let seed = hash21(floor(uv * 32.0) + vec2<f32>(13.0, 17.0));
  let initSpot = smoothstep(0.88, 0.985, hash21(floor(uv * 24.0) + vec2<f32>(3.0, 11.0)));
  let grayInit = vec2<f32>(1.0 - initSpot * 0.55, initSpot * 0.95);
  let fitzInit = vec2<f32>(-1.05 + seed * 0.06, -0.62 + seed * 0.04);
  let initState = mix(grayInit, fitzInit, fitzMode);
  let initMix = select(0.0, 1.0, abs(prev.r) + abs(prev.g) < 0.0001);
  let state = mix(prev.rg, initState, initMix);
  let lap = laplacian(coord, size);

  let mouse = u.zoom_config.yz;
  let mouseStim = (1.0 - smoothstep(0.0, mouseRadius, distance(uv, mouse))) * u.zoom_config.w * (0.6 + pulseStrength * 0.8);

  let pacing = mix(0.35, 2.25, 0.15 + bass * 0.85);
  let pulseIndex = floor(time * pacing);
  let pulseCenter = vec2<f32>(
    hash21(vec2<f32>(pulseIndex + 11.0, pulseIndex * 0.73 + 5.1)),
    hash21(vec2<f32>(pulseIndex * 0.61 + 17.0, pulseIndex + 23.0))
  );
  let pulsePhase = fract(time * pacing);
  let pulseEnvelope = exp(-pulsePhase * (14.0 - bass * 8.0)) * smoothstep(0.08, 0.95, bass + 0.15 * mids);
  let audioStim = pulseEnvelope * (1.0 - smoothstep(0.0, 0.18 + pulseStrength * 0.08, distance(uv, pulseCenter))) * (0.2 + bass * 1.9);

  let a = saturate(state.x);
  let b = saturate(state.y);
  let feed = mix(0.026, 0.074, u.zoom_params.x);
  let kill = mix(0.046, 0.071, u.zoom_params.y);
  let diffA = mix(0.15, 0.28, u.zoom_params.z);
  let diffB = mix(0.07, 0.14, u.zoom_params.z);
  let reaction = a * b * b;
  let grayA = saturate(a + (diffA * lap.x - reaction + feed * (1.0 - a)) * 0.55 - mouseStim * 0.05);
  let grayB = saturate(b + (diffB * lap.y + reaction - (kill + feed) * b) * 0.55 + mouseStim * 0.85 + audioStim * 0.6);

  let uState = clamp(state.x, -2.4, 2.4);
  let vState = clamp(state.y, -1.8, 1.8);
  let aParam = 0.7;
  let bParam = 0.8;
  let epsilon = 0.08;
  let du = 0.45 * lap.x + uState - (uState * uState * uState) / 3.0 - vState + mouseStim * 1.65 + audioStim * 1.55;
  let dv = epsilon * (uState + aParam - bParam * vState);
  let fitzDt = 0.055 + u.zoom_params.z * 0.04;
  let fitzU = clamp(uState + du * fitzDt, -2.4, 2.4);
  let fitzV = clamp(vState + dv * fitzDt, -1.8, 1.8);

  let newState = mix(vec2<f32>(grayA, grayB), vec2<f32>(fitzU, fitzV), fitzMode);

  let gsActivity = abs(grayB - b) + reaction * 3.0;
  let fitzActivity = abs(fitzU - uState) + abs(fitzV - vState) + abs(lap.x) * 0.4;
  let activity = mix(gsActivity, fitzActivity, fitzMode);
  let waveFront = smoothstep(0.05, 0.45, activity + audioStim * 0.2);

  let gsColor = mix(vec3<f32>(1.0, 0.34, 0.12), vec3<f32>(0.08, 0.64, 1.0), grayB)
    + vec3<f32>(1.0, 0.82, 0.48) * reaction * 5.5;

  let activator = saturate(fitzU * 0.38 + 0.5);
  let inhibitor = saturate(fitzV * 0.42 + 0.42);
  var warm = mix(vec3<f32>(0.82, 0.26, 0.05), vec3<f32>(1.0, 0.82, 0.15), activator);
  warm = mix(warm, vec3<f32>(1.0, 1.0, 0.96), smoothstep(0.58, 1.0, activator));
  let cool = mix(vec3<f32>(0.03, 0.05, 0.18), vec3<f32>(0.22, 0.88, 1.0), inhibitor);
  var fitzColor = mix(cool, warm, smoothstep(0.14, 0.72, activator));
  fitzColor += vec3<f32>(1.0, 0.58, 0.18) * waveFront * (0.7 + bass * 2.0);
  fitzColor += vec3<f32>(0.30, 0.48, 0.96) * inhibitor * 0.22;

  let generatedColor = mix(gsColor, fitzColor, fitzMode);
  let opacity = 0.9;
  let finalColor = mix(inputColor.rgb, generatedColor, opacity);
  let finalAlpha = max(inputColor.a, 0.82 + 0.18 * waveFront);
  let depthSignal = mix(grayB, activator, fitzMode);
  let finalDepth = mix(inputDepth, clamp(0.22 + depthSignal * 0.65 + waveFront * 0.2, 0.0, 1.0), 0.9);

  var outCol = acesToneMap(huePreserveClamp(finalColor * 1.1, 2.0));
  outCol += (ign(vec2<f32>(coord)) - 0.5) / 255.0;
  textureStore(writeTexture, coord, vec4<f32>(outCol, finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(newState, waveFront, fitzMode));
  textureStore(dataTextureB, coord, vec4<f32>(generatedColor, saturate(activity)));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
