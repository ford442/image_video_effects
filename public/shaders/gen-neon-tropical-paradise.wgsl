// Neon Tropical Paradise - Psychedelic tropical scene with neon palms, aurora sky, 
// glowing flowers, bioluminescent water. Hot pinks, electric blues, neon greens, sunset oranges.

// ═══════════════════════════════════════════════════════════════════
//  Neon Tropical Paradise
//  Category: generative
//  Features: tropical, neon, paradise, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

const PI: f32 = 3.14159265;

// ---- NOISE FUNCTIONS ----
fn hash2(p: vec2<f32>) -> vec2<f32> {
  let r = vec2<f32>(
    dot(p, vec2<f32>(127.1, 311.7)),
    dot(p, vec2<f32>(269.5, 183.3))
  );
  return fract(sin(r) * 43758.5453);
}

fn hash1(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2d(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  
  return mix(
    mix(hash1(i), hash1(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash1(i + vec2<f32>(0.0, 1.0)), hash1(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var val: f32 = 0.0;
  var amp: f32 = 0.5;
  var freq: f32 = 1.0;
  for (var i: i32 = 0; i < 6; i = i + 1) {
    if (i >= octaves) { break; }
    val += amp * noise2d(p * freq);
    freq *= 2.0;
    amp *= 0.5;
  }
  return val;
}

// ---- PALETTES ----
fn neonPinkBlue(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5, 0.5, 0.5);
  let c = vec3<f32>(1.0, 1.0, 1.0);
  let d = vec3<f32>(0.0, 0.33, 0.67);
  return a + b * cos(TAU * (c * t + d));
}

fn tropicalSunset(t: f32) -> vec3<f32> {
  let p = clamp(t, 0.0, 1.0);
  if (p < 0.2) {
    return mix(vec3<f32>(1.0, 0.2, 0.8), vec3<f32>(1.0, 0.1, 0.4), p / 0.2);
  } else if (p < 0.4) {
    return mix(vec3<f32>(1.0, 0.1, 0.4), vec3<f32>(1.0, 0.4, 0.1), (p - 0.2) / 0.2);
  } else if (p < 0.6) {
    return mix(vec3<f32>(1.0, 0.4, 0.1), vec3<f32>(1.0, 0.7, 0.1), (p - 0.4) / 0.2);
  } else if (p < 0.8) {
    return mix(vec3<f32>(1.0, 0.7, 0.1), vec3<f32>(0.2, 0.8, 1.0), (p - 0.6) / 0.2);
  } else {
    return mix(vec3<f32>(0.2, 0.8, 1.0), vec3<f32>(0.1, 0.2, 0.8), (p - 0.8) / 0.2);
  }
}

fn electricPalette(t: f32) -> vec3<f32> {
  let p = abs(fract(t + vec3<f32>(0.0, 0.333, 0.667)) * 6.0 - vec3<f32>(3.0));
  return pow(clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.6)) * 2.0;
}

// ---- SCENE ELEMENTS ----

// Aurora sky band
fn auroraBand(x: f32, y: f32, bandY: f32, width: f32, time: f32, colorShift: f32) -> vec3<f32> {
  let wave = sin(x * 3.0 + time * 0.5) * 0.05 + sin(x * 7.0 - time * 0.3) * 0.03;
  let dist = abs(y - bandY - wave);
  let glow = exp(-dist * dist / (width * width));
  let auroraColor = electricPalette(x * 2.0 + time * 0.15 + colorShift);
  return auroraColor * glow * 1.5;
}

// Stylized palm tree trunk
fn palmTrunk(uv: vec2<f32>, xPos: f32, sway: f32, height: f32) -> f32 {
  let dx = uv.x - xPos - sway * (1.0 - uv.y / height);
  let trunkW = 0.008 + (1.0 - uv.y / height) * 0.004;
  let dist = abs(dx);
  let inTrunk = smoothstep(trunkW, trunkW * 0.3, dist) * step(uv.y, height) * step(0.0, uv.y);
  return inTrunk;
}

// Palm frond (leaf)
fn palmFrond(uv: vec2<f32>, tipX: f32, tipY: f32, baseX: f32, baseY: f32, spread: f32) -> f32 {
  let t = clamp((uv.y - baseY) / (tipY - baseY), 0.0, 1.0);
  let curveX = baseX + (tipX - baseX) * t + sin(t * PI) * spread;
  let width = 0.012 * sin(t * PI) * (1.0 + spread);
  let dist = abs(uv.x - curveX);
  let frond = smoothstep(width, width * 0.15, dist) * step(uv.y, tipY) * step(baseY, uv.y);
  return frond;
}

// Full palm tree
fn palmTree(uv: vec2<f32>, xPos: f32, time: f32, swayAmt: f32, scale: f32) -> vec3<f32> {
  let treeColor = vec3<f32>(0.15, 0.6, 0.2) * 1.5;
  let trunkColor = vec3<f32>(0.4, 0.25, 0.15);
  
  let sway = sin(time * 0.8) * swayAmt;
  let h = 0.45 * scale;
  let topY = 0.3 + h * 0.5;
  let trunk = palmTrunk(uv, xPos, sway * 0.5, h);
  
  let tipX = xPos + sway;
  let frond = 0.0;
  
  // Multiple fronds radiating from top
  let angles = array<f32, 7>(-0.8, -0.4, -0.1, 0.15, 0.4, 0.7, 1.0);
  let spreads = array<f32, 7>(-0.08, -0.05, -0.02, 0.02, 0.05, 0.08, 0.06);
  
  var totalFrond: f32 = 0.0;
  for (var i: i32 = 0; i < 7; i = i + 1) {
    let a = angles[i];
    let sp = spreads[i];
    let frondX = tipX + cos(a) * 0.18 * scale;
    let frondY = topY - abs(sin(a)) * 0.12 * scale;
    let f = palmFrond(uv, frondX, frondY, tipX, topY - 0.02, sp + sway * 0.03);
    totalFrond = max(totalFrond, f);
  }
  
  var col = vec3<f32>(0.0);
  col += trunkColor * trunk * 2.0;
  col += treeColor * totalFrond * 1.5;
  
  return col;
}

// Glowing flower
fn neonFlower(uv: vec2<f32>, center: vec2<f32>, time: f32, petals: i32, scale: f32) -> vec3<f32> {
  let d = uv - center;
  let r = length(d);
  let a = atan2(d.y, d.x);
  
  let petalShape = abs(sin(a * f32(petals) * 0.5)) * scale;
  let flower = smoothstep(petalShape + 0.02, petalShape * 0.5, r) * step(0.0, r);
  flower = max(flower, smoothstep(0.04 * scale, 0.01, r));
  
  let flowerHue = time * 0.1 + center.x * 3.0;
  let flowerColor = electricPalette(flowerHue);
  return flowerColor * flower * 2.0;
}

// Twinkling star
fn twinkleStar(uv: vec2<f32>, starPos: vec2<f32>, time: f32, idx: f32) -> vec3<f32> {
  let d = length(uv - starPos);
  let twinkle = sin(time * (2.0 + hash1(starPos * 100.0) * 4.0) + idx * 1.5) * 0.5 + 0.5;
  let starSize = 0.001 + hash1(starPos * 50.0) * 0.001;
  let star = exp(-d * d / (starSize * starSize)) * twinkle;
  let starColor = electricPalette(hash1(starPos * 200.0) + time * 0.05);
  return starColor * star * 1.5;
}

// Bioluminescent water
fn bioWater(uv: vec2<f32>, time: f32, mouseNorm: vec2<f32>, mouseDown: f32, intensity: f32, scale: f32, colorShift: f32) -> vec3<f32> {
  let waterY = 0.32;
  if (uv.y < waterY - 0.05) {
    return vec3<f32>(0.0);
  }
  
  let waterSurf = uv.y;
  let inWater = smoothstep(waterY + 0.08, waterY - 0.03, waterSurf);
  
  if (inWater < 0.01) {
    return vec3<f32>(0.0);
  }
  
  // Base water color - deep electric blue
  let depth = (waterY - uv.y) * 4.0;
  let baseWater = mix(vec3<f32>(0.05, 0.2, 0.6), vec3<f32>(0.02, 0.08, 0.3), depth);
  
  // Animated waves
  let wave1 = sin(uv.x * 20.0 + time * 1.5) * 0.008;
  let wave2 = sin(uv.x * 35.0 - time * 2.0) * 0.004;
  let wave3 = sin(uv.x * 8.0 + time * 0.8) * 0.012;
  let surfaceLine = waterY + wave1 + wave2 + wave3;
  let nearSurface = smoothstep(0.04, 0.0, abs(uv.y - surfaceLine));
  
  // Bioluminescent sparkles
  let sparkle = pow(noise2d(vec2<f32>(uv.x * 50.0 * scale, uv.y * 30.0 - time * 0.5)), 8.0);
  sparkle += pow(noise2d(vec2<f32>(uv.x * 80.0 * scale + 100.0, uv.y * 50.0 + time * 0.3)), 10.0) * 0.5;
  
  // Mouse ripple
  var mouseRipple: f32 = 0.0;
  if (mouseDown > 0.5) {
    let md = length(uv - mouseNorm);
    mouseRipple = sin(md * 60.0 - time * 8.0) * exp(-md * 8.0) * 0.5;
    mouseRipple = max(mouseRipple, 0.0);
  }
  
  // Bioluminescent color
  let bioColor = electricPalette(uv.x * 3.0 + time * 0.1 + colorShift) * 2.0;
  let bioGlow = sparkle * intensity * 3.0 + mouseRipple * intensity;
  
  var color = baseWater * inWater;
  color += nearSurface * vec3<f32>(0.3, 0.7, 1.0) * 0.6;
  color += bioColor * bioGlow * inWater;
  color += vec3<f32>(0.2, 0.8, 1.0) * nearSurface * 0.8;
  
  // Reflection band
  let reflect = smoothstep(surfaceLine + 0.01, surfaceLine - 0.01, uv.y);
  color += vec3<f32>(0.4, 0.9, 1.0) * reflect * 0.15;
  
  return color;
}

// ---- MAIN ----
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.z, u.config.w);
  let aspect = res.x / res.y;

  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
    return;
  }

  let fragCoord = vec2<f32>(pixel);
  let uv = fragCoord / res;
  let uvAspect = vec2<f32>((uv.x - 0.5) * aspect + 0.5, uv.y);

  let time = u.config.x;
  let mouseNorm = u.zoom_config.yz / res;
  let mouseDown = u.zoom_config.w;

  let intensity = u.zoom_params.x;
  let speed = u.zoom_params.y;
  let scale = u.zoom_params.z;
  let colorShift = u.zoom_params.w;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let audioSpeed = speed * (0.85 + bass * 0.5);
  let audioIntensity = intensity * (0.9 + treble * 0.5);
  let audioColor = colorShift + mids * 0.2;

  let t = time * audioSpeed;

  // ---- SKY ----
  // Psychedelic sunset gradient
  let skyGrad = tropicalSunset(uv.y * 1.5 + sin(t * 0.1) * 0.1);
  var color = skyGrad * 1.2;

  // ---- AURORA BANDS ----
  for (var i: i32 = 0; i < 5; i = i + 1) {
    let bandY = 0.55 + f32(i) * 0.08 + sin(t * 0.2 + f32(i)) * 0.03;
    let width = 0.04 + f32(i) * 0.005;
    let band = auroraBand(uvAspect.x, uvAspect.y, bandY, width, t, colorShift + f32(i) * 0.2);
    color += band * intensity;
  }

  // ---- STARS ---- (upper portion only)
  if (uv.y > 0.5) {
    for (var i: i32 = 0; i < 25; i = i + 1) {
      let sx = fract(sin(f32(i) * 127.1) * 43758.5);
      let sy = fract(sin(f32(i) * 311.7) * 43758.5) * 0.5 + 0.5;
      let starPos = vec2<f32>(sx * aspect, sy);
      let star = twinkleStar(vec2<f32>(uvAspect.x, uv.y), starPos, time, f32(i));
      color += star;
    }
  }

  // ---- GROUND ----
  let groundY = 0.32;
  let inGround = smoothstep(groundY + 0.01, groundY - 0.01, uv.y);
  if (inGround > 0.0) {
    // Neon sand/dune
    let dune = fbm(vec2<f32>(uvAspect.x * 8.0, uv.y * 4.0) + t * 0.02, 3) * 0.03;
    let groundH = groundY + dune;
    let onGround = smoothstep(groundH + 0.01, groundH - 0.01, uv.y);
    
    let sandColor = mix(
      vec3<f32>(0.9, 0.4, 0.2),
      vec3<f32>(1.0, 0.7, 0.3),
      fbm(vec2<f32>(uvAspect.x * 20.0, uv.y * 10.0), 2)
    ) * 1.3;
    color = mix(color, sandColor, onGround);
  }

  // ---- PALM TREES ----
  let sway = sin(t * 0.8) * 0.015 * intensity;
  let treeScale = 0.8 + scale * 0.4;
  
  let tree1 = palmTree(uvAspect, 0.15, time, 0.015, treeScale);
  color += tree1;
  
  let tree2 = palmTree(uvAspect, 0.82, time + 1.0, 0.012, treeScale * 0.85);
  color += tree2;
  
  let tree3 = palmTree(uvAspect, 0.5, time + 2.5, 0.018, treeScale * 0.65);
  color += tree3;

  // ---- NEON FLOWERS ----
  let flower1 = neonFlower(uvAspect, vec2<f32>(0.25, 0.28), time, 6, 1.2);
  color += flower1;
  
  let flower2 = neonFlower(uvAspect, vec2<f32>(0.7, 0.26), time + 1.0, 8, 1.0);
  color += flower2;
  
  let flower3 = neonFlower(uvAspect, vec2<f32>(0.45, 0.24), time + 2.0, 5, 0.8);
  color += flower3;

  // ---- BIOLUMINESCENT WATER ----
  let water = bioWater(uvAspect, time, mouseNorm, mouseDown, intensity, scale, colorShift);
  color += water;

  // ---- FLOATING PARTICLES ----
  for (var i: i32 = 0; i < 12; i = i + 1) {
    let px = fract(sin(f32(i) * 73.1 + t * 0.02) * 43758.5);
    let py = fract(uvAspect.y * 2.0 + sin(f32(i) * 17.3 + t * 0.3) * 0.2);
    let pPos = vec2<f32>(px * aspect, py);
    let pd = length(vec2<f32>(uvAspect.x, uv.y) - pPos);
    let particle = exp(-pd * pd / 0.0003) * (sin(t * 3.0 + f32(i)) * 0.5 + 0.5);
    let pColor = electricPalette(f32(i) * 0.1 + t * 0.05 + colorShift);
    color += pColor * particle * 0.8 * intensity;
  }

  // ---- GLOBAL POST ----
  // Saturation boost
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(lum), color, 1.3 + intensity * 0.3);
  
  // Tone map
  color = max(color, vec3<f32>(0.0));
  color = color / (1.0 + color * 0.15);

  textureStore(writeTexture, pixel, vec4<f32>(color, 0.85));
}
