// ================================================================
//  Data Slicer
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fractal-slicing, fbm-warping, voronoi-patterns
//  Complexity: High
//  Chunks From: data-slicer
//  Created: 2026-05-30
//  Upgraded: 2026-06-28
//  By: The Complexity Architect
// ================================================================

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=JitterSpeed, y=SliceThickness, z=ChaosAmount, w=ColorSplit
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453;
  return fract(h);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32, lacunarity: f32, gain: f32) -> f32 {
  var total = 0.0;
  var amplitude = 1.0;
  var frequency = 1.0;
  var maxVal = 0.0;
  for (var i = 0; i < octaves; i = i + 1) {
    total = total + amplitude * noise2(p * frequency);
    maxVal = maxVal + amplitude;
    amplitude = amplitude * gain;
    frequency = frequency * lacunarity;
  }
  return total / maxVal;
}

fn voronoiF2F1(p: vec2<f32>, time: f32) -> vec2<f32> {
  let n = floor(p);
  let f = fract(p);
  var minDist1 = 100.0;
  var minDist2 = 100.0;
  var nearest = vec2<f32>(0.0);
  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let g = vec2<f32>(f32(i), f32(j));
      let h = hash22(n + g);
      let o = vec2<f32>(sin(h.x * TAU + time * 0.3), cos(h.y * TAU + time * 0.25)) * 0.3 + 0.5;
      let r = g + o - f;
      let d = dot(r, r);
      if (d < minDist1) {
        minDist2 = minDist1;
        minDist1 = d;
        nearest = n + g + o;
      } else if (d < minDist2) {
        minDist2 = d;
      }
    }
  }
  return vec2<f32>(sqrt(minDist1), sqrt(minDist2));
}

fn domainWarp(p: vec2<f32>, time: f32, strength: f32, bass: f32) -> vec2<f32> {
  let q = vec2<f32>(
    fbm(p + vec2<f32>(0.0, 0.0) + time * 0.15, 5, 2.1, 0.5),
    fbm(p + vec2<f32>(5.2, 1.3) + time * 0.12, 5, 2.1, 0.5)
  );
  let r = vec2<f32>(
    fbm(p + 3.0 * q + vec2<f32>(1.7, 9.2) + time * 0.08 + bass * 0.5, 4, 2.0, 0.5),
    fbm(p + 3.0 * q + vec2<f32>(8.3, 2.8) + time * 0.10 + bass * 0.3, 4, 2.0, 0.5)
  );
  return p + strength * r;
}

fn quasicrystal(p: vec2<f32>, time: f32, freq: f32) -> f32 {
  var value = 0.0;
  let angles = 5.0;
  for (var i = 0; i < 5; i = i + 1) {
    let angle = f32(i) * TAU / angles + time * 0.05;
    let dir = vec2<f32>(cos(angle), sin(angle));
    value = value + cos(dot(p, dir) * freq);
  }
  return value / 5.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let jitterSpeed = 0.15 + zp.x * 3.5;
  let sliceThickness = mix(0.006, 0.12, zp.y);
  let chaosAmount = zp.z * 0.12;
  let colorSplit = zp.w * 0.03;

  // Multi-scale fractal slicing with domain warping
  let warpedUV = domainWarp(uv * vec2<f32>(aspect * 3.0, 3.0), time, chaosAmount * 2.0, bass);
  let sliceIndex = floor(warpedUV.y / sliceThickness);
  let localY = fract(warpedUV.y / sliceThickness);

  // Voronoi cellular cracks for slicing boundaries
  let voro = voronoiF2F1(uv * 8.0 + vec2<f32>(time * 0.2, sliceIndex * 0.5), time);
  let cellEdge = smoothstep(0.02, 0.08, voro.y - voro.x);

  // Quasicrystal pattern for slice modulation
  let qc = quasicrystal(uv * 12.0, time * 0.3 + bass * 2.0, 2.0 + mids * 3.0);

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseMask = 1.0 - smoothstep(0.0, 0.65, mouseDist);

  // FBM-based temporal jitter with 6 octaves
  let jitterSeed = vec2<f32>(sliceIndex, floor(time * jitterSpeed * 6.0));
  let fbmJitter = (fbm(jitterSeed + vec2<f32>(time * 0.5, 0.0), 6, 2.1, 0.5) - 0.5) * chaosAmount * (1.0 + bass * 0.8 + mouseMask * 0.5);

  // Multi-frequency wave distortion
  let wave1 = sin(sliceIndex * 0.33 + time * jitterSpeed * 5.0 + uv.x * 18.0) * chaosAmount * 0.30;
  let wave2 = cos(sliceIndex * 0.71 + time * jitterSpeed * 3.7 + uv.x * 31.0) * chaosAmount * 0.15;
  let wave3 = sin(sliceIndex * 1.13 + time * jitterSpeed * 7.2 + uv.y * 23.0) * chaosAmount * 0.08;
  let totalWave = wave1 + wave2 + wave3;

  // Fractal slice bending with FBM
  let sliceBend = sin(localY * TAU + time * 2.0 + sliceIndex * 0.4 + fbm(vec2<f32>(localY, sliceIndex) + time * 0.3, 4, 2.0, 0.5) * PI) * chaosAmount * 0.18;

  // Audio-reactive fractal zoom on slice displacement
  let fractalDisplacement = (fbmJitter + totalWave + sliceBend * mouseMask) * (1.0 + bass * 0.5);

  let baseUV = clamp(uv + vec2<f32>(fractalDisplacement + qc * chaosAmount * 0.3 * cellEdge, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic aberration with treble-driven multi-layer split
  let splitStrength = colorSplit * (0.4 + mouseMask) * (1.0 + treble * 0.5);
  let splitDir = vec2<f32>(splitStrength, 0.0);

  // Add curl-noise-like rotation to the split direction
  let curlAngle = fbm(uv * 5.0 + time * 0.2, 4, 2.0, 0.5) * PI;
  let rotatedSplit = vec2<f32>(
    splitDir.x * cos(curlAngle) - splitDir.y * sin(curlAngle),
    splitDir.x * sin(curlAngle) + splitDir.y * cos(curlAngle)
  );

  let sampleR = clamp(baseUV + rotatedSplit, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleB = clamp(baseUV - rotatedSplit, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, sampleR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, baseUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, sampleB, 0.0).b
  );

  // Enhanced scan glow with Voronoi cell edges
  let scanGlow = (1.0 - smoothstep(0.15, 0.50, abs(localY - 0.5))) * (0.08 + 0.18 * mids);
  let cellGlow = cellEdge * (0.05 + 0.12 * treble);

  // Dynamic glitch tint based on audio spectrum
  let glitchTint1 = mix(vec3<f32>(0.05, 0.65, 1.0), vec3<f32>(1.0, 0.35, 0.85), treble * 0.6 + mouseMask * 0.25);
  let glitchTint2 = mix(vec3<f32>(1.0, 0.8, 0.1), vec3<f32>(0.2, 1.0, 0.5), bass * 0.7);
  let glitchTint = mix(glitchTint1, glitchTint2, fbm(uv * 3.0 + time * 0.1, 4, 2.0, 0.5));

  finalColor = finalColor + glitchTint * (scanGlow + cellGlow) * (1.0 + bass * 0.4);

  // Fractal sparkle from treble
  let sparkle = hash12(vec2<f32>(gid.xy) + vec2<f32>(time * 10.0, time * 7.0)) * treble * 0.15 * mouseMask;
  finalColor = finalColor + vec3<f32>(sparkle);

  // Alpha: pattern intensity + fractal depth + cell edges
  let finalAlpha = clamp(0.76 + mouseMask * 0.12 + abs(fractalDisplacement) * 1.4 + cellEdge * 0.2, 0.45, 0.98);

  // Depth with Voronoi influence
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, baseUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.25 + scanGlow + mouseMask * 0.25 + cellEdge * 0.15, 0.25 + chaosAmount * 2.0), 0.0, 1.0);

  // Premultiplied alpha writeback
  let premultColor = finalColor * finalAlpha;
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(premultColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(abs(fractalDisplacement), scanGlow + cellGlow, mouseMask, finalAlpha));
}
