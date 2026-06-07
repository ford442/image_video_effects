// ═══════════════════════════════════════════════════════════════════
//  Prismatic Crystal Growth
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Very High
//  Description: SDF crystal lattice that grows over time with
//    Fresnel reflectance for glass-like translucency. Alpha encodes
//    crystal thickness — thin edges are transparent, thick centers
//    opaque. Audio drives growth rate and rotation.
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

// ═══ CHUNK: hash functions ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: rotation matrices ═══
fn rotX(a: f32) -> mat3x3<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotZ(a: f32) -> mat3x3<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// ═══ CHUNK: SDF primitives ═══
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  let q = abs(p);
  return (q.x + q.y + q.z - s) * 0.57735027;
}

fn sdDodecahedron(p: vec3<f32>, s: f32) -> f32 {
  // Approximate dodecahedron using combination of planes
  let q = abs(p);
  let d1 = dot(q, vec3<f32>(0.577, 0.577, 0.577)) - s;
  let d2 = dot(q, vec3<f32>(0.357, 0.862, 0.357)) - s;
  let d3 = dot(q, vec3<f32>(0.0, 0.526, 0.851)) - s;
  return max(max(d1, d2), d3);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ═══ CHUNK: crystal lattice SDF ═══
fn crystalLattice(p: vec3<f32>, t: f32, growth: f32) -> vec2<f32> {
  let spacing = 2.5;
  let id = floor(p / spacing + 0.5);
  let q = p - id * spacing;

  let rand = hash13(id + vec3<f32>(37.0, 17.0, 53.0));
  let rand2 = hash13(id + vec3<f32>(73.0, 31.0, 11.0));

  // Rotation per crystal
  let rotSpeed = 0.2 + rand * 0.3;
  let rotAngle = t * rotSpeed + rand2 * 6.28;
  var rp = rotX(rand * 2.0) * rotY(rotAngle) * rotZ(rand2 * 3.0) * q;

  // Growth factor determines crystal size
  let size = mix(0.1, 0.8, growth) * (0.6 + rand * 0.4);

  // Mix between octahedron and dodecahedron based on rand
  let crystalType = step(0.5, rand);
  var d: f32;
  if (crystalType < 0.5) {
    d = sdOctahedron(rp, size);
  } else {
    d = sdDodecahedron(rp, size * 0.9);
  }

  // Add subtle surface detail
  let detail = hash13(id * 10.0 + floor(rp * 8.0)) * 0.02 * growth;
  d = d - detail;

  return vec2<f32>(d, rand);
}

// ═══ CHUNK: scene map ═══
fn map(p: vec3<f32>, t: f32, growth: f32) -> vec2<f32> {
  let lattice = crystalLattice(p, t, growth);
  // Ground plane
  let ground = p.y + 2.0;
  if (ground < lattice.x) {
    return vec2<f32>(ground, 0.0);
  }
  return lattice;
}

// ═══ CHUNK: normal calculation ═══
fn calcNormal(p: vec3<f32>, t: f32, growth: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  return normalize(vec3<f32>(
    map(p + e.xyy, t, growth).x - map(p - e.xyy, t, growth).x,
    map(p + e.yxy, t, growth).x - map(p - e.yxy, t, growth).x,
    map(p + e.yyx, t, growth).x - map(p - e.yyx, t, growth).x
  ));
}

// ═══ CHUNK: Fresnel Schlick ═══
fn fresnelSchlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
  return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ CHUNK: crystal caustics approximation ═══
fn crystalCaustics(p: vec3<f32>, n: vec3<f32>, lightDir: vec3<f32>, t: f32) -> f32 {
  let refractDir = refract(lightDir, n, 0.75);
  let caustPos = p + refractDir * 0.5;
  let pattern = sin(caustPos.x * 15.0) * sin(caustPos.y * 15.0) * sin(caustPos.z * 15.0);
  let caustic = pow(abs(pattern), 0.5);
  return caustic * 0.4;
}

// ═══ CHUNK: bass envelope smoothing ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
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
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let uv = vec2<f32>(gid.xy) / res;
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let time = u.config.x;

  // Audio input
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rms = plasmaBuffer[0].w;

  // Parameters
  let growthRate = mix(0.05, 0.3, u.zoom_params.x);
  let crystalDensity = mix(0.3, 1.0, u.zoom_params.y);
  let prismIntensity = mix(0.2, 1.0, u.zoom_params.z);
  let causticStrength = mix(0.1, 0.8, u.zoom_params.w);

  // Mouse: position controls light source direction
  let mousePos = u.zoom_config.yz;
  let lightDir = normalize(vec3<f32>(
    (mousePos.x - 0.5) * 3.0,
    0.8 + (mousePos.y - 0.5) * 0.5,
    -1.0
  ));

  // Audio-reactive: bass drives growth rate, mids drive crystal rotation
  var prevBass = extraBuffer[2];
  let smoothBass = bass_env(prevBass, bass, 0.08, 0.02);
  extraBuffer[2] = smoothBass;

  // Time-based growth with audio boost
  let growth = clamp((time * growthRate * (1.0 + smoothBass * 0.5)) / 10.0, 0.0, 1.0);

  // Temporal feedback for growth state
  let prevState = textureLoad(dataTextureC, coord, 0);
  var storedGrowth = prevState.g;
  if (time < 0.1) { storedGrowth = 0.0; }
  storedGrowth = max(storedGrowth, growth);

  // Camera setup
  let aspect = res.x / res.y;
  var screenUV = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

  // Slow orbit
  let camAngle = time * 0.1 + mids * 0.3;
  let camDist = 6.0;
  var ro = vec3<f32>(sin(camAngle) * camDist, 2.0 + sin(time * 0.05) * 0.5, cos(camAngle) * camDist);
  var rd = normalize(vec3<f32>(screenUV.x, screenUV.y, 1.5));

  // Raymarch
  var t = 0.0;
  var mat = 0.0;
  var p = ro;
  var hit = false;
  var crystalRand = 0.0;

  for (var i = 0; i < 120; i = i + 1) {
    p = ro + rd * t;
    let res2 = map(p, time, storedGrowth);
    let d = res2.x;
    mat = res2.y;
    crystalRand = res2.y;

    if (d < 0.001) {
      hit = true;
      break;
    }
    if (t > 30.0) { break; }
    t = t + d * 0.7;
  }

  var color = vec3<f32>(0.0);
  var alpha = 0.0;
  var thickness = 0.0;

  if (hit) {
    let n = calcNormal(p, time, storedGrowth);
    let v = -rd;

    // Thickness estimation: sample slightly inside
    let innerP = p - n * 0.05;
    let innerD = map(innerP, time, storedGrowth).x;
    thickness = clamp(abs(innerD) * 8.0, 0.05, 1.0);

    if (mat < 0.1) {
      // Ground plane
      let diff = max(dot(n, lightDir), 0.0);
      color = vec3<f32>(0.08, 0.1, 0.15) * (diff * 0.5 + 0.2);
      alpha = clamp(0.85 + diff * 0.12, 0.85, 0.98);
    } else {
      // Crystal material
      // Diffuse
      let diff = max(dot(n, lightDir), 0.0);

      // Specular
      let halfVec = normalize(lightDir + v);
      let spec = pow(max(dot(n, halfVec), 0.0), 64.0);

      // Fresnel for glass-like translucency
      let fresnel = fresnelSchlick(max(dot(n, v), 0.0), vec3<f32>(0.04, 0.06, 0.08));
      let fresnelScalar = (fresnel.x + fresnel.y + fresnel.z) / 3.0;

      // Crystal color based on orientation (prismatic dispersion)
      let hue = fract(crystalRand + dot(n, vec3<f32>(1.0, 0.5, 0.3)) * 0.3 + prismIntensity * 0.2);
      let h6 = hue * 6.0;
      let c = 1.0;
      let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
      var crystalCol: vec3<f32>;
      if (h6 < 1.0) { crystalCol = vec3<f32>(c, x, 0.3); }
      else if (h6 < 2.0) { crystalCol = vec3<f32>(x, c, 0.3); }
      else if (h6 < 3.0) { crystalCol = vec3<f32>(0.2, c, x); }
      else if (h6 < 4.0) { crystalCol = vec3<f32>(0.2, x, c); }
      else if (h6 < 5.0) { crystalCol = vec3<f32>(x, 0.2, c); }
      else { crystalCol = vec3<f32>(c, 0.2, x); }

      // Base crystal color
      color = crystalCol * diff * 0.6;

      // Specular highlight
      color = color + vec3<f32>(1.0, 0.95, 0.9) * spec * 0.8;

      // Internal glow / subsurface scattering approximation
      let sss = pow(max(dot(n, -lightDir), 0.0), 2.0) * 0.3;
      color = color + crystalCol * sss * prismIntensity;

      // Caustics
      let caustic = crystalCaustics(p, n, lightDir, time);
      color = color + vec3<f32>(0.8, 0.9, 1.0) * caustic * causticStrength;

      // Rim light
      let rim = pow(1.0 - max(dot(n, v), 0.0), 4.0);
      color = color + crystalCol * rim * 0.5;

      // Alpha = crystal thickness: thin edges transparent, thick centers opaque
      alpha = mix(0.25, 0.95, thickness);
      // Boost alpha where Fresnel is high (edges glow more)
      alpha = mix(alpha, 0.6, fresnelScalar * 0.5);
    }
  } else {
    // Background
    color = vec3<f32>(0.02, 0.03, 0.06);
    // Subtle gradient
    color = color + vec3<f32>(0.01, 0.01, 0.03) * (1.0 - uv.y);
    alpha = 0.0;
    thickness = 0.0;
  }

  // Ripple interaction: add crystal seeds
  let rippleCount = min(u32(u.config.y), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let rAge = time - ripple.z;
    if (rAge < 0.0 || rAge > 2.0) { continue; }
    let rDist = length(uv - ripple.xy);
    let rInfluence = smoothstep(0.1, 0.0, rDist) * exp(-rAge * 2.0);
    color = color + vec3<f32>(0.9, 0.8, 1.0) * rInfluence * 0.5;
    alpha = alpha + rInfluence * 0.3;
  }

  // Temporal blend for smooth growth transitions
  let prevColor = prevState.rgb;
  let prevAlpha = prevState.a;
  color = mix(color, prevColor, 0.08);
  alpha = mix(alpha, prevAlpha, 0.05);

  color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.5));
  color = color / (1.0 + color * 0.3);
  color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
  alpha = clamp(alpha, 0.0, 1.0);

  // Store state: R=thickness, G=growth, B=unused, A=alpha
  textureStore(dataTextureA, coord, vec4<f32>(thickness, storedGrowth, 0.0, alpha));

  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));

  // Depth
  let depthVal = clamp(t / 30.0, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
