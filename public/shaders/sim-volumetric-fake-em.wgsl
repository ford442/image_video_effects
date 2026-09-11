// ═══════════════════════════════════════════════════════════════════
//  Sim: Volumetric Fake + EM Field
//  Category: lighting-effects
//  Features: simulation, fake-volumetrics, mouse-driven, electromagnetic, interactive, upgraded-rgba, audio-reactive
//  Complexity: High
//  Upgraded: 2026-09-11
//  Ideas: Beer-Lambert dust on bent rays; E×B lateral shaft bend
//  A packing: ACES display RGBA; extraBuffer[133..134] previous mouse
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
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * normalize(r) / (dist * dist);
}

fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let hasAudio = arrayLength(&plasmaBuffer) > 0u;
  let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
  let mids = select(0.0, plasmaBuffer[0].y, hasAudio);
  let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

  let lightIntensity = mix(0.5, 2.0, u.zoom_params.x);
  let chargeStrength = mix(0.5, 3.0, u.zoom_params.x);
  let emDistortion = mix(0.0, 0.15, u.zoom_params.y);
  let dustDensity = mix(0.0, 1.0, u.zoom_params.y);
  let chromaticSplit = mix(0.0, 0.02, u.zoom_params.z);
  let scattering = mix(0.3, 1.5, u.zoom_params.z);
  let rippleCharge = mix(0.5, 2.0, u.zoom_params.w);
  let noiseSpeed = mix(0.1, 1.0, u.zoom_params.w);

  var prevMouse = mousePos;
  if (arrayLength(&extraBuffer) > 134u) {
    prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (gid.x == 0u && gid.y == 0u) {
      extraBuffer[133] = mousePos.x;
      extraBuffer[134] = mousePos.y;
    }
  }
  let mouseVel = (mousePos - prevMouse) * 60.0;

  let lightPos = mousePos + vec2<f32>(cos(time * 0.2) * 0.05, sin(time * 0.15) * 0.05);

  let eField = electricField(uv, mousePos, chargeStrength);
  let bField = magneticField(uv, mousePos, mouseVel, chargeStrength);
  let fieldMag = length(eField);
  let fieldDir = select(vec2<f32>(0.0), normalize(eField), fieldMag > 0.0001);

  var totalE = eField;
  var totalB = bField;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let orbitAngle = elapsed * 2.0 + f32(i) * 1.256;
      let orbitRadius = 0.05 + 0.1 * smoothstep(0.0, 1.0, elapsed);
      let orbitPos = mousePos + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitRadius;
      let secondaryCharge = -rippleCharge * exp(-elapsed * 0.8);
      let secVel = vec2<f32>(-sin(orbitAngle), cos(orbitAngle)) * 2.0;
      totalE = totalE + electricField(uv, orbitPos, secondaryCharge);
      totalB = totalB + magneticField(uv, orbitPos, secVel, secondaryCharge);
    }
  }

  let toLight = lightPos - uv;
  let distToLight = max(length(toLight), 0.001);
  let dirToLight = toLight / distToLight;

  let eHat = select(vec2<f32>(0.0), normalize(totalE), length(totalE) > 0.0001);
  let ePerp = vec2<f32>(-eHat.y, eHat.x);
  let exbKick = ePerp * totalB * emDistortion * 0.35;
  let bentDir = normalize(dirToLight + eHat * emDistortion * smoothstep(0.0, 2.0, fieldMag) + exbKick);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var volumetric = vec3<f32>(0.0);
  let samples = i32(16.0 + dustDensity * 16.0);
  var opticalDepth = 0.0;
  let maxSamples = 32;

  for (var i: i32 = 0; i < maxSamples; i = i + 1) {
    if (i >= samples) { break; }
    let t = f32(i) / f32(max(samples, 1));
    let samplePos = uv + bentDir * t * distToLight;
    if (samplePos.x < 0.0 || samplePos.x > 1.0 || samplePos.y < 0.0 || samplePos.y > 1.0) {
      continue;
    }
    let sampleColor = textureSampleLevel(readTexture, u_sampler, clamp(samplePos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let luma = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));
    let dustTap = noise(samplePos * 20.0 + time * noiseSpeed);
    opticalDepth = opticalDepth + (0.15 + luma * 0.45 + dustTap * dustDensity) * (1.0 - t);
    let beer = exp(-opticalDepth * (0.8 + scattering * 0.6));
    let attenuation = (1.0 - t) * (1.0 - t) * beer;
    volumetric = volumetric + vec3<f32>(1.0) * attenuation;
  }

  volumetric = volumetric / f32(max(samples, 1));
  let dustNoise = noise(uv * 20.0 + time * noiseSpeed) * noise(uv * 15.0 - time * noiseSpeed * 0.5);
  let dust = pow(dustNoise, 3.0) * dustDensity;

  let density = 0.3 * scattering * (1.0 + bass * 0.35);
  var lightRays = volumetric * density * lightIntensity;
  lightRays = lightRays + vec3<f32>(dust * lightIntensity * 0.5);
  let sunColor = vec3<f32>(1.0, 0.95, 0.8);
  lightRays = lightRays * sunColor;

  var color = src.rgb + lightRays;
  let viewDir = normalize(uv - lightPos);
  let lightAim = normalize(vec2<f32>(0.5) - lightPos);
  let alignment = max(0.0, dot(viewDir, lightAim));
  color = color + sunColor * alignment * alignment * lightIntensity * 0.1;
  let falloff = 1.0 / (1.0 + distToLight * distToLight * 2.0);
  color = mix(src.rgb, color, falloff);

  let rOffset = clamp(uv + vec2<f32>(chromaticSplit * totalB, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bOffset = clamp(uv - vec2<f32>(chromaticSplit * totalB, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let rSample = textureSampleLevel(readTexture, u_sampler, rOffset, 0.0).r;
  let bSample = textureSampleLevel(readTexture, u_sampler, bOffset, 0.0).b;
  color = vec3<f32>(rSample, color.g, bSample) * 0.3 + color * 0.7;

  let coreDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let coreGlow = exp(-coreDist * coreDist * 400.0) * chargeStrength;
  color = color + vec3<f32>(0.6, 0.9, 1.0) * coreGlow * 0.5 * (1.0 + treble * 0.2);

  let alpha = clamp(0.85 + fieldMag * 0.1 + mids * 0.05, 0.0, 1.0) * src.a;
  let display = vec4<f32>(aces(color), alpha);
  textureStore(writeTexture, gid.xy, display);
  textureStore(dataTextureA, gid.xy, display);
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
