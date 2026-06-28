// ----------------------------------------------------------------
// Ethereal Quantum-Hologram Bonsai
// Category: generative
// ----------------------------------------------------------------
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            hologram, l-system, quantum, iridescence, curl-noise, upgraded-rgba
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

const PI : f32 = 3.14159265358979323846;
const MAX_STEPS : i32 = 80;
const MAX_DIST : f32 = 30.0;
const SURF_DIST : f32 = 0.001;

fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
  let a = normalize(axis);
  let s = sin(angle);
  let c = cos(angle);
  let oc = 1.0 - c;
  return mat3x3<f32>(
    c + a.x*a.x*oc,       a.x*a.y*oc - a.z*s,  a.x*a.z*oc + a.y*s,
    a.y*a.x*oc + a.z*s,   c + a.y*a.y*oc,      a.y*a.z*oc - a.x*s,
    a.z*a.x*oc - a.y*s,   a.z*a.y*oc + a.x*s,  c + a.z*a.z*oc
  );
}

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash3(i+vec3<f32>(0,0,0)), hash3(i+vec3<f32>(1,0,0)), u.x),
        mix(hash3(i+vec3<f32>(0,1,0)), hash3(i+vec3<f32>(1,1,0)), u.x), u.y),
    mix(mix(hash3(i+vec3<f32>(0,0,1)), hash3(i+vec3<f32>(1,0,1)), u.x),
        mix(hash3(i+vec3<f32>(0,1,1)), hash3(i+vec3<f32>(1,1,1)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0; var a = 0.5; var pp = p;
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

fn bass_env(prev: f32, curr: f32, att: f32, rel: f32) -> f32 {
  if(curr > prev) { return mix(prev, curr, att); }
  else { return mix(prev, curr, rel); }
}

// ═══════════════════════════════════════════════════════════════
//  BONSAI L-SYSTEM SDF (simulated via recursive cylinders)
// ═══════════════════════════════════════════════════════════════
fn sdCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
  let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
  return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn bonsaiBranch(p: vec3<f32>, pos: vec3<f32>, dir: vec3<f32>, length: f32, radius: f32) -> f32 {
  let local = p - pos;
  // Align cylinder to direction
  let up = vec3<f32>(0.0, 1.0, 0.0);
  let rotAxis = cross(up, dir);
  let rotAngle = acos(clamp(dot(up, dir), -1.0, 1.0));
  var aligned = local;
  if(length(rotAxis) > 0.001) {
    aligned = rot3D(rotAxis, rotAngle) * local;
  }
  return sdCylinder(aligned, length * 0.5, radius);
}

fn bonsaiSDF(p: vec3<f32>, time: f32, complexity: f32, instability: f32) -> f32 {
  var d = 1000.0;

  // Curl noise displacement for holographic instability
  let disp = vec3<f32>(
    fbm(p * 1.5 + time * 0.3),
    fbm(p * 1.5 + time * 0.3 + 10.0),
    fbm(p * 1.5 + time * 0.3 + 20.0)
  ) * instability * 0.1;
  let pp = p + disp;

  // Main trunk
  d = smin(d, bonsaiBranch(pp, vec3<f32>(0.0, -1.5, 0.0), vec3<f32>(0.0, 1.0, 0.0), 3.0, 0.12), 0.05);

  // Branch levels
  let levels = i32(mix(2.0, 5.0, complexity));
  for(var level = 0; level < levels; level++) {
    let lvlF = f32(level);
    let branchY = -0.5 + lvlF * 0.6;
    let nBranches = i32(mix(2.0, 4.0, complexity)) + level;

    for(var b = 0; b < nBranches; b++) {
      let bf = f32(b);
      let angle = bf * (6.28 / f32(nBranches)) + lvlF * 1.3 + time * 0.1;
      let branchLen = 0.8 - lvlF * 0.15;
      let branchRad = 0.08 - lvlF * 0.015;
      let tilt = 0.3 + lvlF * 0.2;

      let dir = vec3<f32>(sin(angle) * tilt, cos(tilt), cos(angle) * tilt);
      let pos = vec3<f32>(sin(angle) * 0.1, branchY, cos(angle) * 0.1);

      d = smin(d, bonsaiBranch(pp, pos, dir, branchLen, branchRad), 0.08);

      // Leaves (quantum droplets)
      let leafPos = pos + dir * branchLen;
      let leafSize = 0.04 - lvlF * 0.008;
      d = smin(d, sdSphere(pp - leafPos, leafSize), 0.04);
    }
  }

  // Root system
  for(var r = 0; r < 5; r++) {
    let rf = f32(r);
    let angle = rf * (6.28 / 5.0) + time * 0.05;
    let rootDir = vec3<f32>(sin(angle) * 0.5, -0.8, cos(angle) * 0.5);
    let rootPos = vec3<f32>(sin(angle) * 0.05, -1.5, cos(angle) * 0.05);
    d = smin(d, bonsaiBranch(pp, rootPos, normalize(rootDir), 1.0, 0.06), 0.06);
  }

  return d;
}

fn calcNormal(p: vec3<f32>, time: f32, complexity: f32, instability: f32) -> vec3<f32> {
  let e = vec2<f32>(SURF_DIST * 2.0, 0.0);
  return normalize(vec3<f32>(
    bonsaiSDF(p + e.xyy, time, complexity, instability) - bonsaiSDF(p - e.xyy, time, complexity, instability),
    bonsaiSDF(p + e.yxy, time, complexity, instability) - bonsaiSDF(p - e.yxy, time, complexity, instability),
    bonsaiSDF(p + e.yyx, time, complexity, instability) - bonsaiSDF(p - e.yyx, time, complexity, instability)
  ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
  if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

  let uv = (fragCoord - 0.5 * res) / res.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let complexity = u.zoom_params.x;      // Branch Complexity
  let instability = u.zoom_params.y;     // Hologram Instability
  let glow = u.zoom_params.z;            // Ambient Glow
  let audioReact = u.zoom_params.w;      // Audio Reactivity

  // ═══ CHUNK: bass_env smoothing ═══
  let prevBass = extraBuffer[0];
  let bassSmooth = bass_env(prevBass, bass, 0.08, 0.02);
  extraBuffer[0] = bassSmooth;

  // Camera
  let mouseUV = u.zoom_config.yz;
  let mouseY = 1.0 - mouseUV.y;  // Flip Y: screen top = up
  let camAng = time * 0.05 + mouseUV.x * 0.3;
  let camDist = 4.0;
  let ro = vec3<f32>(
    cos(camAng) * camDist,
    1.0 + mouseY * 1.0,
    sin(camAng) * camDist
  );
  let ta = vec3<f32>(0.0, 0.5, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
  let vv = cross(uu, ww);
  let rd = normalize(ww + uu * uv.x + vv * uv.y);

  // Mouse gravity well (quantum gardener)
  let mouseWorld = vec3<f32>(
    (mouseUV.x - 0.5) * 4.0,
    mouseY * 3.0,
    0.0
  );

  // Raymarch
  var t = 0.0;
  var d = 0.0;
  for(var i = 0; i < MAX_STEPS; i++) {
    let p = ro + rd * t;
    let pp = p;
    // Apply mouse gravity lensing
    let toMouse = mouseWorld - p;
    let mDist = length(toMouse);
    let lensing = toMouse / (mDist * mDist + 0.1) * 0.05 * length(u.zoom_config.yz);
    d = bonsaiSDF(pp + lensing, time, complexity, instability);
    if(d < SURF_DIST || t > MAX_DIST) { break; }
    t += d * 0.8;
  }

  // Shading
  var col = vec3<f32>(0.0);
  if(t < MAX_DIST) {
    let p = ro + rd * t;
    let n = calcNormal(p, time, complexity, instability);

    // Lighting
    let lightDir = normalize(vec3<f32>(2.0, 3.0, -1.0));
    let diff = max(dot(n, lightDir), 0.0);
    let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0);
    let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 2.0);

    // Holographic iridescence (jade to magenta)
    let holoHue = fract(dot(p, vec3<f32>(1.0, 2.3, 3.7)) * 0.2 + time * 0.15);
    let holoCol = mix(
      vec3<f32>(0.0, 0.5, 0.2),   // Deep jade
      vec3<f32>(0.8, 0.1, 0.6),   // Luminous magenta
      holoHue
    );

    // Base bark color
    let barkCol = mix(
      vec3<f32>(0.1, 0.08, 0.05),
      holoCol,
      fresnel * instability
    );

    col = barkCol * (diff * 0.6 + 0.3) + spec * vec3<f32>(0.8, 0.9, 1.0) * 0.5;

    // Chromatic aberration (holographic glitch)
    let glitch = noise3(p * 5.0 + time * 2.0) * instability * 0.3;
    col.r += glitch * 0.2;
    col.b -= glitch * 0.1;

    // Quantum droplet glow (leaves)
    let leafGlow = fresnel * glow * vec3<f32>(0.3, 0.8, 0.5);
    col += leafGlow;

    // Audio holographic shimmer
    col += vec3<f32>(0.1, 0.2, 0.3) * bassSmooth * audioReact * fresnel;

    // Distance fade
    col *= exp(-t * 0.08);
  }

  // Ambient glow / background
  let bgGrad = mix(
    vec3<f32>(0.02, 0.03, 0.04),
    vec3<f32>(0.05, 0.08, 0.1),
    uv.y * 0.5 + 0.5
  );
  col = mix(bgGrad, col, smoothstep(MAX_DIST, 0.0, t));

  // Root ripple from bass peaks
  let rootRipple = sin(uv.x * 10.0 + time * 3.0) * cos(uv.y * 8.0) * bassSmooth * audioReact * 0.1;
  col += vec3<f32>(0.0, 0.1, 0.2) * max(rootRipple, 0.0);

  // Temporal feedback
  let prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
  col = mix(prevCol, col, 0.3);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
