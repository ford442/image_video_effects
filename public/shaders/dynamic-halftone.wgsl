// Dynamic Halftone — variable-angle CMYK rosettes with morphing print dots.
// A/C stores premultiplied tone-mapped display RGBA. B and extraBuffer are unused.

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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), hi);
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, historyCoord(uv, resolution), 0);
}

fn rotate2(p: vec2<f32>, angle: f32) -> vec2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return mat2x2<f32>(c, -s, s, c) * p;
}

fn plateDot(p: vec2<f32>, density: f32, angle: f32, radius: f32,
            edgeWidth: f32, morph: f32, petalPhase: f32) -> f32 {
  let grid = rotate2(p, angle) * density;
  let local = fract(grid) - 0.5;
  let polar = atan2(local.y, local.x);
  let circle = length(local);
  let diamond = (abs(local.x) + abs(local.y)) * 0.72;
  let petal = circle * (1.0 + 0.14 * morph * cos(polar * 4.0 + petalPhase));
  let shapeDistance = mix(circle, mix(diamond, petal, 0.58), morph);
  return 1.0 - smoothstep(max(radius - edgeWidth, 0.0), radius + edgeWidth, shapeDistance);
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let p = (uv - 0.5) * aspectVec;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let density = 18.0 + u.zoom_params.x * 96.0;
  let mouseRadius = 0.05 + u.zoom_params.y * 0.56;
  let contrast = 0.6 + u.zoom_params.z * 2.3;
  let sharpness = clamp(u.zoom_params.w, 0.0, 1.0);
  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let pointerMask = smoothstep(mouseRadius, 0.0, pointerDist);
  let magnification = pointerMask * select(0.24, 0.62, held);

  var inkWave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.26 + bass * 0.08);
      inkWave += sin((dist - front) * 68.0) * exp(-abs(dist - front) * 30.0) * exp(-age * 1.2);
    }
  }

  let localDensity = density * (1.0 - magnification * 0.52);
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let ink = clamp(vec4<f32>(1.0 - source.r, 1.0 - source.g, 1.0 - source.b,
                            1.0 - dot(source.rgb, vec3<f32>(0.299, 0.587, 0.114))),
                  vec4<f32>(0.0), vec4<f32>(1.0));
  let angleDrift = sin(time * 0.23 + mids * 2.0) * (0.04 + u.zoom_params.x * 0.08) + inkWave * 0.05;
  let morph = clamp(pointerMask * select(0.35, 1.0, held) + 0.28 * sin(time * 0.7 + bass * 2.0), 0.0, 1.0);
  let edgeWidth = mix(0.075, 0.008, sharpness) * (1.0 + treble * 0.18);
  let radiusBoost = magnification * 0.12 + bass * 0.035 + inkWave * 0.045;

  let cMask = plateDot(p, localDensity, 15.0 * PI / 180.0 + angleDrift,
                       clamp(0.06 + sqrt(ink.x) * 0.39 + radiusBoost, 0.0, 0.56),
                       edgeWidth, morph, time * 0.8);
  let mMask = plateDot(p, localDensity, 75.0 * PI / 180.0 - angleDrift * 0.7,
                       clamp(0.06 + sqrt(ink.y) * 0.39 + radiusBoost, 0.0, 0.56),
                       edgeWidth, morph, time * 0.8 + 1.57);
  let yMask = plateDot(p, localDensity, angleDrift * 0.45,
                       clamp(0.06 + sqrt(ink.z) * 0.39 + radiusBoost, 0.0, 0.56),
                       edgeWidth, morph, time * 0.8 + 3.14);
  let kMask = plateDot(p, localDensity, 45.0 * PI / 180.0 + angleDrift * 0.3,
                       clamp(0.05 + sqrt(ink.w) * 0.36 + radiusBoost * 0.75, 0.0, 0.54),
                       edgeWidth, morph * 0.65, time * 0.6);

  let paperGrain = (ign(vec2<f32>(gid.xy) * 0.43 + time * 0.09) - 0.5) * (0.035 + treble * 0.025);
  let paper = vec3<f32>(0.94, 0.90, 0.82) + vec3<f32>(paperGrain);
  let cyanInk = vec3<f32>(0.05, 0.76, 0.92) * cMask;
  let magentaInk = vec3<f32>(0.92, 0.08, 0.52) * mMask;
  let yellowInk = vec3<f32>(1.0, 0.78, 0.08) * yMask;
  let blackInk = vec3<f32>(0.92) * kMask;
  var hdr = paper * (vec3<f32>(1.0) - cyanInk * 0.78) *
                    (vec3<f32>(1.0) - magentaInk * 0.78) *
                    (vec3<f32>(1.0) - yellowInk * 0.72) *
                    (vec3<f32>(1.0) - blackInk * 0.88);
  hdr = pow(max(hdr, vec3<f32>(0.0)), vec3<f32>(contrast));
  let rosette = cMask * mMask + mMask * yMask + yMask * cMask;
  hdr += vec3<f32>(0.2, 0.55, 1.1) * rosette * (0.06 + treble * 0.18);
  hdr += vec3<f32>(1.0, 0.3, 0.12) * abs(inkWave) * (0.08 + bass * 0.18);
  let history = historyAt(uv - normalize(pointerDelta + vec2<f32>(0.0001)) * inkWave * 0.006, resolution);
  hdr = mix(hdr, history.rgb, clamp(0.025 + rosette * 0.045, 0.0, 0.08));
  let display = aces(max(hdr * 1.16, vec3<f32>(0.0)));
  let coverage = clamp(max(max(cMask, mMask), max(yMask, kMask)), 0.0, 1.0);
  let alpha = clamp(0.12 + coverage * (0.48 + source.a * 0.26) + rosette * 0.14, 0.0, 1.0);
  let result = vec4<f32>(display * alpha, alpha);
  let depth = textureLoad(readDepthTexture, coord, 0).r;

  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, result);
}
