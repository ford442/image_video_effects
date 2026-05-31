// ═══════════════════════════════════════════════════════════════════
//  Electric Eel Storm
//  Category: generative
//  Features: generative, audio-reactive, temporal, chromatic, mouse-driven
//  Complexity: Very High
//  Description: Electric eels swimming through a conductive storm
//               cloud, discharging arcs between them. Bass drives
//               eel body pulses, mids create storm turbulence,
//               treble triggers lightning arcs. Mouse attracts
//               the eel school.
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

fn hash12(p: vec2<f32>) -> vec2<f32> {
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

// Eel path: serpentine swimming motion
fn eelPosition(index: f32, time: f32, pulseSpeed: f32, mouse: vec2<f32>) -> vec2<f32> {
  let fi = index;
  let baseY = 0.3 + fi * 0.15 + sin(fi * 2.7) * 0.1;
  let baseX = 0.5 + sin(time * 0.2 + fi * 1.3) * 0.25;

  // Serpentine body wave
  let bodyWave = sin(time * pulseSpeed * 2.0 + fi * 1.1) * 0.06;

  // Mouse attraction
  let attract = (mouse - vec2<f32>(baseX, baseY)) * 0.15;
  let attractSmooth = attract * (0.5 + 0.5 * sin(time + fi));

  return vec2<f32>(baseX + bodyWave + attractSmooth.x, baseY + attractSmooth.y);
}

// Eel body SDF
fn sdEel(uv: vec2<f32>, pos: vec2<f32>, time: f32, pulseSpeed: f32, bass: f32) -> f32 {
  let toPixel = uv - pos;
  // Eel is elongated horizontally
  let bodyLength = 0.18 + bass * 0.03;
  let bodyWidth = 0.015 + sin(time * pulseSpeed * 3.0) * 0.003 * (1.0 + bass);

  // Tapered capsule
  let dx = abs(toPixel.x);
  let dy = abs(toPixel.y);
  let taper = 1.0 - smoothstep(0.0, bodyLength, dx);
  let w = bodyWidth * taper;
  let d = length(vec2<f32>(max(dx - bodyLength, 0.0), dy)) - w;
  return d;
}

// Lightning arc between two points
fn lightningArc(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>, time: f32, seed: f32) -> f32 {
  let ab = b - a;
  let abLen = length(ab);
  let abDir = ab / max(abLen, 0.0001);
  let abN = vec2<f32>(-abDir.y, abDir.x);

  let toPixel = uv - a;
  let proj = clamp(dot(toPixel, abDir), 0.0, abLen);
  let closest = a + abDir * proj;
  let t = proj / max(abLen, 0.0001);

  // Jagged displacement
  let jagged = sin(t * 20.0 + seed * 10.0) * 0.015;
  let jagged2 = sin(t * 45.0 - seed * 7.0 + time * 8.0) * 0.008;
  let displaced = closest + abN * (jagged + jagged2);

  let d = length(uv - displaced);
  let arcWidth = 0.003 + sin(time * 20.0 + seed) * 0.001;
  return smoothstep(arcWidth, 0.0, d);
}

// Storm cloud turbulence
fn stormCloud(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
  let p = uv * 3.0 + vec2<f32>(time * 0.1, time * 0.05);
  let n1 = fbm2(p, 4);
  let n2 = fbm2(p * 2.0 + vec2<f32>(100.0, 0.0), 3);
  let cloud = smoothstep(0.4 - intensity * 0.2, 0.7, n1) * 0.5;
  let turbulence = smoothstep(0.3, 0.6, n2) * intensity * 0.3;
  return cloud + turbulence;
}

// Branching lightning bolt
fn lightningBolt(uv: vec2<f32>, start: vec2<f32>, time: f32, seed: f32, treble: f32) -> f32 {
  var bolt = 0.0;
  let segments = 12;
  var pos = start;
  let downward = vec2<f32>(0.0, -1.0);

  for (var i: i32 = 0; i < segments; i = i + 1) {
    let fi = f32(i);
    let nextPos = pos + downward * (0.06 + hash21(vec2<f32>(fi, seed)) * 0.04);
    nextPos.x += sin(fi * 3.0 + seed * 5.0 + time * 10.0) * 0.03 * (1.0 + treble);

    let arc = lightningArc(uv, pos, nextPos, time, seed + fi);
    bolt = max(bolt, arc);

    // Branching
    if (i > 3 && hash21(vec2<f32>(fi, seed + 1.0)) > 0.6) {
      let branchPos = nextPos + vec2<f32>(0.03, 0.0) * sign(hash21(vec2<f32>(fi, seed + 2.0)) - 0.5);
      let branch = lightningArc(uv, nextPos, branchPos, time, seed + fi + 10.0);
      bolt = max(bolt, branch * 0.6);
    }
    pos = nextPos;
  }
  return bolt;
}

fn hueToRGB(hue: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
  return clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv01 = vec2<f32>(gid.xy) / res;
  let uv = uv01;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let eelCount = i32(u.zoom_params.x * 4.0 + 2.0);
  let stormIntensity = u.zoom_params.y * 1.5;
  let pulseSpeed = u.zoom_params.z * 3.0 + 1.0;
  let lightningFreq = u.zoom_params.w;

  // Storm cloud background
  let cloud = stormCloud(uv, time, stormIntensity);
  var col = vec3<f32>(0.04, 0.05, 0.08);
  col += vec3<f32>(0.15, 0.18, 0.25) * cloud;

  // Eels and their discharges
  var eelMask = 0.0;
  var eelGlow = 0.0;
  var arcs = 0.0;
  var prevEelPos = vec2<f32>(0.0);

  for (var i: i32 = 0; i < eelCount; i = i + 1) {
    let fi = f32(i);
    let eelPos = eelPosition(fi, time, pulseSpeed, mouse);
    let d = sdEel(uv, eelPos, time, pulseSpeed, bass);

    // Eel body
    let body = smoothstep(0.005, 0.0, d);
    eelMask += body;

    // Eel glow
    let glow = 1.0 / (1.0 + d * d * 2000.0);
    eelGlow += glow * (0.5 + bass * 0.5);

    // Discharge arcs between nearby eels
    if (i > 0) {
      let distBetween = length(eelPos - prevEelPos);
      if (distBetween < 0.4) {
        let arcSeed = fi * 3.7 + time * 0.1;
        let arc = lightningArc(uv, prevEelPos, eelPos, time, arcSeed);
        arcs += arc * (0.3 + treble * 0.7);
      }
    }
    prevEelPos = eelPos;
  }

  // Treble triggers lightning bolts from cloud top
  var bolts = 0.0;
  let boltTrigger = step(0.85, sin(time * 5.0 * lightningFreq) * 0.5 + 0.5 + treble * 0.3);
  if (boltTrigger > 0.0) {
    for (var b: i32 = 0; b < 3; b = b + 1) {
      let bf = f32(b);
      let startX = 0.2 + bf * 0.3 + sin(time + bf) * 0.1;
      let bolt = lightningBolt(uv, vec2<f32>(startX, 0.9), time, bf * 7.3 + time, treble);
      bolts += bolt * boltTrigger;
    }
  }

  // Eel color: bioluminescent blue-green with pulse
  let eelHue = 0.45 + bass * 0.05 + sin(time * pulseSpeed) * 0.02;
  let eelCol = hueToRGB(eelHue) * (0.8 + mids * 0.4);

  // Arc color: electric violet-white
  let arcCol = vec3<f32>(0.7, 0.6, 1.0) * arcs * (1.0 + treble * 2.0);

  // Bolt color: bright white-blue
  let boltCol = vec3<f32>(0.9, 0.95, 1.0) * bolts * (1.5 + treble);

  // Combine
  col += eelCol * eelMask;
  col += eelCol * eelGlow * 0.3;
  col += arcCol;
  col += boltCol;

  // Storm turbulence glow from mids
  let turbGlow = fbm2(uv * 5.0 + time * 0.3, 3) * mids * stormIntensity;
  col += vec3<f32>(0.2, 0.15, 0.3) * turbGlow;

  // Chromatic dispersion on lightning (strong)
  let cStr = 0.006 + treble * 0.01;
  let cDir = normalize(uv - vec2<f32>(0.5) + 0.001);
  let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * 1.5, 0.0).r;
  let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * 1.0, 0.0).g;
  let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cStr * 0.8, 0.0).b;

  // Temporal feedback
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
  var fbCol = mix(col, prev.rgb * 0.9, 0.06 + bass * 0.02);

  // Blend chromatic offsets
  fbCol.r = mix(fbCol.r, prevR * 0.9, 0.05 + arcs * 0.05);
  fbCol.g = mix(fbCol.g, prevG * 0.9, 0.05 + bolts * 0.05);
  fbCol.b = mix(fbCol.b, prevB * 0.9, 0.05 + eelGlow * 0.03);

  // Semantic alpha: eels and arcs are opaque, storm is translucent
  let alpha = clamp(eelMask * 0.9 + eelGlow * 0.4 + arcs * 0.7 + bolts * 0.8 + cloud * 0.3, 0.0, 1.0);

  // Depth: eels in foreground, clouds behind, lightning at mid-depth
  let depth = clamp(0.9 - eelMask * 0.3 - eelGlow * 0.2 + cloud * 0.15, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(fbCol, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(fbCol, alpha));
}
