// ═══════════════════════════════════════════════════════════════════
//  Supernova Remnant
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic, depth-aware
//  Complexity: Very High
//  Description: Expanding supernova shockwave with turbulent ejecta filaments.
//               Bass drives the expansion front, mids create Rayleigh-Taylor
//               instability fingers, treble adds radioactive decay sparkles.
//               Mouse pulls the remnant center.
//  Created: 2026-05-30
//  Upgraded: 2026-07-22 (Visualist pass: blackbody thermal aging, click
//            detonations via ripples[], inertial bass momentum kicks)
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

fn hash21(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 5; i++) {
    v += a * noise(pp);
    a *= 0.5;
    pp *= 2.03;
  }
  return v;
}

// Polar coordinates with turbulence
fn turbulentPolar(uv: vec2<f32>, t: f32, turbulence: f32) -> vec2<f32> {
  let r = length(uv);
  let a = atan2(uv.y, uv.x);
  let turb = fbm(vec2<f32>(r * 3.0, a * 2.0) + t * 0.2) * turbulence;
  return vec2<f32>(r, a + turb);
}

// Blackbody-style thermal aging ramp:
//   t = 0 -> white-hot young shock shell
//   t = 1 -> deep-red cooled ember of the old remnant
fn blackbodyRamp(t: f32) -> vec3<f32> {
  let whiteHot = vec3<f32>(1.00, 0.96, 0.88);
  let orange   = vec3<f32>(1.00, 0.52, 0.12);
  let deepRed  = vec3<f32>(0.42, 0.05, 0.02);
  var c = mix(whiteHot, orange, smoothstep(0.0, 0.45, t));
  c = mix(c, deepRed, smoothstep(0.45, 1.0, t));
  return c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv01 = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mousePos = vec2<f32>(mouse.x * aspect, mouse.y);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let expansionRate    = mix(0.1, 1.0, u.zoom_params.x);
  let filamentTurb     = mix(0.0, 2.0, u.zoom_params.y);
  let shockDensity     = mix(0.5, 3.0, u.zoom_params.z);
  let decaySparkle     = mix(0.0, 1.5, u.zoom_params.w);

  // Mouse pulls the remnant center
  let center = mousePos * 0.3;
  let relUV = uv - center;

  // ═══ Inertial thermal-age accumulator ═══
  // Age lives in dataTextureA alpha and is read back (smoothed by the
  // sampler) from last frame's copy in dataTextureC. Bass nudges the
  // accumulator instead of rescaling expansion, so kicks feel like
  // momentum injected into the blast wave rather than a zoom.
  let prevAge = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).a;
  var age = prevAge + expansionRate * 0.0016;
  age = age + bass * bass * 0.012 * expansionRate;
  age = fract(age);
  let shockRadius = age * 0.8;

  // ═══ Click detonation: secondary expanding shock fronts ═══
  // Each mouse-down spawns its own ring that expands from the click
  // point and perturbs the main shock shell as it sweeps past.
  var detonate = 0.0;
  var detonateGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let elapsed = time - rp.z;
    if (rp.z > 0.0 && elapsed > 0.0 && elapsed < 4.0) {
      let clickPos = (rp.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
      let cd = length(uv - clickPos);
      let frontR = elapsed * 0.55;
      let dBand = (cd - frontR) * 16.0;
      let band = exp(-dBand * dBand);
      let fade = exp(-elapsed * 1.2);
      detonate = detonate + band * fade;
      detonateGlow = detonateGlow + exp(-cd * cd * 30.0) * exp(-elapsed * 3.0);
    }
  }

  // The detonation front displaces the main shell where it passes through.
  let shellRadius = shockRadius + detonate * 0.05;

  // Polar turbulence
  let tp = turbulentPolar(relUV, time, filamentTurb);
  let r = tp.x;
  let a = tp.y;

  // Shockwave front
  let shockWidth = 0.03 + bass * 0.02;
  let shockDist = abs(r - shellRadius);
  let shockFront = exp(-shockDist * shockDist / (shockWidth * shockWidth));

  // Rayleigh-Taylor instability fingers (mids)
  let fingers = fbm(vec2<f32>(a * 8.0, r * 10.0) + mids * 2.0) * mids;
  let fingerMask = exp(-abs(r - shellRadius * 0.7) * 5.0);
  let rtInstability = fingers * fingerMask;

  // Ejecta filaments
  let filamentNoise = fbm(vec2<f32>(cos(a) * 3.0, sin(a) * 3.0) + time * 0.1);
  let filamentMask = exp(-abs(r - shellRadius * (0.5 + filamentNoise * 0.3)) * 8.0);
  let filaments = filamentMask * shockDensity;

  // Inner core glow
  let coreGlow = exp(-r * r * 10.0) * (1.0 - age * 0.5);

  // ═══ Chromatic shell: different effective radius per channel ═══
  let rR = r + bass * 0.01;
  let rG = r + mids * 0.015;
  let rB = r + treble * 0.008;

  let shellR = exp(-abs(rR - shellRadius) * 12.0);
  let shellG = exp(-abs(rG - shellRadius) * 12.0);
  let shellB = exp(-abs(rB - shellRadius) * 12.0);

  // ═══ Blackbody thermal aging of the shell colors ═══
  // The young remnant burns white-hot and cools through orange into a
  // deep-red ember as the inertial age accumulator grows. The core is
  // denser and cools more slowly, so it uses a stretched ramp.
  let shellCol = blackbodyRamp(age);
  let coreCol = blackbodyRamp(age * 0.4);

  var col = vec3<f32>(0.0);
  col.r = shellR * shellCol.r * 1.2 + rtInstability * shellCol.r * 0.8 + coreGlow * coreCol.r * 1.5;
  col.g = shellG * shellCol.g * 1.1 + rtInstability * shellCol.g * 0.6 + coreGlow * coreCol.g * 0.8;
  col.b = shellB * shellCol.b * 1.4 + filaments * shellCol.b * 0.9 + coreGlow * coreCol.b * 0.4;

  // Click detonation energy: blue-white secondary shock ring plus a hot
  // flash blooming at the detonation origin.
  col += vec3<f32>(0.75, 0.85, 1.0) * detonate * 1.2;
  col += vec3<f32>(1.0, 0.9, 0.7) * detonateGlow * 2.0;

  // Radioactive decay sparkles (treble)
  let sparkleNoise = hash21(vec2<f32>(floor(relUV * 50.0) + time * 5.0));
  let sparkle = step(0.98 - treble * 0.05, sparkleNoise) * treble * decaySparkle;
  let sparkleGlow = exp(-r * r * 3.0) * sparkle;
  col += vec3<f32>(0.9, 0.95, 1.0) * sparkleGlow;

  // ═══ Temporal feedback with chromatic dispersion ═══
  let cStr = 0.003 + bass * 0.005;
  let cDir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));

  let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (1.0 + mids), 0.0).r;
  let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (0.5 + treble), 0.0).g;
  let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cStr * (0.8 + bass * 0.5), 0.0).b;
  let prevCol = vec3<f32>(prevR, prevG, prevB);
  col = mix(col, prevCol * 0.92, 0.15 + bass * 0.03);

  // Alpha based on total energy
  let energy = shockFront + rtInstability + filaments + coreGlow + sparkleGlow + detonate;
  let alpha = clamp(energy * 0.8, 0.0, 1.0);

  // Depth based on radial distance and alpha
  let depthVal = clamp(1.0 - r * 1.5, 0.0, 1.0) * alpha;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  // RGB keeps the color trail for feedback; alpha carries the age accumulator.
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col, age));
}
