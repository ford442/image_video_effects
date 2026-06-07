// ═══════════════════════════════════════════════════════════════════
//  Ghost Flame
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba, aces-tone-map
//  Complexity: High
//  Description: Fluid advection flame simulation with temperature-based
//    alpha translucency. Hot regions are bright and slightly translucent,
//    cool regions fade to transparent. Simplex noise advection drives
//    the flame with upward velocity and vorticity confinement.
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

// ═══ CHUNK: hash functions ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: simplex-like 3D noise ═══
fn snoise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(
      mix(hash13(i + vec3<f32>(0.0, 0.0, 0.0)), hash13(i + vec3<f32>(1.0, 0.0, 0.0)), f.x),
      mix(hash13(i + vec3<f32>(0.0, 1.0, 0.0)), hash13(i + vec3<f32>(1.0, 1.0, 0.0)), f.x),
      f.y
    ),
    mix(
      mix(hash13(i + vec3<f32>(0.0, 0.0, 1.0)), hash13(i + vec3<f32>(1.0, 0.0, 1.0)), f.x),
      mix(hash13(i + vec3<f32>(0.0, 1.0, 1.0)), hash13(i + vec3<f32>(1.0, 1.0, 1.0)), f.x),
      f.y
    ),
    f.z
  );
}

// ═══ CHUNK: fbm 3D ═══
fn fbm3(p: vec3<f32>) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0u; i < 4u; i = i + 1u) {
    val = val + amp * snoise3(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return val;
}

// ═══ CHUNK: temperature to blackbody color ═══
fn blackbodyColor(t: f32) -> vec3<f32> {
  // t in 0..1, maps to approximate blackbody radiation
  var color: vec3<f32>;
  let temp = t * 4.0;
  if (temp < 1.0) {
    // Deep red ember
    color = vec3<f32>(temp * 0.3, 0.0, temp * 0.05);
  } else if (temp < 2.0) {
    // Orange flame
    let f = temp - 1.0;
    color = vec3<f32>(0.3 + f * 0.7, f * 0.4, 0.05 + f * 0.1);
  } else if (temp < 3.0) {
    // Yellow-white hot
    let f = temp - 2.0;
    color = vec3<f32>(1.0, 0.4 + f * 0.6, 0.15 + f * 0.3);
  } else {
    // White-blue ghost flame
    let f = temp - 3.0;
    color = vec3<f32>(1.0, 1.0, 0.45 + f * 0.55);
  }
  return color;
}

// ═══ CHUNK: ghost flame color (cooler, ethereal) ═══
fn ghostFlameColor(t: f32) -> vec3<f32> {
  // Ghostly blue-cyan-white palette
  let bb = blackbodyColor(t);
  let ghostTint = vec3<f32>(0.4, 0.7, 1.0);
  let emberTint = vec3<f32>(0.9, 0.3, 0.1);
  // Low temp = ghost blue, high temp = warm core
  let mixed = mix(ghostTint * 0.5, bb, smoothstep(0.1, 0.5, t));
  // Add warm ember at highest temps
  return mix(mixed, emberTint, smoothstep(0.7, 1.0, t) * 0.4);
}

// ═══ CHUNK: velocity field ═══
fn velocityField(p: vec3<f32>, t: f32, turbulence: f32) -> vec2<f32> {
  // Upward base velocity with noise-driven swirl
  let noise1 = fbm3(p * 2.0 + vec3<f32>(t * 0.5, t * 0.3, 0.0));
  let noise2 = fbm3(p * 3.0 + vec3<f32>(t * 0.4 + 100.0, t * 0.2, 50.0));
  let vx = (noise1 - 0.5) * turbulence * 0.3;
  let vy = 0.5 + noise2 * turbulence * 0.2;
  return vec2<f32>(vx, vy);
}

// ═══ CHUNK: bass envelope smoothing ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let uv = vec2<f32>(gid.xy) / res;
  let ps = 1.0 / res;
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let time = u.config.x;

  // Audio input
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rms = plasmaBuffer[0].w;

  // Parameters
  let flameHeight = mix(0.5, 1.5, u.zoom_params.x);
  let turbulence = mix(0.3, 1.5, u.zoom_params.y);
  let coolingRate = mix(0.92, 0.99, u.zoom_params.z);
  let diffusion = mix(0.5, 2.0, u.zoom_params.w);

  // Mouse: position adds heat source, click creates burst
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let mouseHeat = smoothstep(0.15, 0.0, mouseDist) * (0.3 + mouseDown * 0.7);

  // Smooth bass for flame height, RMS for turbulence
  var prevBass = extraBuffer[3];
  var prevRMS = extraBuffer[4];
  let smoothBass = bass_env(prevBass, bass, 0.12, 0.03);
  let smoothRMS = bass_env(prevRMS, rms, 0.1, 0.04);
  extraBuffer[3] = smoothBass;
  extraBuffer[4] = smoothRMS;

  // Audio-reactive: bass drives flame height, RMS drives turbulence
  let audioHeight = flameHeight * (1.0 + smoothBass * 0.6);
  let audioTurb = turbulence * (1.0 + smoothRMS * 0.8);

  // Read previous frame state from dataTextureC
  let prevState = textureLoad(dataTextureC, coord, 0);
  var temperature = prevState.r;
  var fuel = prevState.g;
  var velocityX = prevState.b;
  var age = prevState.a;

  // Seed on first frame
  if (time < 0.1) {
    temperature = 0.0;
    fuel = 0.0;
    velocityX = 0.0;
    age = 0.0;
    // Seed base flame at bottom center
    let baseDist = length(uv - vec2<f32>(0.5, 0.92));
    if (baseDist < 0.12) {
      fuel = 1.0;
      temperature = 0.4;
    }
  }

  temperature = clamp(temperature, 0.0, 2.0);
  fuel = clamp(fuel, 0.0, 2.0);
  age = clamp(age, 0.0, 10.0);

  // ═══ FLUID ADVECTION ═══
  // Sample neighbors for diffusion and advection
  let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Velocity field at this position
  let vel = velocityField(vec3<f32>(uv, time * 0.1), time, audioTurb);

  // Advection: sample from upstream
  let advectUV = uv - vel * ps * 3.0;
  let advected = textureSampleLevel(dataTextureC, u_sampler, clamp(advectUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Mix advected and current for stability
  temperature = mix(temperature, advected.r, 0.4);
  fuel = mix(fuel, advected.g, 0.3);
  velocityX = mix(velocityX, advected.b, 0.3);

  // ═══ DIFFUSION ═══
  let lapTemp = left.r + right.r + down.r + up.r - 4.0 * temperature;
  temperature = temperature + lapTemp * 0.04 * diffusion;

  let lapFuel = left.g + right.g + down.g + up.g - 4.0 * fuel;
  fuel = fuel + lapFuel * 0.02 * diffusion;

  // ═══ VORTICITY CONFINEMENT (approximate) ═══
  let curl = (right.b - left.b) * 0.5 - (up.r - down.r) * 0.5;
  let vorticity = curl * audioTurb * 0.15;
  temperature = temperature + vorticity;

  // ═══ COMBUSTION ═══
  let burnRate = mix(0.02, 0.08, flameHeight);
  let ignitionTemp = 0.15;
  let burning = step(ignitionTemp, temperature) * fuel * burnRate * (1.0 + smoothBass * 0.5);
  fuel = fuel - burning;
  temperature = temperature + burning * 2.5;

  // ═══ COOLING & DECAY ═══
  // Faster cooling higher up (upward velocity)
  let heightFactor = 1.0 - uv.y;
  let heightCooling = coolingRate - heightFactor * 0.03 * audioHeight;
  temperature = temperature * heightCooling;

  // Fuel replenishment at bottom
  let bottomProximity = smoothstep(0.15, 0.0, uv.y);
  fuel = fuel + bottomProximity * 0.02 * (1.0 + smoothBass * 0.3);

  // Age tracking
  age = age + burning * 0.3 + 0.01;
  age = age * 0.99;

  // ═══ MOUSE HEAT SOURCE ═══
  temperature = temperature + mouseHeat * 1.5;
  fuel = fuel + mouseHeat * 0.4;
  velocityX = velocityX + (mousePos.x - 0.5) * mouseHeat * 2.0;

  // ═══ RIPPLE BURSTS ═══
  let rippleCount = min(u32(u.config.y), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let rAge = time - ripple.z;
    if (rAge < 0.0 || rAge > 1.5) { continue; }
    let rDist = length(uv - ripple.xy);
    let burst = smoothstep(0.12, 0.0, rDist) * max(0.0, 1.0 - rAge * 1.5);
    temperature = temperature + burst * 2.0;
    fuel = fuel + burst * 0.5;
    velocityX = velocityX + (ripple.xy.x - 0.5) * burst;
  }

  // Clamp after all updates
  temperature = clamp(temperature, 0.0, 2.0);
  fuel = clamp(fuel, 0.0, 2.0);
  velocityX = clamp(velocityX, -1.0, 1.0);
  age = clamp(age, 0.0, 10.0);

  // ═══ VISUALIZATION ═══
  let tempNorm = clamp(temperature / 1.5, 0.0, 1.0);
  var flameColor = ghostFlameColor(tempNorm);

  // Ghostly glow from high temps
  let glow = smoothstep(0.4, 0.9, tempNorm) * 0.3;
  flameColor = flameColor + vec3<f32>(0.5, 0.8, 1.0) * glow;

  // Smoke/darkening at edges
  let smoke = smoothstep(0.0, 0.3, tempNorm) * (1.0 - smoothstep(0.3, 0.7, tempNorm));
  let smokeColor = vec3<f32>(0.05, 0.08, 0.12);
  flameColor = mix(smokeColor, flameColor, smoothstep(0.05, 0.2, tempNorm));

  // Age adds cyan ghost-trail tint
  let ghostAge = smoothstep(0.5, 3.0, age) * (1.0 - smoothstep(0.5, 1.0, tempNorm));
  flameColor = mix(flameColor, vec3<f32>(0.3, 0.6, 0.9), ghostAge * 0.25);

  flameColor = clamp(flameColor, vec3<f32>(0.0), vec3<f32>(1.5));

  // Soft tone mapping for HDR flame
  flameColor = flameColor / (1.0 + flameColor * 0.4);
  flameColor = clamp(flameColor, vec3<f32>(0.0), vec3<f32>(1.0));

  // Alpha = temperature: hot = bright and slightly translucent, cool = dark and transparent
  // Ghost flames are more translucent than normal fire
  let hotAlpha = mix(0.25, 0.75, tempNorm);
  let coolAlpha = mix(0.0, 0.15, tempNorm);
  let finalAlpha = mix(coolAlpha, hotAlpha, smoothstep(0.1, 0.4, tempNorm));

  // Temporal smoothing for flicker reduction
  let prevAlpha = prevState.a;
  var finalColor = mix(flameColor, prevState.rgb, 0.1);
  let smoothAlpha = mix(finalAlpha, prevAlpha, 0.08);

  // Depth for chromatic + pass-through
  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Store state for next frame
  textureStore(dataTextureA, coord, vec4<f32>(temperature, fuel, velocityX, age));

  // Chromatic aberration + ACES
  let caStr = 0.003 * (1.0 + bass) + depthVal * 0.001;
  finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
  finalColor = acesToneMap(finalColor * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, smoothAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
