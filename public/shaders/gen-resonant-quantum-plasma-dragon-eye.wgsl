// ═══════════════════════════════════════════════════════════════════
//  Resonant Quantum-Plasma Dragon-Eye
//  Category: generative
//  Features: raymarched, dragon-eye, reptilian-iris, slit-pupil,
//            quantum-plasma, chromatic-aberration, audio-reactive,
//            mouse-driven, upgraded-rgba, depth-aware, aces-tone-map
//  Complexity: Very High
//  Created: 2026-06-28
//  Upgraded: 2026-09-27
//  Ideas: dilator-fibre stroma with guanine iridophore flecks; hippus-breathing slit coupled to fibre crimp; corneal dome (Fresnel plasma sheen, Purkinje catchlight, refraction parallax); tapetum eyeshine lighting the plasma as a gaze shaft
//  A packing: ACES display RGBA (C persistence mixed in display space)
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
  config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=PlasmaDensity, y=IrisComplexity, z=PupilSharpness, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// ─── Math Helpers ───
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash3(p: vec3<f32>) -> f32 {
  let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  var qv = q + dot(q, q.yzx + vec3<f32>(33.33));
  return fract((qv.x + qv.y) * qv.z);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn rot2D(a: f32) -> mat2x2<f32> {
  let c = cos(a);
  let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rot3X(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

// ─── Noise ───
fn vnoise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (vec3<f32>(3.0) - 2.0 * f);
  let h = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(
      mix(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f.x),
      mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f.x), f.y
    ),
    mix(
      mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f.x),
      mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f.x), f.y
    ), f.z
  );
}

fn fbm3(p: vec3<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pos = p;
  for (var i = 0; i < 5; i++) {
    v += a * vnoise3(pos);
    pos = pos * 2.1 + vec3<f32>(1.7, 0.3, 0.9);
    a *= 0.5;
  }
  return v;
}

// ─── SDF Helpers ───
fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(p.xz) - t.x, p.y);
  return length(q) - t.y;
}

fn sdVerticalCapsule(p: vec3<f32>, h: f32, r: f32) -> f32 {
  let py = p.y - clamp(p.y, -h, h);
  return length(vec2<f32>(length(p.xz), py)) - r;
}

// ─── Bass Envelope ───
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Global State ───
var<private> g_time: f32;
var<private> g_audio: f32;
var<private> g_mouse: vec2<f32>;
var<private> g_pupilDilation: f32;
var<private> g_pupilW: f32;     // current slit half-width  (eye space)
var<private> g_pupilH: f32;     // current slit half-height (eye space)
var<private> g_pupilN: f32;     // slit superellipse exponent (Pupil Sharpness; 2 = HEAD ellipse)
var<private> g_hitT: f32;       // ray distance of the eye hit (1e9 on miss)

// Superellipse radius: 1.0 on the slit margin. n = 2 reproduces length().
fn superR(a: vec2<f32>, n: f32) -> f32 {
  let b = max(abs(a), vec2<f32>(1e-6));
  return pow(pow(b.x, n) + pow(b.y, n), 1.0 / n);
}

// World -> mouse-rotated eye space (same rotation map() applies, without the lens).
fn toEye(p: vec3<f32>) -> vec3<f32> {
  let lookX = g_mouse.x * 0.5;
  let lookY = (0.5 - g_mouse.y) * 0.5;
  return rot3Y(lookX) * (rot3X(lookY) * p);
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
};

fn map(p_in: vec3<f32>, plasmaDensity: f32, irisComplexity: f32, pupilSharpness: f32, aberration: f32) -> MapResult {
  var p = p_in;

  // Eye follows mouse - look-at rotation
  let lookX = g_mouse.x * 0.5;
  let lookY = (0.5 - g_mouse.y) * 0.5;
  let rotX = rot3X(lookY);
  let rotY = rot3Y(lookX);
  p = rotX * p;
  p = rotY * p;

  // Mouse gravitational lens distortion
  let mouseWorld = vec3<f32>(g_mouse.x * 2.0, (0.5 - g_mouse.y) * 2.0, 1.0);
  let mouseDist = length(p - mouseWorld);
  let lensPower = max(0.0, 1.0 - mouseDist / 3.0) * aberration * 0.2;
  p = p + normalize(p - mouseWorld) * lensPower;

  // Base eyeball sphere
  let eyeRadius = 2.0;
  let eyeDist = length(p) - eyeRadius;

  // Iris: torus-like ring on front surface
  let irisR = 0.8;
  let irisThick = 0.15;
  let frontZ = p.z + eyeRadius;
  let irisCenter = vec3<f32>(0.0, 0.0, -eyeRadius + 0.1);
  let irisDist = sdTorus(p - irisCenter, vec2<f32>(irisR, irisThick));

  // Fractal iris fibers using polar noise
  let r = length(p.xy);
  let theta = atan2(p.y, p.x);
  let irisNoise = fbm3(vec3<f32>(
    cos(theta * irisComplexity * 5.0) * r,
    sin(theta * irisComplexity * 5.0) * r,
    g_time * 0.2
  )) * 0.1;
  let fiberDist = abs(r - irisR) - irisThick * 0.5 - irisNoise;

  // Slit pupil - vertical ellipse that dilates with bass
  let pupilWidth = 0.15 + g_pupilDilation * 0.4;
  let pupilHeight = 0.6 + g_pupilDilation * 0.3;
  // Pupil Sharpness = superellipse exponent (was a dead `sharpPupil` value); n=2 at default == HEAD ellipse
  let pupilDist = superR(p.xy / vec2<f32>(pupilWidth, pupilHeight), g_pupilN) - 1.0;
  // Bug fix: iris ring + slit were infinite cylinders along z (a glowing slab through the socket in side
  // views of the orbit). Bound both to the front cap of the eyeball.
  let frontCap = p.z < 0.0;
  let capR = length(p);

  // Eye socket / surrounding scales
  let socketDist = length(p) - (eyeRadius + 0.3);
  let scaleNoise = fbm3(p * 3.0 + vec3<f32>(0.0, 0.0, g_time * 0.1)) * 0.05;
  let scaleDist = socketDist - scaleNoise;

  // Combine: eyeball, iris, pupil
  var d = eyeDist;
  var mat = 2.0; // 2.0 = sclera
  var glow = 0.0;

  // Idea 1: dilator-fibre stroma — the bare cap between slit and fibre ring is iris tissue, not sclera
  if (frontCap && r < irisR - irisThick * 0.5 + 0.03) {
    mat = 4.0; // 4.0 = iris stroma
    glow = 0.2;
  }

  // Iris is in front
  if (fiberDist < d && r < irisR + 0.3 && r > 0.1 && frontCap && capR < eyeRadius + 0.12) {
    d = fiberDist;
    mat = 1.0; // 1.0 = iris
    glow = 0.3;
  }

  // Pupil cuts through center
  if (pupilDist < 0.0 && r < irisR - 0.1 && frontCap && capR < eyeRadius + 0.02) {
    d = pupilDist;
    mat = 0.0; // 0.0 = pupil (void)
    glow = 2.0 * g_pupilDilation;
  }

  // Scales around socket
  if (scaleDist < d && r > irisR + 0.2) {
    d = scaleDist;
    mat = 3.0; // 3.0 = scales
    glow = 0.1;
  }

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, plasmaDensity: f32, irisComplexity: f32, pupilSharpness: f32, aberration: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, plasmaDensity, irisComplexity, pupilSharpness, aberration);
  let m2 = map(p - e.xyy, plasmaDensity, irisComplexity, pupilSharpness, aberration);
  let m3 = map(p + e.yxy, plasmaDensity, irisComplexity, pupilSharpness, aberration);
  let m4 = map(p - e.yxy, plasmaDensity, irisComplexity, pupilSharpness, aberration);
  let m5 = map(p + e.yyx, plasmaDensity, irisComplexity, pupilSharpness, aberration);
  let m6 = map(p - e.yyx, plasmaDensity, irisComplexity, pupilSharpness, aberration);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Raymarch ───
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, plasmaDensity: f32, irisComplexity: f32, pupilSharpness: f32, aberration: f32) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var hit = false;
  var matId = 2.0;
  var hitGlow = 0.0;
  g_hitT = 1e9;

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, plasmaDensity, irisComplexity, pupilSharpness, aberration);
    let d = res.d;

    if (d < 0.001) {
      hit = true;
      matId = res.mat;
      hitGlow = res.glow;

      let n = calcNormal(p, plasmaDensity, irisComplexity, pupilSharpness, aberration);
      let v = -rd;
      let lightDir = normalize(vec3<f32>(1.0, 1.5, -1.0));
      let diff = max(dot(n, lightDir), 0.0);
      let cosi = min(max(dot(n, v), 0.0), 1.0);
      g_hitT = t;

      // Eye-space frame for iris / pupil / cornea shading
      let q = toEye(p);
      let vE = toEye(v);
      let LE = toEye(lightDir);

      if (matId < 0.5) {
        // Pupil: contained supernova
        let novaCol = vec3<f32>(1.0, 0.9, 0.4) * (2.0 + g_audio * 3.0);
        let novaSwirl = fbm3(p * 3.0 + vec3<f32>(g_time * 0.5, 0.0, 0.0));
        col = novaCol * (0.8 + novaSwirl * 0.4);
        col += vec3<f32>(0.5, 0.2, 1.0) * g_audio;
        // Idea 4: tapetum eyeshine — retroreflective flare as the camera crosses the gaze axis (-z in eye space)
        let onAxis = max(-vE.z, 0.0);
        let shine = pow(onAxis, 12.0) * 1.6 + pow(onAxis, 3.0) * 0.25;
        col += vec3<f32>(1.0, 0.75, 0.3) * shine * (0.8 + novaSwirl * 0.5);
        alpha = 0.95;
      } else if (matId < 1.5) {
        // Iris: liquid-neon greens, piercing golds, deep abyss blues
        // (eye space: the ring geometry is mouse-rotated, HEAD shaded it in world space)
        let r = length(q.xy);
        let theta = atan2(q.y, q.x);
        let irisPat = sin(theta * 8.0 + g_time * 0.3) * cos(r * 10.0);

        let green = vec3<f32>(0.0, 0.8, 0.3);
        let gold = vec3<f32>(1.0, 0.8, 0.1);
        let abyss = vec3<f32>(0.0, 0.1, 0.4);

        var irisCol = mix(green, gold, sat(irisPat * 0.5 + 0.5));
        irisCol = mix(irisCol, abyss, sat(r / 0.8));

        // Subsurface scattering on iris fibers
        let sss = pow(max(1.0 - cosi, 0.0), 3.0) * 0.5;
        irisCol += vec3<f32>(0.2, 0.5, 0.3) * sss;

        // Audio-reactive chromatic aberration ripple
        let caRipple = sin(r * 20.0 - g_time * 5.0) * 0.5 + 0.5;
        irisCol += vec3<f32>(0.3, 0.0, 0.3) * caRipple * g_audio * aberration;

        col = irisCol * (diff + 0.3);
        alpha = 0.85;
      } else if (matId < 2.5) {
        // Sclera: white with vein texture
        let veinNoise = fbm3(p * 4.0 + vec3<f32>(g_time * 0.1, 0.0, 0.0));
        let scleraCol = mix(vec3<f32>(0.9, 0.9, 0.85), vec3<f32>(0.3, 0.0, 0.5), veinNoise * 0.3);
        col = scleraCol * (diff + 0.4);
        alpha = 0.9;
      } else if (matId < 3.5) {
        // Scales: bioluminescent subsurface scattering
        let scalePat = fbm3(p * 5.0) * 0.5 + 0.5;
        let scaleCol = mix(
          vec3<f32>(0.05, 0.15, 0.1),
          vec3<f32>(0.1, 0.4, 0.3),
          scalePat
        );
        let sss = pow(max(1.0 - cosi, 0.0), 2.0) * 0.8;
        col = scaleCol * (diff + 0.2) + vec3<f32>(0.0, 0.3, 0.2) * sss;
        alpha = 0.8;
      } else {
        // ── Idea 1 + 2: dilator-fibre stroma, anchored margin-to-root (hippus coupling) ──
        // Idea 3 (parallax): stroma sits ~0.12 behind the cornea, refracted (n≈1.376) toward the viewer
        let par = vE.xy / max(abs(vE.z), 0.35) * 0.035;
        let ps = q.xy - par;
        let r = length(ps);
        let theta = atan2(ps.y, ps.x);
        // Tissue coordinate s: 0 on the (breathing) slit margin, 1 at the fibre-ring root.
        // As the slit widens the margin moves out, so the same fibres compress toward the root.
        let rho = superR(ps / vec2<f32>(g_pupilW, g_pupilH), g_pupilN);
        let margin = r / max(rho, 1e-4);
        let rootR = 0.8 - 0.075;
        let s = sat((r - margin) / max(rootR - margin, 0.02));
        // Radial dilator fibres; count from Iris Complexity (integer -> seamless at theta = ±PI)
        let nF = floor(14.0 + irisComplexity * 6.0);
        // Idea 2: crimp — fibres pleat harder as the slit dilates (hippus + bass)
        let crimp = sin(s * 20.0 - g_time * 0.4) * (0.08 + 0.5 * g_pupilDilation) * (1.0 - s);
        let fib = pow(abs(sin(theta * nF * 0.5 + crimp)), 6.0)
                + pow(abs(sin(theta * nF * 1.5 + crimp * 1.7 + 0.8)), 10.0) * 0.5;
        let gold = vec3<f32>(1.0, 0.8, 0.1);
        let green = vec3<f32>(0.0, 0.8, 0.3);
        let abyss = vec3<f32>(0.0, 0.1, 0.4);
        var sc = mix(gold * 0.9, green, smoothstep(0.15, 0.55, s)); // pupillary gold -> ciliary green
        sc = mix(sc, abyss, smoothstep(0.7, 1.0, s));               // abyss at the root (matches ring)
        sc *= 0.45 + 0.75 * fib;
        sc *= 0.25 + 0.75 * smoothstep(0.0, 0.07, s);                 // dark pigment ruff on the slit margin
        // Idea 1: guanine iridophore flecks — reptile-iris metallic cells that twinkle with view angle
        let K = 2.0 * nF;
        let cellUV = vec2<f32>((theta / (2.0 * PI) + 0.5) * K, s * 7.0);
        let cell = floor(cellUV);
        let hC = hash21(cell + vec2<f32>(17.0, 3.0));
        let spot = 1.0 - smoothstep(0.12, 0.32, length(fract(cellUV) - 0.5));
        let twinkle = pow(0.5 + 0.5 * sin(hC * 43.0 + dot(vE, vec3<f32>(9.0, 7.0, 5.0))), 6.0);
        let fleck = step(0.78, hC) * spot * twinkle * smoothstep(0.08, 0.2, s);
        sc += vec3<f32>(1.0, 0.72, 0.35) * fleck * (0.6 + diff);
        let sss = pow(max(1.0 - cosi, 0.0), 3.0) * 0.5;
        sc += vec3<f32>(0.2, 0.5, 0.3) * sss;
        col = sc * (diff + 0.3);
        alpha = 0.85;
      }

      // ── Idea 3: corneal dome over slit, stroma and fibre ring ──
      if (matId < 1.5 || matId > 3.5) {
        let nC = normalize(q - vec3<f32>(0.0, 0.0, -0.95));       // tighter bulge than the eyeball
        let cv = max(dot(nC, vE), 0.0);
        let fres = 0.04 + 0.96 * pow(max(1.0 - cv, 0.0), 5.0);
        let rC = reflect(-vE, nC);
        let envN = fbm3(rC * 2.0 + vec3<f32>(g_time * 0.2, 0.0, 0.0));
        let env = vec3<f32>(0.05, 0.04, 0.08)
                + (vec3<f32>(0.1, 0.0, 0.2) + vec3<f32>(0.0, 0.35, 0.2) * envN) * (0.3 + plasmaDensity);
        let spec = max(dot(rC, LE), 0.0);
        let purkinje = pow(spec, 240.0) * 8.0 + pow(spec, 24.0) * 0.2;  // catchlight + halo
        let limbus = 1.0 - smoothstep(0.85, 0.98, length(q.xy));
        col = mix(col, env, fres * limbus * 0.8) + vec3<f32>(1.0, 0.96, 0.88) * purkinje * limbus;
      }
      break;
    }

    if (t > 20.0) { break; }
    t = t + d * 0.7;
  }

  if (!hit) {
    // Quantum plasma atmosphere bleeding from eye
    let axisDist = length(ro.xy + rd.xy * 5.0);
    let plasmaFalloff = 0.1 / (axisDist + 0.1);
    let plasmaNoise = fbm3(ro + rd * 5.0 + vec3<f32>(g_time * 0.2, 0.0, 0.0));
    col = vec3<f32>(0.02, 0.01, 0.03);
    col += vec3<f32>(0.1, 0.0, 0.2) * plasmaFalloff * plasmaDensity;
    col += vec3<f32>(0.0, 0.2, 0.1) * plasmaNoise * plasmaDensity * 0.2;
    alpha = 0.0;
  }

  return vec4<f32>(col, alpha);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;

  // Audio
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Bug fix: HEAD kept a bass envelope in extraBuffer[0], which the engine overwrites with raw bass every
  // frame (and pixel 0's write raced other workgroups). Stateless: read the uploaded bass directly.
  let smoothBass = max(bass, 0.0);

  // Parameters
  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
  let plasmaDensity = mix(0.0, 1.0, zp.x);
  let irisComplexity = mix(0.1, 5.0, zp.y);
  let pupilSharpness = mix(0.1, 2.0, zp.z);
  let aberration = mix(0.0, 1.0, zp.w);

  // Pupil dilation tied to bass
  // Idea 2: hippus — slow irregular autonomic pupil breathing, alive with audio = 0 (bass rides on top)
  let hippus = 0.07 * (1.0 + 0.6 * sin(time * 0.53) + 0.4 * sin(time * 1.37 + 2.1));
  g_pupilDilation = smoothBass + hippus;
  g_pupilW = 0.15 + g_pupilDilation * 0.4;
  g_pupilH = 0.6 + g_pupilDilation * 0.3;
  // Pupil Sharpness -> slit superellipse exponent; exactly 2 (HEAD ellipse) at the saved default 0.37
  let psDefZ: f32 = 0.37;
  let psDefault = mix(0.1, 2.0, psDefZ);
  g_pupilN = clamp(2.0 * psDefault / max(pupilSharpness, 0.05), 1.0, 4.0);

  // Mouse
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  g_mouse = vec2<f32>((mouseUV.x - 0.5) * 2.0 * aspect, (0.5 - mouseUV.y) * 2.0);

  g_time = time;
  g_audio = smoothBass;

  // Camera
  let camDist = 5.0;
  let camAng = time * 0.1 + mouseUV.x * 0.3;
  let camHeight = sin(time * 0.05) * 0.2 + (0.5 - mouseUV.y) * 0.2;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  // Ray direction
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch
  let result = raymarch(ro, rd, plasmaDensity, irisComplexity, pupilSharpness, aberration);
  var col = result.rgb;
  var alpha = result.a;

  // Volumetric quantum plasma atmosphere
  var plasmaGlow = vec3<f32>(0.0);
  let numVol = 16;
  let volStep = 10.0 / f32(numVol);
  for (var i: i32 = 0; i < numVol; i = i + 1) {
    let vt = f32(i) * volStep + hash21(vec2<f32>(f32(i32(gid.x) + i * 73), f32(i32(gid.y) + i * 137))) * volStep;
    let vp = ro + rd * vt;
    let vfbm = fbm3(vp * 1.2 + vec3<f32>(time * 0.2, 0.0, time * 0.15));
    let vg = sat(0.5 - vfbm) * exp(-vt * 0.15);
    plasmaGlow += vec3<f32>(0.1, 0.3, 0.2) * vg * (0.03 + smoothBass * 0.06) * plasmaDensity;
  }
  // Idea 4: tapetum gaze shaft — the eye's light illuminates the haze's own density field (base octave of the
  // fbm above) in a slit-shaped cone along the mouse-look axis; occluded behind the eyeball via g_hitT.
  var gaze = vec3<f32>(0.0);
  let nG = 12;
  let gStep = min(g_hitT, 10.0) / f32(nG);
  let gJit = hash21(vec2<f32>(f32(gid.x) * 0.37 + 11.0, f32(gid.y) * 0.73 + 5.0));
  for (var i: i32 = 0; i < nG; i = i + 1) {
    let gp = ro + rd * ((f32(i) + gJit) * gStep);
    let qv = toEye(gp);
    let ax = -qv.z - 1.95;                    // distance out of the front of the eye
    if (ax > 0.0) {
      let wx = g_pupilW + 0.12 + ax * 0.16;
      let wy = g_pupilH * 0.8 + ax * 0.16;
      let cone = exp(-(qv.x * qv.x) / (wx * wx) - (qv.y * qv.y) / (wy * wy)) * exp(-ax * 0.28);
      if (cone > 0.003) {
        let dens = vnoise3(gp * 1.2 + vec3<f32>(time * 0.2, 0.0, time * 0.15));
        let lit = cone * (0.25 + 1.5 * sat(dens - 0.3));
        gaze += mix(vec3<f32>(1.0, 0.75, 0.3), vec3<f32>(0.45, 0.2, 1.0), sat(ax * 0.3)) * lit * gStep;
      }
    }
  }
  gaze *= (0.16 + smoothBass * 0.12) * (0.3 + plasmaDensity);

  col = col + plasmaGlow + gaze;

  // Chromatic aberration on edges
  let caStr = 0.002 * aberration * (1.0 + smoothBass);
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  // Tone map
  col = acesToneMap(col * 1.15);

  // Temporal persistence — C holds ACES display (what A stores), so mix in display space; exact texel load
  let prev = textureLoad(dataTextureC, coord, 0);
  col = mix(col, prev.rgb * 0.92, 0.04);

  // Output — semantic alpha: eye coverage + plasma / gaze-shaft glow (HEAD computed this, then wrote 1.0)
  let presence = sat(alpha + length(plasmaGlow + gaze) * 2.0);
  let finalAlpha = presence;
  let finalDepth = sat(0.95 - alpha * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(col, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, finalAlpha));
}
