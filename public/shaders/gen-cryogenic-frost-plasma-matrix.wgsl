// ----------------------------------------------------------------
// Cryogenic Frost-Plasma Matrix
// Category: generative
// ----------------------------------------------------------------
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            volumetric-fog, KIFS-fractal, thermal-plasma, ice-refractive,
//            upgraded-rgba
// ----------------------------------------------------------------
//  Uniforms (std140):
//    u.config        : vec4(time, audioLevel, resolution.x, resolution.y)
//    u.zoom_config   : vec4(zoom, mouseX, mouseY, unused)
//    u.zoom_params   : vec4(param0, param1, param2, param3) – UI sliders
//    u.ripples       : array<vec4<f32>, 50>
// ----------------------------------------------------------------

struct Uniforms {
  config      : vec4<f32>,
  zoom_config : vec4<f32>,
  zoom_params : vec4<f32>,
  ripples     : array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler                : sampler;
@group(0) @binding(1) var readTexture              : texture_2d<f32>;
@group(0) @binding(2) var writeTexture             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u               : Uniforms;
@group(0) @binding(4) var readDepthTexture         : texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler    : sampler;
@group(0) @binding(6) var writeDepthTexture        : texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC             : texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer : array<f32>;
@group(0) @binding(11) var comparison_sampler      : sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer : array<vec4<f32>>;

// ═══════════════════════════════════════════════════════════════
//  CONSTANTS  (workgroup-size = 16×16×1 in .json)
// ═══════════════════════════════════════════════════════════════
const PI            : f32 = 3.14159265358979323846;
const MAX_STEPS     : i32 = 80;
const MAX_DIST      : f32 = 40.0;
const SURF_DIST     : f32 = 0.0015;

// ═══════════════════════════════════════════════════════════════
//  MATH HELPERS
// ═══════════════════════════════════════════════════════════════
fn rot(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn bass_env(prev: f32, curr: f32, att: f32, rel: f32) -> f32 {
  if(curr > prev) { return mix(prev, curr, att); }
  else { return mix(prev, curr, rel); }
}

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(mix(hash3(i + vec3<f32>(0,0,0)), hash3(i + vec3<f32>(1,0,0)), f.x),
        mix(hash3(i + vec3<f32>(0,1,0)), hash3(i + vec3<f32>(1,1,0)), f.x), f.y),
    mix(mix(hash3(i + vec3<f32>(0,0,1)), hash3(i + vec3<f32>(1,0,1)), f.x),
        mix(hash3(i + vec3<f32>(0,1,1)), hash3(i + vec3<f32>(1,1,1)), f.x), f.y),
    f.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for(var i = 0; i < 5; i++) {
    v += a * noise3(pp);
    pp = pp * 2.03 + vec3<f32>(1.7, 3.1, 5.3);
    a *= 0.5;
  }
  return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

// ═══════════════════════════════════════════════════════════════
//  KIFS FRACTAL
// ═══════════════════════════════════════════════════════════════
fn kIFS(p: vec3<f32>, time: f32, complexity: f32) -> f32 {
  var z = p;
  var dr = 1.0;
  let scale = mix(2.0, 2.5, complexity);
  let iterations = i32(mix(4.0, 8.0, complexity));

  for(var i = 0; i < iterations; i++) {
    z = abs(z);
    if(z.x + z.y < 0.0) { let t = -z.y; z.y = z.x; z.x = t; }
    if(z.x + z.z < 0.0) { let t = -z.z; z.z = z.x; z.x = t; }
    if(z.y + z.z < 0.0) { let t = -z.z; z.z = z.y; z.y = t; }
    z = z * scale - vec3<f32>(1.0, 1.0, 1.0) * (scale - 1.0);
    dr = dr * scale;
  }
  return length(z) / abs(dr);
}

// ═══════════════════════════════════════════════════════════════
//  SDF SCENE
// ═══════════════════════════════════════════════════════════════
struct MapResult {
  d: f32,
  mat: f32,   // 0 = ice, 1 = plasma
  glow: f32,
};

fn map(p: vec3<f32>, time: f32, fracture: f32, plasmaHeat: f32,
       iceDensity: f32, audio: f32) -> MapResult {
  // Domain distortion from audio
  let warp = fbm(p * 0.5 + time * 0.1) * fracture * audio;
  let pp = p + vec3<f32>(warp, warp * 0.7, warp * 0.3);

  // KIFS ice structure
  let kDist = kIFS(pp * iceDensity, time, 0.6) * 0.3;

  // Plasma core inside
  let plasmaDist = length(pp * 0.4) - 0.3 * plasmaHeat;
  let plasmaGlow = 1.0 / (1.0 + plasmaDist * plasmaDist * 10.0);

  // Combine: ice shell with plasma interior
  let totalDist = smin(kDist, plasmaDist + 0.5, 0.3);

  var mat = 0.0;
  if(plasmaDist < kDist) { mat = 1.0; }

  return MapResult(totalDist, mat, plasmaGlow * plasmaHeat);
}

fn calcNormal(p: vec3<f32>, time: f32, fracture: f32, plasmaHeat: f32,
              iceDensity: f32, audio: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m2 = map(p - e.xyy, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m3 = map(p + e.yxy, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m4 = map(p - e.yxy, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m5 = map(p + e.yyx, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m6 = map(p - e.yyx, time, fracture, plasmaHeat, iceDensity, audio).d;
  return normalize(vec3<f32>(m1-m2, m3-m4, m5-m6));
}

// ═══════════════════════════════════════════════════════════════
//  VOLUMETRIC FOG
// ═══════════════════════════════════════════════════════════════
fn fogDensity(p: vec3<f32>, time: f32, fogThickness: f32) -> f32 {
  let n = fbm(p * 0.3 + time * 0.05);
  return fogThickness * n * exp(-length(p) * 0.05);
}

// ═══════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
  if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

  let uv = (fragCoord - 0.5 * res) / res.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;

  // Parameters (clamp zoom_params to normalized range)
  let zparams = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let fracture = mix(0.0, 2.0, zparams.x);        // Fracture Intensity
  let plasmaHeat = mix(0.0, 2.0, zparams.y);      // Plasma Heat
  let iceDensity = mix(0.5, 2.0, zparams.z);      // Ice Density
  let fogThickness = mix(0.0, 1.0, zparams.w);    // Fog Thickness

  // ═══ CHUNK: bass_env smoothing ═══
  let prevBass = extraBuffer[0];
  let bassSmooth = bass_env(prevBass, bass, 0.08, 0.02);
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[0] = bassSmooth;
  }

  // Camera
  let mouseUV = u.zoom_config.yz;
  let mouseY = mouseUV.y;  // Flip Y: screen top = up
  let camAng = time * 0.1 + mouseUV.x * 0.5;
  let camDist = 8.0;
  let ro = vec3<f32>(
    cos(camAng) * camDist,
    2.0 + mouseY * 2.0,
    sin(camAng) * camDist
  );
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
  let vv = cross(uu, ww);
  let rd = normalize(ww + uu * uv.x + vv * uv.y);

  // Raymarch
  var t = 0.0;
  var d = 0.0;
  var mat = 0.0;
  var glow = 0.0;
  var hit = false;

  for(var i = 0; i < MAX_STEPS; i++) {
    let p = ro + rd * t;
    let res = map(p, time, fracture, plasmaHeat, iceDensity, bassSmooth);
    d = res.d;
    mat = res.mat;
    glow = res.glow;
    if(d < SURF_DIST || t > MAX_DIST) { break; }
    t += d * 0.8;
  }

  // Volumetric fog along ray
  var fogAccum = vec3<f32>(0.0);
  var fogT = 0.0;
  for(var i = 0; i < 16; i++) {
    let fp = ro + rd * fogT;
    let fd = fogDensity(fp, time, fogThickness);
    let fogCol = vec3<f32>(0.6, 0.8, 1.0) * fd * 0.1;
    fogAccum += fogCol * (1.0 - fogAccum.x);
    fogT += 0.5;
    if(fogT > min(t, MAX_DIST)) { break; }
  }

  // Shading
  var col = vec3<f32>(0.0);
  if(t < MAX_DIST) {
    let p = ro + rd * t;
    let n = calcNormal(p, time, fracture, plasmaHeat, iceDensity, bassSmooth);

    // Lighting
    let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
    let diff = max(dot(n, lightDir), 0.0);
    let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 64.0);
    let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

    if(mat < 0.5) {
      // Ice material
      let iceCol = vec3<f32>(0.7, 0.9, 1.0);
      let refractCol = vec3<f32>(0.3, 0.7, 0.9) * fbm(p * 2.0);
      col = iceCol * (diff * 0.5 + 0.3) + spec * vec3<f32>(1.0) * 0.5 + refractCol * fresnel;
      // Chromatic refraction
      let r_refr = refract(rd, n, 0.95);
      let g_refr = refract(rd, n, 0.97);
      let b_refr = refract(rd, n, 0.99);
      col += vec3<f32>(
        fbm(p + r_refr * 0.5) * 0.15,
        fbm(p + g_refr * 0.5) * 0.1,
        fbm(p + b_refr * 0.5) * 0.08
      ) * fresnel;
    } else {
      // Plasma material
      let plasmaCol = mix(
        vec3<f32>(1.0, 0.2, 0.8),
        vec3<f32>(1.0, 0.8, 0.1),
        glow * bassSmooth
      );
      col = plasmaCol * (diff * 0.8 + 0.5) + spec * vec3<f32>(1.0, 0.9, 0.7) * 0.8;
      col += glow * vec3<f32>(2.0, 0.5, 1.0) * plasmaHeat;
    }

    // Distance fade
    col *= exp(-t * 0.03);
  }

  // Add fog
  col = mix(col, fogAccum, clamp(length(fogAccum), 0.0, 1.0));

  // Audio flash
  col += vec3<f32>(0.1, 0.3, 0.5) * bassSmooth * bassSmooth * 0.5;

  // Temporal feedback (upgraded-rgba)
  let prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
  col = mix(prevCol, col, 0.3);

  // Write
  let outCoords = vec2<i32>(global_id.xy);
  textureStore(writeTexture, outCoords, vec4<f32>(col, 1.0));
  textureStore(writeDepthTexture, outCoords, vec4<f32>(1.0 - clamp(t / MAX_DIST, 0.0, 1.0), 0.0, 0.0, 1.0));
}
