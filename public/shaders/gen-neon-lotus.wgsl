// ═══════════════════════════════════════════════════════════════════
//  Neon Lotus
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, interactive
//  Complexity: Medium
//  Created: 2026-05-30
//  Upgraded: 2026-07-13
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1(petalCount), y=Param2(bloom), z=Param3(speed), w=Param4(glow)
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;
const TAU: f32 = 6.2831853;

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn noise2d(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
  return v * mix(vec3<f32>(k.x), clamp(p - vec3<f32>(k.x), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

// Lotus petal SDF: teardrop shape in polar coords
fn petalSdf(r: f32, theta: f32, phase: f32, bloom: f32) -> f32 {
  let petalR = bloom * 0.5 * max(0.0, cos(theta * 0.5 + phase));
  return r - petalR;
}

fn envelope(prev: f32, goal: f32, attack: f32, release: f32) -> f32 {
  let delta = goal - prev;
  let coeff = select(release, attack, delta > 0.0);
  return prev + delta * coeff;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let t = u.config.x;

  // Raw audio bands from the plasma buffer
  let rawBass   = plasmaBuffer[0].x;
  let rawMids   = plasmaBuffer[0].y;
  let rawTreble = plasmaBuffer[0].z;

  // Audio envelope followers: single-threaded state update for smooth attack/release
  let dt = 0.016;
  let attack  = 1.0 - exp(-dt * 22.0);
  let release = 1.0 - exp(-dt * 3.5);
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[0] = envelope(extraBuffer[0], rawBass,   attack, release);
    extraBuffer[1] = envelope(extraBuffer[1], rawMids,   attack, release);
    extraBuffer[2] = envelope(extraBuffer[2], rawTreble, attack, release);
    let clicks = u.config.y;
    if (clicks > extraBuffer[4]) {
      extraBuffer[5] = t;
    }
    extraBuffer[4] = clicks;
  }
  let bass   = extraBuffer[0];
  let mids   = extraBuffer[1];
  let treble = extraBuffer[2];
  let shockTime = extraBuffer[5];
  let shockAge = t - shockTime;

  // Params
  let nPetals   = mix(4.0, 20.0, u.zoom_params.x);
  let bloomAmt  = mix(0.3, 1.1, u.zoom_params.y) * (1.0 + bass * 0.5);
  let speed     = mix(0.1, 0.9, u.zoom_params.z);
  let glowScale = mix(0.5, 3.0, u.zoom_params.w) * (1.0 + mids * 0.35);

  // Mouse: shift center + gravity-well attraction
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

  let toMouse = mouse - p;
  let distMouse = length(toMouse);
  let gravityStrength = 0.35 / (1.0 + distMouse * 3.0);
  p += toMouse * gravityStrength * u.zoom_config.w;
  p -= mouse * 0.2 * u.zoom_config.w;

  let r = length(p);
  let theta = atan2(p.y, p.x);

  // Click-triggered shockwave expanding from the lotus center
  var shock = 0.0;
  if (shockAge >= 0.0 && shockAge < 2.5) {
    let swR = shockAge * 1.5;
    let ring = abs(r - swR);
    shock = exp(-ring * 22.0) * exp(-shockAge * 1.2) * 1.6;
  }

  // Video input samples for luma/depth keyed particle spawn
  let video = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let videoLuma = dot(video, vec3<f32>(0.299, 0.587, 0.114));
  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Layered lotus
  var col = vec3<f32>(0.0);
  var totalGlow = 0.0;
  var edgeMask = 0.0;

  let nLayers = 4u;
  for (var layer = 0u; layer < nLayers; layer++) {
    let lf = f32(layer);
    let layerScale = 1.0 - lf * 0.22;
    let layerR = r / layerScale;
    let layerT = theta + lf * 0.35 + t * speed * (1.0 - lf * 0.15);
    let nP = nPetals + lf * 5.0;
    let petalAngle = TAU / nP;
    let sector = floor(layerT / petalAngle + 0.5);
    let localTheta = layerT - sector * petalAngle;
    let phase = sector * 0.08 + lf * 0.2;
    let bloom = bloomAmt * layerScale * (0.8 + 0.2 * sin(t * 0.4 + lf));
    let sdf = petalSdf(layerR, localTheta, phase, bloom);
    let petalMask = smoothstep(0.025, -0.025, sdf);
    edgeMask += exp(-abs(sdf) * 40.0) * layerScale;

    // Prismatic hue per layer; mids drive hue-shift speed
    let hue = fract(lf * 0.28 + t * 0.07 * (1.0 + mids * 2.0) + bass * 0.12 + sector * 0.06);
    let petalColor = hsv2rgb(hue, 0.85, 1.0);

    // Treble-driven edge sparkle
    let sparkle = hash3(vec3<f32>(p * 300.0, t * 8.0 + sector));
    let edgeSparkle = step(0.96 - treble * 0.08, sparkle) * treble * 2.0;
    let edgeGlow = exp(-abs(sdf) * 28.0) * glowScale * (1.0 + treble * 0.6 + edgeSparkle);

    // Shockwave briefly intensifies petals
    let layerShock = shock * (1.0 - lf * 0.15);

    col += petalColor * (petalMask * 0.7 + edgeGlow * 0.9 + layerShock * 0.5);
    totalGlow += edgeGlow;
  }

  // Luma + depth keyed particle spawn around petal edges
  let lumaKey = smoothstep(0.35, 0.65, videoLuma);
  let depthKey = smoothstep(0.2, 0.7, depthVal);
  let particleSeed = hash3(vec3<f32>(uv * 250.0, t * 3.0));
  let particleBurst = step(0.97 - treble * 0.05, particleSeed) * lumaKey * depthKey;
  let particleColor = hsv2rgb(fract(t * 0.15 + treble * 0.2), 0.9, 1.0);
  col += particleColor * particleBurst * edgeMask * 3.0 * (1.0 + shock);

  // Stamens at center
  let centerDist = smoothstep(0.1, 0.0, r) * (1.0 + bass * 0.6);
  let centerHue = fract(t * 0.12 + mids * 0.25);
  let centerColor = hsv2rgb(centerHue, 0.9, 1.0);
  col += centerColor * centerDist * 1.8;

  // Fine noise shimmer on treble
  let shimmer = noise2d(p * 45.0 + vec2<f32>(t * 0.7)) * treble * 0.1;
  col += shimmer;

  // Temporal feedback: brief neon trails from previous frame
  let trailAngle = t * 0.08 * speed;
  let trailUv = uv + vec2<f32>(sin(trailAngle), cos(trailAngle)) * 0.0035 * speed;
  let prevFrame = textureSampleLevel(dataTextureC, u_sampler, trailUv, 0.0).rgb;
  col = max(col, prevFrame * 0.88);

  // Vignette
  col *= 1.0 - smoothstep(0.75, 1.4, r);

  // Tonemap
  col = aces(col);

  // Alpha: luminance-driven, rich from center and glow
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.9 + centerDist * 0.2 + totalGlow * 0.15, 0.0, 1.0);

  // Depth
  let depth = clamp(1.0 - r * 0.55 + bass * 0.1, 0.0, 1.0);

  let finalColor = vec4<f32>(col, alpha);

  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
