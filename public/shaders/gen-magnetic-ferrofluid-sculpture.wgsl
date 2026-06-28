// ═══════════════════════════════════════════════════════════════════
//  Magnetic Ferrofluid-Sculpture
//  Category: generative
//  Features: raymarched, ferrofluid, magnetic-spikes, iridescence,
//            audio-reactive, mouse-driven, liquid-metal, upgraded-rgba,
//            depth-aware, chromatic
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

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash3(p: vec3<f32>) -> f32 {
  let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  let q2 = q + dot(q, q.yzx + 33.33);
  return fract((q2.x + q2.y) * q2.z);
}

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rot3X(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

// ─── SDF Primitives ───
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdCone(p: vec3<f32>, h: f32, r: f32) -> f32 {
  let q = vec2<f32>(length(p.xz), p.y);
  let d1 = -p.y - h;
  let d2 = max(q.x - r * (1.0 - p.y / h), -p.y);
  return length(max(vec2<f32>(d1, d2), vec2<f32>(0.0))) + min(max(d1, d2), 0.0);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── 3D Noise ───
fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0 + i.z * 113.0;
  var v = 0.0;
  for (var k: i32 = 0; k <= 1; k = k + 1) {
    for (var j: i32 = 0; j <= 1; j = j + 1) {
      for (var i2: i32 = 0; i2 <= 1; i2 = i2 + 1) {
        let corner = vec3<f32>(f32(i2), f32(j), f32(k));
        let h2 = hash3(i + corner);
        v += h2 * (1.0 - abs(corner.x - f.x)) * (1.0 - abs(corner.y - f.y)) * (1.0 - abs(corner.z - f.z));
      }
    }
  }
  return v;
}

// ─── Ferrofluid SDF ───
fn ferrofluid(p: vec3<f32>, time: f32, bass: f32, spikeDensity: f32,
              viscosity: f32, magneticPull: f32, mousePos: vec3<f32>) -> f32 {
  var pos = p;

  // Base sphere with organic noise displacement
  let baseRadius = 1.2 + bass * 0.3;
  var d = sdSphere(pos, baseRadius);

  // Noise-based surface ripples (liquid dynamics)
  let noiseFreq = 3.0 + spikeDensity * 5.0;
  let noiseAmp = 0.08 * viscosity + bass * 0.1;
  let surfaceNoise = noise3(pos * noiseFreq + time * 0.5) * noiseAmp;
  d += surfaceNoise;

  // Magnetic spikes - radial protrusions
  let dir = normalize(pos);
  let phi = atan2(dir.z, dir.x);
  let theta = acos(sat(dir.y));

  // Generate spike field using domain repetition around sphere
  let numSpikes = 16.0 + spikeDensity * 32.0;
  let spikeBaseHeight = 0.3 + bass * 0.8;

  for (var i: i32 = 0; i < 6; i = i + 1) {
    let fi = f32(i);
    let spikeAngle = fi * 6.28318 / numSpikes + time * 0.1 * (1.0 + fi * 0.1);
    let spikeTheta = 1.57 + sin(fi * 2.3 + time * 0.3) * 0.8;
    let spikeDir = vec3<f32>(sin(spikeTheta) * cos(spikeAngle), cos(spikeTheta), sin(spikeTheta) * sin(spikeAngle));
    let spikeTip = spikeDir * (baseRadius + spikeBaseHeight * (1.0 + sin(time * 2.0 + fi) * 0.3));
    let spikeD = sdCone(pos - spikeTip + spikeDir * spikeBaseHeight * 0.5, spikeBaseHeight * 0.5, 0.08 * viscosity);
    d = smin(d, spikeD, 0.15 * viscosity);
  }

  // Secondary fine spikes (high frequency)
  let fineSpikes = sin(phi * 20.0 + time) * cos(theta * 15.0 - time * 1.3) * 0.15 * bass;
  d += fineSpikes;

  // Mouse magnetic attraction - pull nearby fluid toward cursor
  let mDist = length(pos - mousePos);
  let magRadius = 3.0;
  if (mDist < magRadius) {
    let pull = (1.0 - mDist / magRadius) * magneticPull * 2.0;
    let toMouse = normalize(mousePos - pos);
    let bulgePos = pos - toMouse * pull * 0.5;
    let bulge = sdSphere(bulgePos - pos * 0.3, pull * 0.4);
    d = smin(d, bulge, 0.3);
  }

  // Orbiting droplets
  let dropletOrbit = 2.2 + bass * 0.5;
  let dropletPos = vec3<f32>(
    sin(time * 0.7) * dropletOrbit,
    cos(time * 1.1) * dropletOrbit * 0.6,
    sin(time * 0.5) * dropletOrbit
  );
  let droplet = sdSphere(pos - dropletPos, 0.25 + bass * 0.15);
  d = smin(d, droplet, 0.4);

  return d;
}

fn map(p: vec3<f32>, time: f32, bass: f32, spikeDensity: f32,
       viscosity: f32, magneticPull: f32, mousePos: vec3<f32>) -> vec2<f32> {
  let d = ferrofluid(p, time, bass, spikeDensity, viscosity, magneticPull, mousePos);
  return vec2<f32>(d, 1.0);
}

fn calcNormal(p: vec3<f32>, time: f32, bass: f32, spikeDensity: f32,
              viscosity: f32, magneticPull: f32, mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  return normalize(vec3<f32>(
    map(p + e.xyy, time, bass, spikeDensity, viscosity, magneticPull, mousePos).x -
    map(p - e.xyy, time, bass, spikeDensity, viscosity, magneticPull, mousePos).x,
    map(p + e.yxy, time, bass, spikeDensity, viscosity, magneticPull, mousePos).x -
    map(p - e.yxy, time, bass, spikeDensity, viscosity, magneticPull, mousePos).x,
    map(p + e.yyx, time, bass, spikeDensity, viscosity, magneticPull, mousePos).x -
    map(p - e.yyx, time, bass, spikeDensity, viscosity, magneticPull, mousePos).x
  ));
}

// ─── Iridescence ───
fn iridescent(nDotV: f32, shift: f32) -> vec3<f32> {
  let t = nDotV * 3.14159 + shift;
  return vec3<f32>(
    0.5 + 0.5 * cos(t + 0.0),
    0.5 + 0.5 * cos(t + 2.09),
    0.5 + 0.5 * cos(t + 4.18)
  );
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
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
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let spikeDensity = u.zoom_params.x;
  let viscosity = mix(0.5, 1.0, u.zoom_params.y);
  let iridescence = u.zoom_params.z;
  let magneticPull = u.zoom_params.w;

  // Mouse in 3D - screen top = UP, flip Y
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = 1.0 - mouseUV.y;
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (mouseUV.y * 2.0 - 1.0) * 3.0,
    0.0
  );

  // Camera
  let camDist = 4.5 + sin(time * 0.2) * 0.5;
  let camAng = time * 0.15 + mouseUV.x * 0.5;
  let camHeight = mouseY * 1.0;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch
  var t = 0.0;
  var hit = false;
  var hitPos = vec3<f32>(0.0);
  var depth = 0.0;

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let pos = ro + rd * t;
    let res = map(pos, time, bass, spikeDensity, viscosity, magneticPull, mousePos);
    if (res.x < 0.005) {
      hit = true;
      hitPos = pos;
      depth = t;
      break;
    }
    if (t > 20.0) { break; }
    t = t + res.x * 0.7;
  }

  var col = vec3<f32>(0.01, 0.015, 0.025);
  col += vec3<f32>(0.02, 0.03, 0.05) * max(rd.y, 0.0);

  if (hit) {
    let n = calcNormal(hitPos, time, bass, spikeDensity, viscosity, magneticPull, mousePos);
    let viewDir = -rd;
    let nDotV = sat(dot(n, viewDir));

    let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
    let lightDir2 = normalize(vec3<f32>(-0.3, 0.5, -0.7));
    let lightDir3 = normalize(mousePos - hitPos + vec3<f32>(0.0, 2.0, 0.0));

    let diff = sat(dot(n, lightDir));
    let diff2 = sat(dot(n, lightDir2)) * 0.5;
    let diff3 = sat(dot(n, lightDir3)) * 0.3;

    let hal = normalize(lightDir - rd);
    let spec = pow(sat(dot(n, hal)), 64.0);
    let hal2 = normalize(lightDir2 - rd);
    let spec2 = pow(sat(dot(n, hal2)), 128.0) * 0.5;

    let fresnel = pow(1.0 - nDotV, 5.0);

    // Base liquid metal
    let baseMetal = vec3<f32>(0.08, 0.09, 0.12);

    // Iridescent thin-film
    let ired = iridescent(nDotV, time * 0.3 + mid * 2.0) * iridescence;
    let metal = baseMetal + ired * 0.7;

    // Specular highlights (chrome-like)
    let specCol = vec3<f32>(0.8, 0.85, 0.9) * (spec + spec2) * 2.0;

    // Rim lighting
    let rim = vec3<f32>(0.3, 0.4, 0.6) * fresnel * 0.8;

    // Combine lighting
    col = metal * (0.2 + diff * 0.6 + diff2 * 0.3 + diff3 * 0.2);
    col = col + specCol + rim;

    // Audio-reactive glow on peaks
    let spikeHighlight = pow(1.0 - nDotV, 3.0) * bass * 0.5;
    col = col + vec3<f32>(0.5, 0.3, 0.8) * spikeHighlight;

    // Deep ambient occlusion in valleys
    let ao = 1.0 - f32(100) / f32(100) * 0.3;
    col = col * (0.3 + 0.7 * ao);

    // Depth fog
    col = mix(col, vec3<f32>(0.01, 0.015, 0.025), 1.0 - exp(-0.03 * depth));
  } else {
    depth = 20.0;
  }

  // Temporal persistence (extraBuffer for bass_env smoothing)
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let bassEnv = extraBuffer[0];
  extraBuffer[0] = mix(bassEnv, bass, 0.05);
  col = mix(col, prev.rgb * 0.95, 0.03 + extraBuffer[0] * 0.02);

  // Tone map
  col = acesToneMap(col * 1.3);

  let alpha = hit ? sat(0.85 + (1.0 - depth / 8.0) * 0.15) : 0.0;
  let finalDepth = sat(0.95 - depth * 0.04);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, alpha));
}
