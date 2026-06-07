// ═══════════════════════════════════════════════════════════════════
//  Volumetric Spiral Galaxy
//  Category: simulation
//  Features: simulation, procedural, volumetric, spiral-galaxy
//  Complexity: Very High
//  Upgraded by: Algorithmist Agent
//  Date: 2026-05-03
// ═══════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for(var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise2D(pos);
    pos = rot * pos * 2.0 + 100.0;
    a = a * 0.5;
  }
  return v;
}

fn spiralArmDensity(p: vec2<f32>, arms: f32, tightness: f32) -> f32 {
  let r = length(p);
  let angle = atan2(p.y, p.x);
  let spiralAngle = log(max(r, 0.001)) * tightness;
  let armPhase = (angle - spiralAngle) * arms;
  let armDist = abs(fract(armPhase / 6.2831853) - 0.5) * 2.0;
  let radialFalloff = exp(-r * 2.5);
  let armWidth = 0.12 + radialFalloff * 0.15;
  var density = smoothstep(armWidth, 0.0, armDist) * radialFalloff;
  let bulge = exp(-r * r * 5.0);
  density = density + bulge * 0.4;
  return density;
}

fn nebulaClouds(p: vec2<f32>, time: f32) -> f32 {
  let warp = vec2<f32>(
    fbm(p * 1.5 + time * 0.08, 4),
    fbm(p * 1.5 + vec2<f32>(5.2, 1.3) + time * 0.1, 4)
  );
  let warped = p + warp * 0.5;
  let clouds = fbm(warped * 2.5 + vec2<f32>(time * 0.03, 0.0), 5);
  return clouds * clouds;
}

fn keplerianOrbit(ringIndex: f32, time: f32) -> vec2<f32> {
  let baseRadius = 0.08 + ringIndex * 0.06;
  let orbitSpeed = 0.15 / sqrt(max(baseRadius, 0.02));
  let angle = time * orbitSpeed + ringIndex * 2.4;
  return vec2<f32>(cos(angle), sin(angle)) * baseRadius;
}

fn starParticleGlow(p: vec2<f32>, time: f32) -> vec3<f32> {
  var glow = vec3<f32>(0.0);
  let armCount = 3.0;
  for(var arm: i32 = 0; arm < 3; arm = arm + 1) {
    let fArm = f32(arm);
    let armOffset = fArm * 6.2831853 / armCount;
    for(var ring: i32 = 0; ring < 8; ring = ring + 1) {
      let fRing = f32(ring);
      let pos = keplerianOrbit(fRing, time + armOffset * 0.3);
      let rot = mat2x2<f32>(cos(armOffset), -sin(armOffset), sin(armOffset), cos(armOffset));
      let worldPos = rot * pos;
      let d = length(p - worldPos);
      let mass = 1.0 / (1.0 + fRing * 0.25);
      let brightness = mass / (1.0 + d * d * 1500.0);
      let temp = 1.0 - fRing * 0.1;
      let starColor = vec3<f32>(1.0, 0.75 + temp * 0.2, 0.5 + temp * 0.3);
      glow = glow + starColor * brightness;
    }
  }
  return glow;
}

fn galaxyHalo(p: vec2<f32>, time: f32) -> f32 {
  let r = length(p);
  let halo = exp(-r * 1.8) * 0.15;
  let turbulence = fbm(p * 4.0 + time * 0.05, 3) * 0.08;
  return halo + turbulence;
}

fn colorTemperature(t: f32) -> vec3<f32> {
  let r = 1.0;
  let g = mix(0.5, 0.95, t);
  let b = mix(0.25, 0.85, t);
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let zoom = max(u.zoom_params.x, 0.1);
  let pan = vec2<f32>(u.zoom_params.y, u.zoom_params.z);
  let centeredUV = (uv - 0.5) / zoom + 0.5 + (pan - 0.5);
  let aspect = resolution.x / resolution.y;
  let p = (centeredUV - 0.5) * vec2<f32>(aspect, 1.0) * 3.5;

  let armDensity = spiralArmDensity(p, 3.0, 2.2);
  let clouds = nebulaClouds(p, time);
  let stars = starParticleGlow(p, time);
  let halo = galaxyHalo(p, time);

  let integratedDensity = armDensity * (0.6 + clouds * 0.4) + halo;
  let bulge = exp(-length(p) * length(p) * 4.0);

  let hotGas = integratedDensity * 0.9 + bulge * 0.6;
  let dustScattering = integratedDensity * clouds * 0.5 + bulge * 0.25;
  let synchrotron = integratedDensity * clouds * 0.35 + armDensity * 0.2;

  let temp = 0.5 + bulge * 0.5;
  let gasColor = colorTemperature(temp);

  var r = hotGas * gasColor.r + stars.r * 0.6;
  var g = dustScattering * 0.7 + hotGas * gasColor.g * 0.4 + stars.g * 0.5;
  var b = synchrotron * 1.8 + hotGas * gasColor.b * 0.3 + stars.b * 0.35 + bulge * 0.1;

  let opticalDepth = clamp(integratedDensity + bulge * 0.6 + stars.r * 0.3, 0.0, 1.0);
  let galaxyColor = vec3<f32>(r, g, b);

  let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let opacity = clamp(u.zoom_params.w, 0.0, 1.0);
  let finalRGB = mix(texColor.rgb, galaxyColor, opticalDepth * opacity);
  let finalAlpha = mix(texColor.a, 1.0, opticalDepth * opacity);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, finalAlpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
