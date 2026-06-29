// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Plasma-Reef Matrix
//  Category: generative
//  Features: raymarched, organic, bioluminescent, audio-reactive,
//            mouse-driven, upgraded-rgba, depth-aware, oceanic
//  Complexity: Very High
//  Created: 2026-06-28
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

// ─── Math Helpers ───
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  q = q + dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn rot2D(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn rot3X(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

// ─── Noise ───
fn valueNoise3D(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  var n = 0.0;
  for (var k: i32 = 0; k <= 1; k = k + 1) {
    for (var j: i32 = 0; j <= 1; j = j + 1) {
      for (var i0: i32 = 0; i0 <= 1; i0 = i0 + 1) {
        let h = hash3(i + vec3<f32>(f32(i0), f32(j), f32(k)));
        n = n + h * abs(1.0 - f32(i0) - f.x) * abs(1.0 - f32(j) - f.y) * abs(1.0 - f32(k) - f.z);
      }
    }
  }
  return n;
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise3D(pp);
    pp = pp * 2.0;
    a = a * 0.5;
  }
  return v;
}

// ─── SDF Primitives ───
fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Coral Branch SDF ───
fn coralBranch(p: vec3<f32>, seed: f32, time: f32, audio: f32) -> f32 {
  let branchP = p - vec3<f32>(sin(seed * 3.0) * 0.5, seed * 0.8, cos(seed * 2.7) * 0.5);
  // Bend the branch
  let bend = vec3<f32>(sin(branchP.y * 2.0 + seed + time * 0.3) * 0.3, 0.0, cos(branchP.y * 1.5 + seed + time * 0.2) * 0.2);
  let bp = branchP + bend;
  // Tapered capsule
  let t = sat(bp.y * 0.5 + 0.5);
  let radius = mix(0.15, 0.03, t) * (1.0 + audio * 0.2);
  let d = sdCapsule(bp, vec3<f32>(0.0, -0.5, 0.0), vec3<f32>(0.0, 0.5, 0.0), radius);
  // Add organic bumps
  let bumps = sin(bp.x * 8.0 + seed * 10.0) * sin(bp.y * 6.0 + time) * sin(bp.z * 8.0) * 0.02;
  return d + bumps;
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
};

fn map(p_in: vec3<f32>, time: f32, audio: f32, bass: f32, reefDensity: f32,
       swarmSize: f32, glowIntensity: f32, mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Mouse ripple displacement
  let md = p - mousePos;
  let mDist = length(md);
  let rippleRadius = 3.0;
  if (mDist < rippleRadius) {
    let ripple = (1.0 - mDist / rippleRadius) * sin(mDist * 5.0 - time * 3.0) * 0.3;
    p = p + normalize(md) * ripple;
  }

  // Terrain floor (ocean bed)
  let terrainY = -1.5 + fbm3(p * vec3<f32>(0.5, 0.3, 0.5) + vec3<f32>(0.0, time * 0.05, 0.0), 4) * 0.8;
  let terrain = p.y - terrainY;

  // Coral structures (multiple branches)
  var coral = 8.0;
  for (var i: i32 = 0; i < 5; i = i + 1) {
    let fi = f32(i);
    let pos = vec3<f32>(sin(fi * 2.1) * 2.0, -1.0 + fi * 0.2, cos(fi * 1.7) * 2.0);
    let branch = coralBranch(p - pos, fi + 0.5, time, audio);
    coral = smin(coral, branch, 0.2 + audio * 0.1);
  }

  // Combine terrain and coral
  var d = smin(terrain, coral, 0.4);
  var mat = 1.0; // coral
  var glow = 0.0;

  if (coral < terrain) {
    // Coral glow
    let distToCoral = coral;
    glow = sat((0.0 - distToCoral) * 2.0) * glowIntensity;
    // Breathing expansion
    let breath = sin(time * 1.5 + p.y * 3.0) * 0.5 + 0.5;
    glow = glow * (0.5 + breath * 0.5 + bass * 0.5);
  }

  // Bioluminescent entities (procedural particles via SDF)
  var entityDist = 8.0;
  let numEntities = 8;
  for (var i: i32 = 0; i < numEntities; i = i + 1) {
    let fi = f32(i);
    let et = time * 0.5 + fi * 1.3;
    var ePos = vec3<f32>(
      sin(et * 0.7 + fi * 2.0) * 2.5 * swarmSize,
      -0.5 + sin(et * 0.3 + fi) * 0.8,
      cos(et * 0.5 + fi * 1.5) * 2.5 * swarmSize
    );
    // Flee from mouse
    let eToMouse = ePos - mousePos;
    let eMouseDist = length(eToMouse);
    if (eMouseDist < 2.0) {
      ePos = ePos + normalize(eToMouse) * (2.0 - eMouseDist) * 0.5;
    }
    let ed = sdSphere(p - ePos, 0.05 + bass * 0.03);
    if (ed < entityDist) { entityDist = ed; }
  }
  if (entityDist < d) {
    d = entityDist;
    mat = 2.0; // entity
    glow = 1.0 + bass * 2.0;
  }

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, bass: f32, reefDensity: f32,
              swarmSize: f32, glowIntensity: f32, mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, bass, reefDensity, swarmSize, glowIntensity, mousePos);
  let m2 = map(p - e.xyy, time, audio, bass, reefDensity, swarmSize, glowIntensity, mousePos);
  let m3 = map(p + e.yxy, time, audio, bass, reefDensity, swarmSize, glowIntensity, mousePos);
  let m4 = map(p - e.yxy, time, audio, bass, reefDensity, swarmSize, glowIntensity, mousePos);
  let m5 = map(p + e.yyx, time, audio, bass, reefDensity, swarmSize, glowIntensity, mousePos);
  let m6 = map(p - e.yyx, time, audio, bass, reefDensity, swarmSize, glowIntensity, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Raymarch ───
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio: f32, bass: f32, mids: f32,
            treble: f32, reefDensity: f32, swarmSize: f32, glowIntensity: f32,
            mousePos: vec3<f32>) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var hit = false;
  var hitGlow = 0.0;
  var hitMat = 0.0;

  for (var i: i32 = 0; i < 80; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, time, audio, bass, reefDensity, swarmSize, glowIntensity, mousePos);
    let d = res.d;

    if (d < 0.003) {
      hit = true;
      hitGlow = res.glow;
      hitMat = res.mat;
      let n = calcNormal(p, time, audio, bass, reefDensity, swarmSize, glowIntensity, mousePos);
      let viewAngle = max(dot(-rd, n), 0.0);

      if (hitMat < 1.5) {
        // Coral: violet -> pink gradient with bioluminescence
        let height = sat(p.y + 1.5);
        var coralCol = mix(vec3<f32>(0.2, 0.0, 0.4), vec3<f32>(0.9, 0.3, 0.6), height);
        coralCol = coralCol + vec3<f32>(0.3, 0.0, 0.5) * hitGlow * 2.0;
        coralCol = coralCol + vec3<f32>(0.0, 0.2, 0.5) * bass * viewAngle;
        // Subsurface scattering approximation
        let sss = pow(viewAngle, 3.0) * hitGlow;
        coralCol = coralCol + vec3<f32>(0.5, 0.1, 0.4) * sss;
        col = coralCol;
        alpha = sat(0.5 + hitGlow * 0.3);
      } else {
        // Entity: bright cyan/green flash
        let flash = sin(time * 10.0 + p.x * 20.0) * 0.5 + 0.5;
        var entityCol = mix(vec3<f32>(0.0, 1.0, 0.8), vec3<f32>(0.2, 1.0, 0.2), flash);
        entityCol = entityCol * (1.0 + treble * 3.0);
        // Trailing glow
        let trail = pow(viewAngle, 2.0) * 0.5;
        col = entityCol + vec3<f32>(0.0, 0.5, 0.4) * trail;
        alpha = 0.95;
      }
      break;
    }

    if (t > 25.0) { break; }
    t = t + d * 0.7;

    // Volumetric fog glow from coral
    if (res.glow > 0.01 && t < 15.0) {
      let fogCol = vec3<f32>(0.1, 0.0, 0.2) * res.glow * 0.03 * exp(-t * 0.08);
      col = col + fogCol;
    }
  }

  if (!hit) {
    // Deep ocean background
    col = vec3<f32>(0.0, 0.01, 0.03);
    // Caustic light from above
    let caustic = pow(sin(rd.x * 10.0 + time) * sin(rd.y * 8.0 + time * 0.7), 2.0);
    col = col + vec3<f32>(0.0, 0.1, 0.15) * caustic * (0.1 + bass * 0.1) * max(-rd.y, 0.0);
    // Distant bioluminescent haze
    col = col + vec3<f32>(0.1, 0.0, 0.2) * (0.05 + bass * 0.05) * sat(0.3 / (abs(rd.y) + 0.1));
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
  let audio = plasmaBuffer[0].x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters from zoom_params (clamp to normalized range)
  let zparams = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let reefDensity = mix(0.1, 1.0, zparams.x);
  let swarmSize = mix(0.0, 2.0, zparams.y);
  let glowIntensity = mix(0.1, 1.5, zparams.z);
  let fogDensity = mix(0.2, 1.0, zparams.w);

  // Mouse handling: screen top = UP in 3D
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = 1.0 - mouseUV.y; // Flip Y
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (mouseUV.y * 2.0 - 1.0) * 3.0,
    0.0
  );

  // Camera (underwater looking at reef)
  let camDist = 5.0 + sin(time * 0.1) * 0.5;
  let camAng = time * 0.12 + mouseUV.x * 0.3;
  let camHeight = sin(time * 0.08) * 0.3 + mouseY * 0.5 - 0.5;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, -0.5, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  // Ray direction
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch
  let result = raymarch(ro, rd, time, audio, bass, mids, treble, reefDensity, swarmSize, glowIntensity, mousePos);
  var col = result.rgb;
  var alpha = result.a;

  // Ocean volumetric fog
  let fog = exp(-alpha * 0.3 * fogDensity);
  let fogCol = vec3<f32>(0.0, 0.02, 0.05) * (1.0 + bass * 0.2);
  col = mix(fogCol, col, fog);

  // Audio-reactive color shift
  col = col + vec3<f32>(0.0, 0.1, 0.15) * bass * 0.15;
  col = col + vec3<f32>(0.0, 0.2, 0.0) * treble * 0.1;

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(col, prev.rgb * 0.93, 0.04);

  // Tone map
  col = acesToneMap(col * 1.3);

  let finalDepth = sat(0.95 - alpha * 0.4 + fogDensity * 0.05);

  textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, 1.0));
}
