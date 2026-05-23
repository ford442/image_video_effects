// ═══════════════════════════════════════════════════════════════════
//  Vorticity Raincloud Convection
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven, temporal
//  Complexity: Very High
//  Scientific: Curl-noise cloud advection with vorticity confinement, buoyant convection, Mie silver lining, and rain-sheet transport
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

const PI: f32 = 3.14159265359;

fn clampCoord(p: vec2<i32>, size: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0, 0), size - vec2<i32>(1, 1));
}

fn saturate(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn safeNormalize2(v: vec2<f32>, fallback: vec2<f32>) -> vec2<f32> {
  let len = length(v);
  if (len > 1e-5) {
    return v / len;
  }
  return fallback;
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  let a = hash21(i + vec2<f32>(0.0, 0.0));
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var value = 0.0;
  var amplitude = 0.55;
  var frequency = 1.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    value += amplitude * valueNoise(p * frequency);
    frequency *= 2.02;
    amplitude *= 0.52;
  }
  return value;
}

fn streamFunction(p: vec2<f32>, time: f32) -> f32 {
  let q = p + vec2<f32>(time * 0.018, -time * 0.011);
  return fbm(q * 2.8) + 0.5 * fbm(q * 5.4 + 17.3);
}

fn curlNoise(p: vec2<f32>, time: f32, eps: f32) -> vec2<f32> {
  let dy = streamFunction(p + vec2<f32>(0.0, eps), time) - streamFunction(p - vec2<f32>(0.0, eps), time);
  let dx = streamFunction(p + vec2<f32>(eps, 0.0), time) - streamFunction(p - vec2<f32>(eps, 0.0), time);
  return vec2<f32>(dy, -dx) / max(2.0 * eps, 1e-4);
}

fn sampleState(uv: vec2<f32>, resolution: vec2<f32>, size: vec2<i32>) -> vec4<f32> {
  let pos = clamp(uv * resolution - vec2<f32>(0.5), vec2<f32>(0.0), resolution - vec2<f32>(1.001));
  let i0 = vec2<i32>(i32(floor(pos.x)), i32(floor(pos.y)));
  let f = fract(pos);
  let c00 = textureLoad(dataTextureC, clampCoord(i0, size), 0);
  let c10 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(1, 0), size), 0);
  let c01 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(0, 1), size), 0);
  let c11 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(1, 1), size), 0);
  return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

fn phaseMie(cosTheta: f32, g: f32) -> f32 {
  let denom = pow(max(1.0 + g * g - 2.0 * g * cosTheta, 0.08), 1.5);
  return (1.0 - g * g) / (4.0 * PI * denom);
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
  let pixel = 1.0 / min(resolution.x, resolution.y);

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let coverage = saturate(u.zoom_params.x);
  let turbulence = saturate(u.zoom_params.y);
  let rainIntensity = saturate(u.zoom_params.z);
  let windX = (u.zoom_params.w * 2.0 - 1.0) * 0.014;

  let prev = textureLoad(dataTextureC, coord, 0);
  let prevVelocity = vec2<f32>(prev.g, prev.b);
  let advected = sampleState(uv - prevVelocity, resolution, size);
  let advectedVelocity = vec2<f32>(advected.g, advected.b);

  let noiseField = fbm(vec2<f32>(uv.x * 3.2 + windX * time * 8.0, uv.y * 4.4 - time * 0.05));
  let altitude = 1.0 - uv.y;
  let cloudBand = smoothstep(0.18, 0.74, altitude);
  let baseCloud = smoothstep(0.48 - coverage * 0.22, 0.96, noiseField) * cloudBand;

  let mouse = u.zoom_config.yz;
  let mouseMask = (1.0 - smoothstep(0.0, 0.16, distance(uv, mouse))) * (0.18 + u.zoom_config.w * 1.25);

  var density = mix(advected.r, baseCloud, 0.06 + coverage * 0.06);
  var moisture = mix(advected.a, baseCloud * (0.45 + rainIntensity * 0.5), 0.045);

  let curl = curlNoise(uv * mix(1.5, 4.8, coverage) + vec2<f32>(time * 0.02, -time * 0.016), time, pixel * 5.0);
  var velocity = advectedVelocity * 0.97 + curl * (0.0015 + turbulence * 0.0095);
  velocity.x += windX;

  let vN = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(0, -1), size), 0).gb;
  let vS = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(0, 1), size), 0).gb;
  let vE = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(1, 0), size), 0).gb;
  let vW = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(-1, 0), size), 0).gb;
  let omega = (vE.y - vW.y) - (vN.x - vS.x);
  let gradAbsOmega = vec2<f32>(abs(vE.y) - abs(vW.y), abs(vN.x) - abs(vS.x));
  let confDir = safeNormalize2(gradAbsOmega, vec2<f32>(0.0, 1.0));
  let confinement = (0.001 + turbulence * 0.014) * (1.0 + bass * 3.0);
  velocity += vec2<f32>(confDir.y, -confDir.x) * omega * confinement;

  velocity.y -= (0.001 + density * 0.006 + moisture * 0.004);
  velocity.y -= mouseMask * 0.018;
  velocity.x += (uv.x - mouse.x) * mouseMask * 0.01;

  let pulseBoost = smoothstep(0.82, 0.98, bass);
  density = saturate(density * 0.995 + mouseMask * 0.06 + pulseBoost * 0.015);
  moisture = saturate(moisture * 0.996 + density * 0.018 + mouseMask * 0.05);

  let aboveState = sampleState(uv - vec2<f32>(windX * 5.0, 0.028 + rainIntensity * 0.05), resolution, size);
  let rainCore = smoothstep(0.45, 0.88, aboveState.r) * smoothstep(0.25, 0.95, aboveState.a) * rainIntensity;
  let rainNoise = fbm(vec2<f32>(uv.x * 72.0 + windX * 100.0, uv.y * 160.0 - time * 6.0));
  let rain = rainCore * smoothstep(0.42, 0.92, rainNoise) * smoothstep(0.18, 0.92, uv.y);
  moisture = saturate(moisture - rain * 0.09);
  density = saturate(density - rain * 0.025);

  let densityN = sampleState(uv + vec2<f32>(0.0, -pixel * 2.0), resolution, size).r;
  let densityS = sampleState(uv + vec2<f32>(0.0, pixel * 2.0), resolution, size).r;
  let densityE = sampleState(uv + vec2<f32>(pixel * 2.0, 0.0), resolution, size).r;
  let densityW = sampleState(uv + vec2<f32>(-pixel * 2.0, 0.0), resolution, size).r;
  let gradient = vec2<f32>(densityE - densityW, densityN - densityS);
  let gradientDir = safeNormalize2(gradient, vec2<f32>(0.0, 1.0));

  let lightDir2 = safeNormalize2(vec2<f32>(0.8, -0.55), vec2<f32>(0.8, -0.55));
  let shadow = saturate(sampleState(uv + lightDir2 * 0.025, resolution, size).r * 0.7 + sampleState(uv + lightDir2 * 0.055, resolution, size).r * 0.3);
  let silverEdge = smoothstep(0.012, 0.11, length(gradient)) * smoothstep(0.18, 0.85, density) * (1.0 - shadow);
  let cosTheta = dot(lightDir2, safeNormalize2(-gradientDir, vec2<f32>(0.0, 1.0)));
  let mie = phaseMie(cosTheta, 0.72);

  let lightningGate = smoothstep(0.9, 1.0, bass + 0.06 * sin(time * 27.0 + hash21(floor(uv * 26.0)) * 9.0));
  let lightningShape = smoothstep(0.55, 0.95, fbm(vec2<f32>(uv.x * 18.0, uv.y * 42.0 - time * 4.0)));
  let lightning = lightningGate * lightningShape * density;

  let skyColor = mix(vec3<f32>(0.42, 0.56, 0.80), vec3<f32>(0.86, 0.92, 0.98), altitude);
  let cloudBase = mix(vec3<f32>(0.26, 0.28, 0.33), vec3<f32>(0.90, 0.92, 0.95), smoothstep(0.15, 0.85, density));
  var cloudColor = mix(cloudBase, vec3<f32>(1.0, 0.99, 0.97), silverEdge * saturate(mie * 18.0));
  cloudColor = mix(cloudColor, vec3<f32>(0.18, 0.20, 0.25), shadow * density * 0.75);
  cloudColor += vec3<f32>(1.0, 0.98, 0.96) * lightning * 1.8;

  let rainColor = vec3<f32>(0.70, 0.82, 1.0) * rain * (0.35 + density * 0.8);
  let generatedColor = mix(skyColor, cloudColor + rainColor, saturate(density * 0.95 + rain * 0.45));
  let finalColor = mix(inputColor.rgb, generatedColor, 0.94);
  let finalAlpha = max(inputColor.a, saturate(0.42 + density * 0.55 + rain * 0.12 + lightning * 0.2));
  let finalDepth = mix(inputDepth, saturate(0.18 + density * 0.64 + rain * 0.18 + lightning * 0.16), 0.92);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(density, velocity.x, velocity.y, moisture));
  textureStore(dataTextureB, coord, vec4<f32>(rain, omega * 0.5 + 0.5, silverEdge, lightning));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
