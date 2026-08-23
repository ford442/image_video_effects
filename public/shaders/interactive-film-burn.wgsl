// ═══════════════════════════════════════════════════════════════════
//  Interactive Film Burn — Batch 58E
//  Sprung ember hole, cigarette-click brands, traveling ember conveyors
//  along the burn rim, oil-slick heat color, held-drag flare.
//  A remains [hole, fire, smoke, alpha] diagnostic packing.
//  extraBuffer[133..138] is the existing burn-center spring (0,0 writer).
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

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var pos = p;
  let rot = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);
  for (var i: i32 = 0; i < 5; i = i + 1) {
    value = value + amplitude * noise(pos);
    pos = rot * pos * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let mouseRaw = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);
  let audio = plasmaBuffer[0].xyz;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let burnRadius = u.zoom_params.x * 0.80 * (1.0 + held * 0.18);
  let burnSpeed = u.zoom_params.y * 2.0;
  let grainStrength = u.zoom_params.z;
  let glowWidth = u.zoom_params.w * 0.20 + 0.01;

  var burnPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var burnVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  let prevTime = extraBuffer[137];
  let springInitialized = extraBuffer[138] > 0.5;
  let dt = select(0.0, clamp(time - prevTime, 0.0, 0.1), springInitialized);
  if (!springInitialized) {
    burnPos = mouseRaw;
    burnVel = vec2<f32>(0.0, 0.0);
  }
  let omega = mix(7.0, 11.0, held);
  let springAcc = (mouseRaw - burnPos) * (omega * omega) - burnVel * (2.0 * omega);
  burnVel = burnVel + springAcc * dt;
  burnPos = burnPos + burnVel * dt;
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = burnPos.x;
    extraBuffer[134] = burnPos.y;
    extraBuffer[135] = burnVel.x;
    extraBuffer[136] = burnVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }
  let mouse = burnPos;

  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let noiseScale = 10.0 + audio.z * 6.0;
  let noiseVal = fbm(uv * noiseScale + vec2<f32>(time * burnSpeed * 0.15, -time * burnSpeed * 0.11));
  let distortedDist = dist - noiseVal * (0.10 + audio.x * 0.30);

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let filmGrain = (hash12(uv * 120.0 + vec2<f32>(time * 7.3, time * 13.1)) - 0.5) * grainStrength * 0.35;
  let gray = dot(sourceColor, vec3<f32>(0.299, 0.587, 0.114));
  let sepia = vec3<f32>(gray * 1.18, gray * 1.0, gray * 0.78);
  let intactColor = mix(sourceColor, sepia, 0.55) + vec3<f32>(filmGrain);

  let d = distortedDist - burnRadius;
  var holeMask = 1.0 - smoothstep(-0.015, 0.015, d);
  var fireMask = smoothstep(-glowWidth, 0.0, d) * (1.0 - smoothstep(0.0, glowWidth, d));
  var smokeMask = 1.0 - smoothstep(glowWidth * 0.5, glowWidth * 3.0, d);
  var clickFireMask = 0.0;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri: u32 = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let clickAge = time - ripple.z;
    if (clickAge < 0.0 || clickAge > 3.0) { continue; }
    let clickVec = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
    let clickDist = length(clickVec);
    let grow = smoothstep(0.0, 0.6, clickAge);
    let brandRadius = 0.08 * grow;
    let brandD = clickDist - brandRadius - noiseVal * 0.03;
    let flameLife = 1.0 - smoothstep(0.35, 1.0, clickAge);
    let charSettle = 1.0 - smoothstep(1.5, 2.5, clickAge);
    holeMask = max(holeMask, (1.0 - smoothstep(-0.015, 0.015, brandD)) * grow);
    let brandFire = smoothstep(-glowWidth, 0.0, brandD) * (1.0 - smoothstep(0.0, glowWidth, brandD)) * flameLife;
    fireMask = max(fireMask, brandFire);
    smokeMask = max(smokeMask, (1.0 - smoothstep(glowWidth * 0.5, glowWidth * 3.0, brandD)) * charSettle);
    clickFireMask = max(clickFireMask, brandFire);
  }

  let edgeAngle = atan2(distVec.y, distVec.x);
  let sector = u32(clamp(floor((edgeAngle + 3.14159265) * 1.27323954), 0.0, 7.0));
  let sectorAmp = plasmaBuffer[(sector % 8u) + 1u].x * 0.4;
  let conveyor = pow(max(0.0, sin(edgeAngle * 10.0 - time * (8.0 + burnSpeed * 4.0) + noiseVal * 4.0)), 8.0);
  let packets = pow(max(0.0, sin(distortedDist * 42.0 - time * (5.0 + audio.y * 4.0))), 14.0) * fireMask;

  let emberNoise = noise(uv * 50.0 + vec2<f32>(time * 10.0, -time * 7.0));
  let emberGlow = smoothstep(-0.08, 0.0, d) * (0.4 + 0.6 * emberNoise) * (0.8 + sectorAmp);
  let fireT = clamp(d / glowWidth, 0.0, 1.0);
  var fireColor = mix(vec3<f32>(1.0, 0.98, 0.80), vec3<f32>(1.0, 0.30, 0.0), fireT);
  fireColor = mix(fireColor, vec3<f32>(0.08, 0.0, 0.0), fireT * fireT);
  let slick = hsv2rgb(vec3<f32>(fract(0.04 + fireT * 0.12 + audio.y * 0.15 + time * 0.08), 0.85, 1.0));
  fireColor = mix(fireColor, fireColor * slick * 1.35, 0.35 + held * 0.2);
  fireColor = mix(fireColor, vec3<f32>(1.0, 0.42, 0.04) * (0.75 + emberNoise * 0.5), clickFireMask);
  fireColor = fireColor + vec3<f32>(1.0, 0.45, 0.10) * emberGlow * (0.4 + 0.6 * audio.x);
  fireColor += slick * (conveyor * 0.45 + packets * 0.55) * fireMask;
  let charColor = vec3<f32>(0.0) + vec3<f32>(1.0, 0.18, 0.02) * emberGlow * 0.45;

  var finalColor = intactColor * mix(0.55, 1.0, smokeMask);
  finalColor = mix(finalColor, fireColor, fireMask);
  finalColor = mix(finalColor, charColor, holeMask);
  finalColor = mix(finalColor, prev.rgb, 0.12 * (1.0 - holeMask));

  var finalAlpha = (1.0 - holeMask) * (0.82 + 0.12 * smokeMask);
  finalAlpha = max(finalAlpha, fireMask * (0.35 + 0.45 * u.zoom_params.w));
  finalAlpha = clamp(finalAlpha, 0.0, 0.98);

  let baseDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthOut = clamp(mix(baseDepth, baseDepth * 0.25, holeMask) + fireMask * 0.08, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(holeMask, fireMask, smokeMask, finalAlpha));
}
