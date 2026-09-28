// ═══════════════════════════════════════════════════════════════════
//  Celestial Weave
//  Category: generative
//  Features: procedural, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-09-27
//  Ideas: shimmer-driven traveling thread glint; void-depth star parallax; constellation pulse-travel timed to bass
//  A packing: display RGBA
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

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(31.2, 13.6)));
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * noise2(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = sat(dot(pa, ba) / dot(ba, ba));
  return length(pa - ba * h);
}

fn starGlow(d: f32, r: f32) -> f32 {
  let core = exp(-d * d / (r * r));
  let halo = smoothstep(r * 4.0, r * 0.5, d);
  return core + halo * 0.5;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
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
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  // Clamp/normalize parameter vector
  let zp_x = u.zoom_params.x;
  let zp_y = u.zoom_params.y;
  let zp_z = u.zoom_params.z;
  let zp_w = u.zoom_params.w;
  let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));

  // ═══ CHUNK: bass_env smoothing (replaces raw-bass strobing) ═══
  let prevBass = extraBuffer[0];
  let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[0] = smoothBass;
  }

  let weaveScale = mix(3.0, 30.0, u.zoom_params.x);
  let twist = mix(0.0, 2.5, u.zoom_params.y);
  let glowAmp = mix(0.2, 2.0, u.zoom_params.z);
  let voidDepth = mix(0.1, 1.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * 0.2;

  // ═══ FBM domain warp for organic weave flow ═══
  let warp = vec2<f32>(
    fbm(p * 2.0 + vec2<f32>(time * 0.11, 0.0), 4),
    fbm(p * 2.0 + vec2<f32>(5.2, 1.3) - time * 0.13, 4)
  );
  let warpedP = p + (warp - 0.25) * 0.45;

  let ang = twist * sin(time * 0.5 + length(p) * 2.0);
  let ca = cos(ang);
  let sa = sin(ang);
  let rp = vec2<f32>(ca * warpedP.x - sa * warpedP.y, sa * warpedP.x + ca * warpedP.y);

  let weftPhase = rp.x * weaveScale + time * (0.8 + smoothBass);
  let warpPhase = rp.y * weaveScale * (0.9 + mids * 0.2) - time * 0.7;
  let weft = sin(weftPhase);
  let warpWave = sin(warpPhase);
  let knot = smoothstep(0.7, 1.0, abs(weft * warpWave));
  let fiber = smoothstep(0.92, 1.0, max(abs(weft), abs(warpWave)));

  // Idea: shimmer-driven traveling thread glint — a bright point riding each
  // thread's own already-moving phase, scaled by the Shimmer-derived glowAmp.
  let glintWeft = pow(sat(sin(weftPhase)), 48.0);
  let glintWarp = pow(sat(sin(warpPhase)), 48.0);
  let threadGlint = (glintWeft + glintWarp) * fiber * glowAmp;

  // ═══ Procedural star field with stochastic positions ═══
  let starUV = uv + vec2<f32>(time * 0.008, 0.0);
  let starGrid = floor(starUV * 240.0);
  let starNoise = hash21(starGrid);
  let starThreshold = 0.997 - treble * 0.02;
  let starRaw = step(starThreshold, starNoise);
  // Idea: void-depth star parallax — near stars (low hash) render bigger, brighter
  // and drift a touch faster than far stars, scaled by the Void Depth param.
  let starDepthHash = hash21(starGrid + vec2<f32>(4.0, 5.0));
  let nearness = mix(1.7, 0.5, starDepthHash) * mix(1.0, 1.8, voidDepth);
  let parallaxJitter = sin(time * 0.2 * nearness + starNoise * 17.0) * 0.0025 * voidDepth * nearness;
  let starOffset = hash22(starGrid) * 0.4 + vec2<f32>(parallaxJitter, parallaxJitter * 0.6);
  let starPos = (starGrid + vec2<f32>(0.5) + starOffset) / 240.0;
  let starRadius = mix(0.0012, 0.0040, hash21(starGrid + vec2<f32>(1.0, 2.0))) * nearness;
  let dToStar = length(uv - starPos);
  let starTwinkle = 0.5 + 0.5 * sin(time * 15.0 + starNoise * 31.0);
  let starGlowVal = starGlow(dToStar, starRadius) * starRaw * (0.5 + starTwinkle) * nearness;

  // ═══ Constellation connection lines between neighboring stars ═══
  var constellation = 0.0;
  var constellationPulse = 0.0;
  for (var dy: i32 = -2; dy <= 2; dy = dy + 1) {
    for (var dx: i32 = -2; dx <= 2; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let nGrid = starGrid + vec2<f32>(f32(dx), f32(dy));
      let nNoise = hash21(nGrid);
      if (nNoise < starThreshold) { continue; }
      let nPos = (nGrid + vec2<f32>(0.5) + hash22(nGrid) * 0.4) / 240.0;
      let linkChance = hash21(starGrid + nGrid + vec2<f32>(3.1, 7.4));
      let link = smoothstep(0.55, 0.0, linkChance) * starRaw;
      let lineDist = sdSegment(uv, starPos, nPos);
      constellation = constellation + smoothstep(0.0025, 0.0003, lineDist) * link;

      // Idea: constellation pulse-travel — a light pulse runs along each link,
      // timed to the smoothed bass, using the segment's own along-length fraction.
      let ba = nPos - starPos;
      let along = sat(dot(uv - starPos, ba) / max(dot(ba, ba), 0.000001));
      let travelPos = fract(along - time * 0.6 - linkChance * 4.0);
      let pulseGate = smoothstep(0.12, 0.0, abs(travelPos - 0.5));
      constellationPulse = constellationPulse + pulseGate * link * smoothstep(0.0018, 0.0002, lineDist) * smoothBass;
    }
  }

  // Chromatic weave + stellar glow
  let starHue = hash21(starGrid + vec2<f32>(2.0, 3.0));
  let starCol = palette(starHue,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.0, 0.33, 0.67)
  );

  var color = vec3<f32>(0.01, 0.02, 0.05) * (1.0 - voidDepth * 0.7);
  color = color + vec3<f32>(0.35, 0.15, 0.75) * fiber * (1.0 + treble * 0.2);
  color = color + vec3<f32>(0.95, 0.35, 0.75) * knot * glowAmp * (1.0 + smoothBass * 0.15);
  color = color + starCol * starGlowVal * glowAmp * (0.6 + treble);
  color = color + vec3<f32>(0.75, 0.95, 1.0) * constellation * glowAmp * (0.5 + mids * 0.3);
  color = color + vec3<f32>(1.0, 0.95, 0.8) * threadGlint;
  color = color + vec3<f32>(0.6, 0.85, 1.0) * constellationPulse * glowAmp;

  // Temporal persistence: star trails and weave memory — exact texel read, no filtering.
  let prev = textureLoad(dataTextureC, coord, 0);
  color = mix(color, prev.rgb * 0.9, 0.03 + mids * 0.01);

  color = acesToneMap(color * 1.1);

  // Semantic alpha: coverage of fiber/knot/star/constellation structure over the void.
  let alpha = sat(fiber * 0.5 + knot * 0.35 + starGlowVal * 0.4 + constellation * 0.3 + threadGlint * 0.3 + 0.08);
  // Truthful relief: brighter thread/knot structure reads as nearer (lower depth).
  let depthVal = sat(1.0 - (fiber * 0.55 + knot * 0.45) - voidDepth * 0.15);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
