// Stipple Engraving — tone-aware low-discrepancy stipple and directional hatching.
// A/C stores ACES display RGBA. B is unused. Depth remains engraved ink density.

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

const TAU: f32 = 6.28318530718;

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn lowDiscrepancy(pixel: vec2<f32>) -> f32 {
  let lattice = fract(dot(pixel, vec2<f32>(0.754877666, 0.569840296)));
  let scramble = hash21(floor(pixel / 8.0)) * 0.35;
  return fract(lattice + scramble);
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let texel = vec2<f32>(1.0) / resolution;
  let pixel = vec2<f32>(gid.xy);
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let density = 0.65 + u.zoom_params.x * 2.6;
  let contrast = 0.7 + u.zoom_params.y * 2.2;
  let spotRadius = 0.05 + u.zoom_params.z * 0.55;
  let inkStrength = 0.35 + u.zoom_params.w * 1.3;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lumL = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumR = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumT = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let lumB = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let gradient = vec2<f32>(lumR - lumL, lumB - lumT);
  let gradientMagnitude = length(gradient);
  let tangent = normalize(vec2<f32>(-gradient.y, gradient.x) + vec2<f32>(0.0001));
  let tone = clamp((1.0 - luma(source.rgb) - 0.5) * contrast + 0.5, 0.0, 1.0);

  let stipplePixel = pixel / density;
  let threshold = lowDiscrepancy(floor(stipplePixel));
  let dotCoverage = smoothstep(threshold - 0.055, threshold + 0.055, tone * (0.82 + audio.x * 0.1));
  let dotCell = fract(stipplePixel) - 0.5;
  let dotRadius = 0.08 + sqrt(tone) * 0.42;
  let stippleDot = dotCoverage * (1.0 - smoothstep(dotRadius - 0.08, dotRadius + 0.08, length(dotCell)));

  let hatchCoordinate = dot(pixel, tangent) / (2.8 + density * 1.7);
  let crossCoordinate = dot(pixel, vec2<f32>(-tangent.y, tangent.x)) / (4.5 + density);
  let hatchA = pow(0.5 + 0.5 * sin(hatchCoordinate * TAU), 10.0);
  let hatchB = pow(0.5 + 0.5 * sin((hatchCoordinate + crossCoordinate * 0.42) * TAU), 12.0);
  let hatch = (hatchA * smoothstep(0.38, 0.78, tone) + hatchB * smoothstep(0.68, 0.96, tone)) * (0.45 + gradientMagnitude * 4.0);

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDistance = length(pointerDelta);
  let burnish = smoothstep(spotRadius, 0.0, pointerDistance);
  let heldPool = select(0.0, exp(-pointerDistance * pointerDistance / max(spotRadius * spotRadius * 0.18, 0.001)), held);
  var engravingRing = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.6) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.2 + audio.y * 0.035);
      engravingRing += exp(-abs(rd - front) * 62.0) * exp(-age * 1.1);
    }
  }

  let longFiber = hash21(floor(pixel * vec2<f32>(0.08, 0.7)));
  let shortFiber = hash21(floor(pixel.yx * vec2<f32>(0.21, 0.45)) + 29.0);
  let absorption = 0.88 + (longFiber - 0.5) * 0.12 + (shortFiber - 0.5) * 0.07;
  let paper = vec3<f32>(0.93, 0.89, 0.78) * absorption;
  let ink = vec3<f32>(0.022, 0.026, 0.045) * (0.8 + hash21(floor(pixel * 0.5)) * 0.25);
  let rustInk = vec3<f32>(0.18, 0.045, 0.015) * (0.4 + audio.z * 0.35);
  let inkMask = clamp((stippleDot + hatch * 0.55) * inkStrength * (1.0 - burnish * 0.38) + heldPool * 0.72 + engravingRing * 0.58, 0.0, 1.0);
  var hdr = mix(paper, ink + rustInk * (hatch + engravingRing), inkMask);
  hdr += source.rgb * burnish * 0.12;
  hdr += vec3<f32>(0.22, 0.15, 0.08) * burnish * (1.0 - heldPool) * 0.16;
  let history = historyAt(uv, resolution);
  hdr += history.rgb * clamp(heldPool * 0.035 + engravingRing * 0.025, 0.0, 0.065);
  let alpha = clamp(inkMask * (0.72 + absorption * 0.2) + burnish * 0.06, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(inkMask, 0.0, 0.0, 0.0));
}
