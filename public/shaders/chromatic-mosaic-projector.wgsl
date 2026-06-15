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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & noise ────────────────────────────────────────────────
fn hashf(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < oct; i = i + 1) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

// ── Color & tone ────────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (t <= 66.0) { r = 1.0; }
  else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t <= 19.0) { b = 0.0; }
  else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// ── Voronoi mosaic ──────────────────────────────────────────────
fn voronoi(uv: vec2<f32>, cellSize: f32, distort: f32, time: f32) -> vec3<f32> {
  let scaled = uv * cellSize;
  let cellId = floor(scaled);
  let fracPos = fract(scaled);
  var minDist = 1.0;
  var nearCell = cellId;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = cellId + vec2<f32>(f32(x), f32(y));
      let h = hash22(neighbor);
      let anim = vec2<f32>(
        sin(time * 0.8 + h.x * TAU) * distort,
        cos(time * 0.6 + h.y * TAU) * distort
      );
      let point = h + anim + vec2<f32>(f32(x), f32(y)) - fracPos;
      let d = length(point);
      let closer = f32(d < minDist);
      minDist = mix(minDist, d, closer);
      nearCell = mix(nearCell, neighbor, closer);
    }
  }
  return vec3<f32>(minDist, nearCell.x, nearCell.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let aspect = res.x / res.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  // Parameters
  let cellSizeBase = mix(8.0, 80.0, u.zoom_params.x);
  let cellSize = cellSizeBase * (1.0 + bass * 0.25);
  let chromaticStrength = u.zoom_params.y * 0.08 * (1.0 + mids * 2.0);
  let voronoiDistort = u.zoom_params.z * 0.5 * (1.0 + treble);
  let projectionAngle = (u.zoom_params.w - 0.5) * 1.5;

  // Animated Voronoi cells
  let voro = voronoi(uv01, cellSize, voronoiDistort, time);
  let cellHash = hash21(vec2<f32>(voro.y, voro.z));
  let cellCenter = (vec2<f32>(voro.y, voro.z) + 0.5) / cellSize;

  // Mouse gravity warp
  let toMouse = (mouse - uv01) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(toMouse);
  let gravity = 0.25;
  let warp = select(vec2<f32>(0.0), normalize(toMouse) * gravity / (1.0 + mouseDist * 3.0), mouseDist > 0.0001);
  let warpedUV = uv01 + warp * 0.025;

  // Projection direction with per-cell rotation
  let dirVec = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dirVec);
  var dir = select(vec2<f32>(1.0, 0.0), normalize(dirVec), dist > 0.0001);
  let angleRot = projectionAngle + cellHash * 0.6;
  let ca = cos(angleRot);
  let sa = sin(angleRot);
  dir = vec2<f32>(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);

  // Chromatic channel offsets
  let cellChroma = chromaticStrength * (0.5 + cellHash);
  let baseOffset = dir * dist * 0.1;
  let rOff = baseOffset + dir * cellChroma * (1.0 + bass * 0.6);
  let gOff = baseOffset + dir * cellChroma * 0.35;
  let bOff = baseOffset - dir * cellChroma * 0.8;

  let src = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Mosaic edge shaping + radial falloff
  let edgeFade = smoothstep(0.0, 0.18, voro.x);
  color = color * (0.65 + 0.35 * edgeFade);
  let falloff = 1.0 / (1.0 + dist * 2.5);
  color = color * falloff;

  // Audio brightness + dynamic color temperature per cell
  color = color * (1.0 + bass * 0.25);
  let temp = mix(3500.0, 7500.0, clamp(cellHash + mids * 0.3, 0.0, 1.0));
  let tint = blackbodyRGB(temp);
  color = mix(color, color * tint * 1.5, 0.35);

  // Temporal feedback trail
  let decay = 0.96 - u.zoom_params.w * 0.03;
  let trail = mix(prev.rgb * decay, color, 0.22 + treble * 0.08);
  textureStore(dataTextureA, pixel, vec4<f32>(trail, prev.a));

  // ACES tone map + IGN dither
  color = acesToneMap(trail * 1.15);
  let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // Semantic alpha: bloom weight blended with source alpha
  let lum = luma(color);
  let bloomWeight = pow(max(0.0, lum - 0.55), 2.0) * 2.5;
  let alpha = clamp(src.a * (0.5 + 0.5 * edgeFade) + bloomWeight * 0.35, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color * alpha, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
