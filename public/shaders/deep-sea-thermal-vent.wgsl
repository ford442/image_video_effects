// ═══════════════════════════════════════════════════════════════════
//  Deep Sea Thermal Vent
//  Category: generative
//  Features: audio-reactive, temporal-feedback, chromatic-dispersion,
//            hydrothermal-plumes, bioluminescence, mouse-flow-distortion
//  Complexity: High
//  Created: 2026-05-30
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn hash31(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453123);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pos = p;
  let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * noise2(pos);
    pos = rot * pos * 2.0 + vec2<f32>(100.0);
    a = a * 0.5;
  }
  return v;
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pos = p;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * noise2(pos.xy + vec2<f32>(pos.z * 0.3, pos.z * 0.7));
    pos = pos * 2.0 + vec3<f32>(100.0, 50.0, 25.0);
    a = a * 0.5;
  }
  return v;
}

// Curl noise for fluid-like plume motion
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = fbm2(p + vec2<f32>(eps, 0.0) + vec2<f32>(time * 0.05, 0.0), 4);
  let n2 = fbm2(p - vec2<f32>(eps, 0.0) + vec2<f32>(time * 0.05, 0.0), 4);
  let n3 = fbm2(p + vec2<f32>(0.0, eps) + vec2<f32>(time * 0.05, 0.0), 4);
  let n4 = fbm2(p - vec2<f32>(0.0, eps) + vec2<f32>(time * 0.05, 0.0), 4);
  let dx = (n1 - n2) / (2.0 * eps);
  let dy = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dy, -dx);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  let plumeSize = mix(0.8, 2.5, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let heatGlow = u.zoom_params.z;
  let microbeDensity = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = uv * vec2<f32>(aspect, 1.0);

  // Vent position at bottom center
  let ventPos = vec2<f32>(aspect * 0.5, 0.05);

  // Mouse distorts vent flow
  let mouseUV = mouse * 0.5 + 0.5;
  let mouseUVAspect = mouseUV * vec2<f32>(aspect, 1.0);
  let mouseDist = length(p - mouseUVAspect);
  let mouseInfluence = exp(-mouseDist * mouseDist * 2.0);

  // Plume coordinate system: distance from vent, angle, height
  let toVent = p - ventPos;
  let distFromVent = length(toVent);
  let angle = atan2(toVent.y, toVent.x);
  let height = max(toVent.y, 0.0);

  // Plume rises upward with curl noise turbulence
  let plumeScale = 3.0 / plumeSize;
  let plumeP = p * plumeScale + vec2<f32>(0.0, -time * 0.15);
  let curl = curlNoise(plumeP, time);

  // Bass swells the plumes
  let swell = 1.0 + bass * 0.8;
  let plumeRadius = (0.15 + height * 0.4) * swell;

  // Mouse distortion pushes plume
  let pushDir = normalize(p - mouseUVAspect + vec2<f32>(0.001));
  let distortedP = p + curl * (0.03 + turbulence * 0.08) + pushDir * mouseInfluence * 0.15;
  let distortedToVent = distortedP - ventPos;
  let distortedDist = length(distortedToVent);

  // Plume density field
  let plumeCenterDist = abs(distortedToVent.x) / max(plumeRadius, 0.01);
  let plumeFalloff = exp(-plumeCenterDist * plumeCenterDist) * exp(-height * 0.8);
  let plumeNoise = fbm3(vec3<f32>(distortedP * 2.0, time * 0.2), 5);
  let plumeDensity = plumeFalloff * (0.5 + plumeNoise * 0.5) * smoothstep(0.0, 0.1, height);

  // Multiple plume columns
  let plume2Dist = length(distortedP - ventPos - vec2<f32>(0.2 * aspect, 0.0));
  let plume3Dist = length(distortedP - ventPos + vec2<f32>(0.15 * aspect, 0.0));
  let plume2 = exp(-plume2Dist * plume2Dist * 8.0) * 0.6 * swell;
  let plume3 = exp(-plume3Dist * plume3Dist * 10.0) * 0.4 * swell;
  let totalPlume = clamp(plumeDensity + plume2 + plume3, 0.0, 1.0);

  // Mids add particle turbulence within plumes
  let turbNoise = fbm3(vec3<f32>(distortedP * 5.0, time * 0.5), 4);
  let turbParticles = step(1.0 - mids * 0.3, turbNoise) * totalPlume * mids * turbulence;

  // Heat glow at vent mouth
  let ventGlow = exp(-distFromVent * distFromVent * 15.0) * heatGlow * (1.0 + bass * 2.0);

  // Chromatic dispersion in plume minerals: R=iron sulfide (warm), G=copper, B=calcium
  let caStrength = 0.02 * totalPlume * (1.0 + treble);
  let rOffset = vec2<f32>(caStrength * 0.8, caStrength * 0.3);
  let gOffset = vec2<f32>(-caStrength * 0.4, caStrength * 0.6);
  let bOffset = vec2<f32>(caStrength * 0.2, -caStrength * 0.7);

  let plumeR = fbm3(vec3<f32>((distortedP + rOffset) * 2.0, time * 0.2), 5);
  let plumeG = fbm3(vec3<f32>((distortedP + gOffset) * 2.0, time * 0.2), 5);
  let plumeB = fbm3(vec3<f32>((distortedP + bOffset) * 2.0, time * 0.2), 5);

  let chromaPlume = vec3<f32>(plumeR, plumeG, plumeB) * totalPlume;

  // Mineral-rich plume colors: warm sulfides near vent, cooler upward
  let mineralWarm = vec3<f32>(0.9, 0.5, 0.2);
  let mineralCool = vec3<f32>(0.3, 0.6, 0.7);
  let mineralColor = mix(mineralWarm, mineralCool, smoothstep(0.0, 0.5, height));

  // Plume color with chromatic dispersion
  let plumeColor = chromaPlume * mineralColor * (0.6 + bass * 0.5);

  // Ocean floor
  let floorNoise = fbm2(p * vec2<f32>(8.0, 3.0) + vec2<f32>(0.0, 0.5), 5);
  let floorColor = vec3<f32>(0.02, 0.025, 0.03) * (0.7 + floorNoise * 0.5);
  let floorMask = smoothstep(0.08, 0.0, uv.y);

  // Vent structure
  let ventDist = length(p - ventPos);
  let ventWall = smoothstep(0.06, 0.04, abs(ventDist - 0.04)) * floorMask;
  let ventColor = vec3<f32>(0.15, 0.12, 0.08) * (1.0 + floorNoise * 0.3);

  // Treble creates bioluminescent microbe flashes
  let microbeTime = time * 3.0;
  let microbeGrid = floor(p * (8.0 + microbeDensity * 12.0));
  let microbeHash = hash31(vec3<f32>(microbeGrid, fract(microbeTime * 0.1)));
  let microbePhase = fract(microbeHash * 37.0 + microbeTime * (0.5 + microbeHash));
  let microbeFlash = smoothstep(0.1, 0.0, abs(microbePhase - 0.5)) * step(0.7, microbeHash);
  let microbePos = (microbeGrid + 0.5) / (8.0 + microbeDensity * 12.0);
  let microbeDistField = length(p - microbePos);
  let microbeGlow = exp(-microbeDistField * microbeDistField * 200.0) * microbeFlash * treble * 2.0;

  // Microbe colors: bioluminescent greens and blues
  let microbeHue = fract(microbeHash * 0.3 + 0.25);
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let h = abs(fract(vec3<f32>(microbeHue) + k) * 6.0 - vec3<f32>(3.0));
  let microbeColor = clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));

  // Turbulence particles color
  let turbColor = vec3<f32>(0.7, 0.8, 0.9) * turbParticles;

  var color = floorColor + floorMask * ventColor * ventWall + plumeColor + turbColor;
  color = color + microbeColor * microbeGlow;

  // Vent glow adds warm light
  color = color + vec3<f32>(1.0, 0.6, 0.2) * ventGlow * 0.5;

  // Temporal feedback: trailing plume smoke
  let feedback = mix(color, prev.rgb, 0.2 + bass * 0.1);
  let feedbackMask = smoothstep(0.05, 0.3, prev.a) * totalPlume * 0.4;
  color = mix(color, feedback, feedbackMask);

  // Semantic alpha: plume density + glow + microbes + vent wall
  let alpha = clamp(totalPlume * 0.8 + ventGlow * 0.6 + microbeGlow * 0.5 + ventWall * 0.9, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(totalPlume * 0.5 + ventGlow * 0.4 + microbeGlow * 0.3, 0.0, 0.0, 0.0));
}
