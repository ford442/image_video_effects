// ═══════════════════════════════════════════════════════════════════
//  Neon Lotus
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-14
//  Ideas: Nelumbo seed-pod receptacle with carpel pits on a Vogel golden-angle spiral ringed by stamen filaments; lotus-effect water beads rolling along petal midlines and shed at the tips, shaken loose by click pond-ripples
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // x=time, y=rippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Petal Count, y=Bloom, z=Speed, w=Glow Scale
  ripples: array<vec4<f32>, 50>,
};

// ACES filmic tonemap
const TAU: f32 = 6.28318530718;
const GOLDEN_ANGLE: f32 = 2.399963229728653;

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
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

// Lotus petal SDF: teardrop shape in polar coords
fn petalSdf(r: f32, theta: f32, phase: f32, bloom: f32) -> f32 {
  // petal: r ~ cos(theta/2) * bloom
  let petalR = bloom * 0.5 * max(0.0, cos(theta * 0.5 + phase));
  return r - petalR;
}

fn hash1(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453123);
}

// Nelumbo receptacle: flat-topped seed pod whose carpels sit in pits arranged
// on Vogel's golden-angle spiral (r_k = R*sqrt(k/N), a_k = k*GOLDEN_ANGLE),
// ringed by a fringe of stamen filaments. Returns (rgb, coverage).
fn receptacle(p: vec2<f32>, R: f32, nCarpels: i32, t: f32, bass: f32, mids: f32) -> vec4<f32> {
  let r = length(p);
  let disc = smoothstep(R, R * 0.92, r);
  var pits = 0.0;
  var rims = 0.0;
  let spin = t * 0.05;
  let pitR = R * 0.55 / sqrt(f32(nCarpels));
  for (var k = 0; k < nCarpels; k++) {
    let fk = f32(k);
    let rk = R * 0.84 * sqrt((fk + 0.5) / f32(nCarpels));
    let ak = fk * GOLDEN_ANGLE + spin;
    let c = vec2<f32>(cos(ak), sin(ak)) * rk;
    let dk = length(p - c) / pitR;
    pits = max(pits, smoothstep(1.0, 0.6, dk));
    rims = max(rims, exp(-pow((dk - 1.0) * 4.0, 2.0)));
  }
  let podBody = vec3<f32>(0.25, 0.9, 0.35) * (0.35 + 0.25 * mids);
  let pitGlow = vec3<f32>(1.0, 0.85, 0.2) * (0.6 + bass * 0.8);
  var col = podBody * disc * (1.0 - pits * 0.85) + pitGlow * rims * disc * 1.2;
  // Stamen filaments: thin radial threads with anthers at their tips
  let ang = atan2(p.y, p.x);
  let fil = pow(abs(sin(ang * 36.0 + sin(ang * 7.0 + t) * 0.3)), 24.0);
  let stamenLen = R * (1.55 + bass * 0.25);
  let band = smoothstep(R * 0.95, R * 1.05, r) * smoothstep(stamenLen, stamenLen * 0.9, r);
  let anther = exp(-pow((r - stamenLen * 0.93) / (R * 0.06), 2.0)) * smoothstep(0.2, 0.8, fil);
  col += vec3<f32>(1.0, 0.75, 0.25) * (fil * band * 0.9 + anther * 1.4);
  let cover = clamp(disc + fil * band * 0.6 + anther, 0.0, 1.0);
  return vec4<f32>(col, cover);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let t = u.config.x;

  // Audio
  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // Params
  let nPetals   = mix(4.0, 16.0, u.zoom_params.x);
  let bloomAmt  = mix(0.3, 1.0, u.zoom_params.y) * (1.0 + bass * 0.35);
  let speed     = mix(0.1, 0.8, u.zoom_params.z);
  let glowScale = mix(0.5, 2.5, u.zoom_params.w) * (1.0 + mids * 0.25);

  // Mouse: shift center
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p -= mouse * 0.4 * u.zoom_config.w;

  // Click ripples: rings spreading across the pond surface the lotus floats
  // on; the passing swell refracts the view and shakes water beads loose.
  var pondGlow = 0.0;
  var shake = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = t - rp.z;
    if (age >= 0.0 && age < 3.0) {
      let rpos = (rp.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
      let dv = p - rpos;
      let dl = max(length(dv), 1e-4);
      let front = dl - age * 0.7;
      let env = exp(-front * front * 14.0) * exp(-age * 1.1);
      let swell = sin(front * 42.0) * env;
      p += (dv / dl) * swell * 0.012;
      pondGlow += max(swell, 0.0) * 0.6;
      shake += env;
    }
  }

  let r = length(p);
  let theta = atan2(p.y, p.x);

  // Layered lotus: multiple rings of petals
  var col = vec3<f32>(0.0);
  var totalGlow = 0.0;
  var coverage = 0.0;
  var beadDepth = 0.0;

  let nLayers = 3u;
  for (var layer = 0u; layer < nLayers; layer++) {
    let lf = f32(layer);
    let layerScale = 1.0 - lf * 0.3;
    let layerR = r / layerScale;
    let layerT = theta + lf * GOLDEN_ANGLE + t * speed * (1.0 - lf * 0.2);
    let nP = nPetals + lf * 4.0;
    let petalAngle = 6.28318 / nP;
    let sector = floor(layerT / petalAngle + 0.5);
    let localTheta = layerT - sector * petalAngle;
    let phase = sector * 0.1;
    let bloom = bloomAmt * layerScale * (0.8 + 0.2 * sin(t * 0.5 + lf));
    let sdf = petalSdf(layerR, localTheta, phase, bloom);
    let petalMask = smoothstep(0.02, -0.02, sdf);
    let hue = fract(lf * 0.33 + t * 0.05 + bass * 0.15 + sector * 0.07);
    let petalColor = vec3<f32>(
      0.5 + 0.5 * cos(6.2832 * hue),
      0.5 + 0.5 * cos(6.2832 * (hue + 0.33)),
      0.5 + 0.5 * cos(6.2832 * (hue + 0.67))
    );
    let edgeGlow = exp(-abs(sdf) * 30.0) * glowScale * (1.0 + treble * 0.4);
    let vein = exp(-abs(localTheta) * 26.0) * petalMask;
    col += petalColor * (petalMask * 0.7 + edgeGlow * 0.8 + vein * 0.55);
    totalGlow += edgeGlow;
    coverage = max(coverage, petalMask);

    // Lotus effect: the superhydrophobic papillae keep water beaded, so drops
    // roll down the midline groove toward the petal tip and fly off there.
    // Petal tilt (Speed) sets roll rate; pond swell jolts them forward.
    let seed = sector * 7.13 + lf * 31.7;
    let petalLen = max(bloom * 0.5 * cos(phase), 1e-3);
    let roll = fract(hash1(seed) + t * speed * (0.25 + 0.3 * hash1(seed + 3.0)) + shake * 0.15);
    let beadPos = vec2<f32>(mix(0.15, 1.0, roll) * petalLen, sin(t * 23.0 + seed) * shake * 0.004);
    let beadLocal = vec2<f32>(layerR * cos(localTheta), layerR * sin(localTheta));
    let beadR = (0.010 + 0.008 * hash1(seed + 9.0)) * (1.0 - smoothstep(0.8, 1.0, roll) * 0.7);
    let bd = length(beadLocal - beadPos) * layerScale / beadR;
    let beadBody = smoothstep(1.0, 0.8, bd) * petalMask;
    let beadRim = exp(-pow((bd - 0.9) * 6.0, 2.0)) * beadBody;
    let glint = exp(-length((beadLocal - beadPos) * layerScale / beadR - vec2<f32>(-0.35, -0.35)) * 9.0) * beadBody;
    col = mix(col, col * 0.55 + petalColor * 0.25, beadBody * 0.6);
    col += vec3<f32>(0.75, 0.95, 1.0) * (beadRim * 0.5 * glowScale + glint * (1.2 + treble * 1.5));
    beadDepth = max(beadDepth, beadBody);
  }

  // Stamens at center
  let centerDist = smoothstep(0.08, 0.0, r) * (1.0 + bass * 0.5);
  let nCarpels = 8 + i32(u.zoom_params.x * 16.0);
  let pod = receptacle(p, 0.06 + 0.04 * u.zoom_params.y, nCarpels, t, bass, mids);
  let centerHue = fract(t * 0.1 + mids * 0.2);
  let centerColor = vec3<f32>(
    0.5 + 0.5 * cos(6.2832 * centerHue),
    0.5 + 0.5 * cos(6.2832 * (centerHue + 0.33)),
    0.5 + 0.5 * cos(6.2832 * (centerHue + 0.67))
  );
  col += centerColor * centerDist * 0.6;
  col = mix(col, col * 0.4 + pod.rgb * glowScale * 0.8, pod.a);
  coverage = max(coverage, pod.a);

  // Pond swell light
  col += vec3<f32>(0.3, 0.7, 1.0) * pondGlow * glowScale;

  // Fine noise shimmer on treble
  let shimmer = noise2d(p * 40.0 + vec2<f32>(t * 0.5)) * treble * 0.08;
  col += shimmer;

  // Vignette
  col *= 1.0 - smoothstep(0.8, 1.5, r);

  // Tonemap (single ACES pass on the display colour)
  let display = aces(max(col, vec3<f32>(0.0)) * 1.1);

  // Alpha: flower coverage (petals, receptacle) plus edge glow and pond swell
  let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(coverage * 0.75 + min(totalGlow, 1.0) * 0.15 + luma * 0.25 + pondGlow * 0.2, 0.02, 1.0);

  // Depth: dome of the flower, beads and receptacle sit proud
  let depth = clamp(1.0 - r * 0.6 + beadDepth * 0.08 + pod.a * 0.1, 0.0, 1.0);

  let finalColor = vec4<f32>(display, alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
