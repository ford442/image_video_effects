// ═══════════════════════════════════════════════════════════════════
//  Aurora Borealis Loom
//  Category: generative
//  Features: generative, audio-reactive, temporal, chromatic, mouse-driven
//  Complexity: High
//  Description: Aurora curtains woven like fabric on a celestial loom.
//               Threads of light interlace with weft and warp patterns.
//               Bass swells the weave, mids shift hue, treble adds
//               bead-like ionization nodes. Mouse pulls the fabric.
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
    f *= 2.01;
  }
  return v;
}

// Aurora curtain SDF
fn auroraCurtain(uv: vec2<f32>, xPos: f32, width: f32, time: f32, speed: f32) -> f32 {
  let dx = uv.x - xPos;
  // Curtain waves
  let wave1 = sin(uv.y * 4.0 + time * speed + xPos * 3.0) * 0.08;
  let wave2 = sin(uv.y * 7.0 - time * speed * 0.7 + xPos * 5.0) * 0.04;
  let wave3 = sin(uv.y * 2.5 + time * speed * 0.3) * 0.12;
  let curtainEdge = dx - wave1 - wave2 - wave3;
  let curtain = smoothstep(width, 0.0, abs(curtainEdge));
  // Vertical fade
  let vFade = smoothstep(0.0, 0.3, uv.y) * smoothstep(1.0, 0.7, uv.y);
  return curtain * vFade;
}

// Weft thread pattern
fn weftPattern(uv: vec2<f32>, density: f32, time: f32) -> f32 {
  let threadY = fract(uv.y * density);
  let thread = smoothstep(0.15, 0.0, abs(threadY - 0.5));
  // Slight weave offset per row
  let row = floor(uv.y * density);
  let offset = sin(row * 1.7 + time * 0.2) * 0.02;
  let threadX = fract(uv.x * density + offset);
  let crossThread = smoothstep(0.12, 0.0, abs(threadX - 0.5));
  return max(thread, crossThread * 0.6);
}

// Warp thread pattern
fn warpPattern(uv: vec2<f32>, density: f32, time: f32) -> f32 {
  let threadX = fract(uv.x * density);
  let col = floor(uv.x * density);
  let offset = sin(col * 2.3 + time * 0.15) * 0.02;
  let threadY = fract(uv.y * density + offset);
  let warp = smoothstep(0.1, 0.0, abs(threadX - 0.5));
  let weftCross = smoothstep(0.12, 0.0, abs(threadY - 0.5));
  return max(warp, weftCross * 0.5);
}

// Ionization nodes (beads of light)
fn ionizationNodes(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
  var nodes = 0.0;
  let nodeCount = 6;
  for (var i: i32 = 0; i < nodeCount; i = i + 1) {
    let fi = f32(i);
    let nx = fi / f32(nodeCount) + sin(time * 0.4 + fi * 2.1) * 0.08;
    let ny = 0.3 + sin(time * 0.3 + fi * 1.3) * 0.15 + fbm2(vec2<f32>(fi, time * 0.1), 2) * 0.1;
    let nPos = vec2<f32>(nx, ny);
    let d = length(uv - nPos);
    let flash = step(0.7, sin(time * 3.0 + fi * 4.7) * 0.5 + 0.5) * intensity;
    nodes += exp(-d * d * 300.0) * flash;
  }
  return nodes;
}

fn hueToRGB(hue: f32) -> vec3<f32> {
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
  var uv = uv01;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let weaveDensity = u.zoom_params.x * 20.0 + 8.0;
  let hueSpeed = u.zoom_params.y * 0.5 + 0.05;
  let ionization = u.zoom_params.z;
  let curtainFlow = u.zoom_params.w * 0.3 + 0.1;

  // Mouse pulls the fabric (warps UV toward mouse)
  let mouseDist = length(uv01 - mouse);
  let pullStrength = exp(-mouseDist * mouseDist * 4.0) * 0.08;
  uv += (mouse - uv01) * pullStrength;

  // Bass swells the weave width
  let swell = 1.0 + bass * 0.5;

  // Multiple aurora curtains
  var curtains = 0.0;
  var curtainCol = vec3<f32>(0.0);
  let numCurtains = 5;
  for (var i: i32 = 0; i < numCurtains; i = i + 1) {
    let fi = f32(i);
    let xPos = 0.15 + fi * 0.18 + sin(time * curtainFlow + fi * 1.3) * 0.06;
    let width = (0.04 + fi * 0.005) * swell;
    let c = auroraCurtain(uv, xPos, width, time, curtainFlow * 3.0 + 0.2);

    // Mids shift hue through spectrum per curtain
    let hue = fract(fi * 0.15 + time * hueSpeed + mids * 0.2);
    let cCol = hueToRGB(hue);
    curtains += c;
    curtainCol += cCol * c;
  }

  // Normalize curtain color
  curtainCol = select(curtainCol / max(curtains, 0.001), vec3<f32>(0.0), curtains < 0.001);

  // Weave pattern overlay
  let weft = weftPattern(uv, weaveDensity, time);
  let warp = warpPattern(uv, weaveDensity * 0.8, time);
  let weave = max(weft, warp * 0.7);

  // Weave glow tinted by curtain color
  let weaveCol = curtainCol * weave * 0.5;

  // Ionization nodes from treble
  let nodes = ionizationNodes(uv, time, treble * ionization);
  let nodeCol = vec3<f32>(0.9, 0.95, 1.0) * nodes * (1.0 + ionization);

  // Starfield background
  let starNoise = hash21(floor(uv * 200.0));
  let stars = step(0.995, starNoise) * hash21(floor(uv * 200.0) + vec2<f32>(1.0, 0.0));
  let bg = vec3<f32>(0.02, 0.03, 0.06) + vec3<f32>(0.6, 0.7, 0.9) * stars * 0.5;

  // Combine
  var col = bg;
  col += curtainCol * curtains * 0.8;
  col += weaveCol * swell;
  col += nodeCol;

  // Atmospheric noise
  let atmos = fbm2(uv * 4.0 + time * 0.05, 3) * 0.1;
  col += vec3<f32>(0.1, 0.2, 0.3) * atmos * curtains;

  // Chromatic dispersion: R/G/B offset along curtain direction
  let cStr = 0.005 + treble * 0.008;
  let cDir = vec2<f32>(0.0, 1.0);
  let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * 1.3, 0.0).r;
  let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * 0.9, 0.0).g;
  let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * 0.5, 0.0).b;

  // Temporal feedback
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
  var fbCol = mix(col, prev.rgb * 0.94, 0.05 + bass * 0.02);

  // Blend chromatic channels
  fbCol.r = mix(fbCol.r, prevR * 0.94, 0.04 + mids * 0.02);
  fbCol.g = mix(fbCol.g, prevG * 0.94, 0.04 + treble * 0.02);
  fbCol.b = mix(fbCol.b, prevB * 0.94, 0.04 + bass * 0.02);

  // Semantic alpha: based on curtain intensity and weave presence
  let alpha = clamp(curtains * 0.8 + weave * 0.3 + nodes * 0.5, 0.0, 1.0);

  // Depth: curtains in front, stars behind
  let depth = clamp(0.8 - curtains * 0.5 + weave * 0.1, 0.0, 1.0);

  fbCol = acesToneMap(fbCol * 1.1);
  textureStore(writeTexture, gid.xy, vec4<f32>(fbCol, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(fbCol, alpha));
}
