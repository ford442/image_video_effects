// ═══════════════════════════════════════════════════════════════════
//  Morphogenic Resonance
//  Category: generative
//  Features: generative, audio-reactive, temporal, chromatic, mouse-driven
//  Complexity: High
//  Description: Organic shapes morph between geometric and biological
//               forms via sinusoidal interpolation. Bass drives morph
//               speed, mids add surface ripple resonance, treble
//               creates edge discharge. Mouse warps the morph field.
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

const PI = 3.14159265;
const TAU = 6.2831853;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v += a * noise2(p * f);
    a *= 0.5;
    f *= 2.03;
  }
  return v;
}

// SDF for a polygon (geometric form)
fn sdPolygon(p: vec2<f32>, n: f32, r: f32) -> f32 {
  let angle = atan2(p.y, p.x);
  let sector = TAU / n;
  let a = abs(fract(angle / sector + 0.5) - 0.5) * sector;
  let d = length(p);
  let polyDist = cos(a) * d - r;
  return polyDist;
}

// SDF for organic blob (biological form)
fn sdOrganic(p: vec2<f32>, time: f32, seed: f32) -> f32 {
  let n1 = noise2(p * 3.0 + vec2<f32>(time * 0.3 + seed, seed));
  let n2 = noise2(p * 5.0 - vec2<f32>(seed, time * 0.2));
  let d = length(p) - 0.25 - n1 * 0.08 - n2 * 0.04;
  return d;
}

// Morph field value
fn morphField(uv: vec2<f32>, time: f32, morphSpeed: f32, geoBias: f32) -> f32 {
  let t = time * morphSpeed;
  let morphPhase = sin(t) * 0.5 + 0.5;
  let phase = mix(morphPhase, smoothstep(0.0, 1.0, morphPhase), geoBias);

  // Grid of shapes
  let gridScale = 3.0 + geoBias * 2.0;
  let gp = uv * gridScale;
  let cell = floor(gp);
  let local = fract(gp) - 0.5;

  let seed = hash21(cell);
  let nSides = 3.0 + floor(seed * 5.0);
  let rotAngle = seed * TAU + t * 0.2;
  let c = cos(rotAngle);
  let s = sin(rotAngle);
  let rotLocal = vec2<f32>(c * local.x - s * local.y, s * local.x + c * local.y);

  let geoDist = sdPolygon(rotLocal, nSides, 0.22 + seed * 0.08);
  let bioDist = sdOrganic(local, t, seed);

  // Sinusoidal interpolation between forms
  let interp = phase + geoBias * 0.3;
  let smoothInterp = interp * interp * (3.0 - 2.0 * interp);
  var dist = mix(geoDist, bioDist, smoothInterp);

  // Add internal vein structure when biological
  if (smoothInterp > 0.4) {
    let veinNoise = fbm2(local * 8.0 + vec2<f32>(t * 0.1), 3);
    let vein = smoothstep(0.35, 0.45, veinNoise) * smoothstep(0.65, 0.55, veinNoise);
    dist = dist - vein * 0.03 * smoothInterp;
  }

  return dist;
}

fn hueShiftRGB(hue: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
  return clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
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
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv01 = vec2<f32>(gid.xy) / res;
  let uv = (vec2<f32>(gid.xy) / res - 0.5) * vec2<f32>(res.x / res.y, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let morphSpeed = u.zoom_params.x * 2.0 + 0.2;
  let geoBias = u.zoom_params.y;
  let rippleIntensity = u.zoom_params.z * 2.0;
  let colorShift = u.zoom_params.w;

  // Mouse warps the morph field
  let mouseDist = length(uv - mouse);
  let mouseWarp = exp(-mouseDist * mouseDist * 8.0) * 0.15;
  var warpedUV = uv;
  warpedUV += normalize(uv - mouse + 0.001) * mouseWarp;

  // Calculate morph field
  var dist = morphField(warpedUV, time, morphSpeed, geoBias);

  // Bass-driven morph acceleration (temporal warp)
  let bassWarp = sin(uv.x * 10.0 + time * morphSpeed * (1.0 + bass * 2.0)) * bass * 0.03;
  dist += bassWarp;

  // Mids add surface ripple resonance
  let ripple = sin(length(warpedUV) * 30.0 - time * 3.0 * (1.0 + mids)) * mids * rippleIntensity * 0.02;
  dist += ripple;

  // Shape edge glow
  let edge = 1.0 - smoothstep(-0.02, 0.04, dist);
  let interior = 1.0 - smoothstep(0.0, 0.06, dist);

  // Treble creates edge discharge
  let discharge = treble * hash21(uv * 100.0 + time * 10.0) * edge * 2.0;

  // Color based on morph phase and audio
  let hue = colorShift + bass * 0.1 + interior * 0.15 + time * 0.02;
  var col = hueShiftRGB(hue);

  // Geometric forms lean toward cyan/blue, biological toward warm organic
  let geoColor = vec3<f32>(0.3, 0.7, 0.9);
  let bioColor = vec3<f32>(0.9, 0.5, 0.3);
  let morphPhase = sin(time * morphSpeed) * 0.5 + 0.5;
  let formColor = mix(geoColor, bioColor, morphPhase);
  col = mix(col, formColor, 0.4);

  // Interior fill with organic texture
  let interiorTex = fbm2(warpedUV * 6.0 + time * 0.1, 4) * interior;
  col += vec3<f32>(0.1, 0.2, 0.15) * interiorTex;

  // Edge glow and discharge
  col += vec3<f32>(0.6, 0.8, 1.0) * edge * (0.5 + treble);
  col += vec3<f32>(1.0, 0.9, 0.7) * discharge;

  // Chromatic dispersion: R/G/B channel offsets per element
  let cOffset = 0.004 + treble * 0.006;
  let cDir = normalize(warpedUV + 0.001);
  let rOff = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cOffset * 1.2, 0.0).r;
  let gOff = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cOffset * 0.8, 0.0).g;
  let bOff = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cOffset * 1.0, 0.0).b;

  // Temporal feedback
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
  var fbCol = mix(col, prev.rgb * 0.92, 0.04 + bass * 0.02);

  // Blend chromatic offsets
  fbCol.r = mix(fbCol.r, rOff * 0.92, 0.03 + treble * 0.02);
  fbCol.g = mix(fbCol.g, gOff * 0.92, 0.03 + mids * 0.02);
  fbCol.b = mix(fbCol.b, bOff * 0.92, 0.03 + bass * 0.02);

  // Semantic alpha: based on edge presence and interior density
  let alpha = clamp(edge * 0.9 + interior * 0.6 + discharge * 0.3, 0.0, 1.0);

  // Depth based on morph field distance
  let depth = clamp(0.5 + dist * 2.0 + interiorTex * 0.2, 0.0, 1.0);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  fbCol = vec3<f32>(fbCol.r + caStr, fbCol.g, fbCol.b - caStr * 0.5);

  fbCol = acesToneMap(fbCol * 1.1);
  textureStore(writeTexture, gid.xy, vec4<f32>(fbCol, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(fbCol, alpha));
}
