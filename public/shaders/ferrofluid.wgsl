// ═══════════════════════════════════════════════════════════════════
//  Magnetic Ferrofluid — image-warping domains and droplet runners
//  A owns HDR display history; C is loaded exactly for viscous trails.
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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

fn domainHeight(p: vec2<f32>, magnet: vec2<f32>, scale: f32, time: f32, viscosity: f32) -> f32 {
  let delta = p - magnet;
  let radius = length(delta);
  let angle = atan2(delta.y, delta.x);
  let mobility = mix(1.7, 0.28, viscosity);
  let spokes = 8.0 + scale * 0.16;
  let rosette = 0.5 + 0.5 * cos(angle * spokes - time * mobility * 2.8 + radius * scale * 0.75);
  let rings = 0.5 + 0.5 * sin(radius * scale * 2.2 - time * mobility * 5.5 + angle * 2.0);
  let grain = noise2(vec2<f32>(angle * 3.2 + time * 0.16, radius * scale * 0.8 - time * mobility));
  let envelope = exp(-radius * radius * 3.8);
  return envelope * (0.18 + pow(rosette, 5.0) * 0.58 + pow(rings, 9.0) * 0.32 + grain * 0.22);
}

fn hueRotate(color: vec3<f32>, angle: f32) -> vec3<f32> {
  let axis = vec3<f32>(0.577350269);
  return color * cos(angle) + cross(axis, color) * sin(angle)
    + axis * dot(axis, color) * (1.0 - cos(angle));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn clampPixel(pixel: vec2<i32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let p = uv * aspectVec;
  let magnet = u.zoom_config.yz * aspectVec;
  let time = u.config.x;

  // Saved-preset contract: spikeScale, attraction, viscosity, colorShift.
  let spikeScale = mix(12.0, 52.0, u.zoom_params.x);
  let attraction = u.zoom_params.y;
  let viscosity = u.zoom_params.z;
  let colorShift = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let held = select(0.55, 1.0, u.zoom_config.w > 0.5);

  let delta = p - magnet;
  let radius = length(delta);
  let radial = delta / max(radius, 0.001);
  let tangent = vec2<f32>(-radial.y, radial.x);
  let field = exp(-radius * radius * mix(7.0, 2.8, attraction)) * attraction * held;

  var clickFront = 0.0;
  var clickNormal = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri += 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.9) {
      let clickDelta = (uv - ripple.xy) * aspectVec;
      let clickRadius = length(clickDelta);
      let front = smoothstep(0.026, 0.0, abs(clickRadius - age * 0.38)) * exp(-age * 1.25);
      clickFront += front;
      clickNormal += clickDelta / max(clickRadius, 0.001) * front;
    }
  }

  let height = domainHeight(p, magnet, spikeScale, time * (1.0 + bass * 0.22), viscosity)
    * (0.55 + field * 1.7) + clickFront * 0.42;
  let eps = 1.4 / resolution.y;
  let hL = domainHeight(p - vec2<f32>(eps, 0.0), magnet, spikeScale, time, viscosity);
  let hR = domainHeight(p + vec2<f32>(eps, 0.0), magnet, spikeScale, time, viscosity);
  let hD = domainHeight(p - vec2<f32>(0.0, eps), magnet, spikeScale, time, viscosity);
  let hU = domainHeight(p + vec2<f32>(0.0, eps), magnet, spikeScale, time, viscosity);
  var normal = normalize(vec3<f32>((hL - hR) * (2.2 + attraction * 5.0),
                                   (hD - hU) * (2.2 + attraction * 5.0), 0.14));
  normal = normalize(vec3<f32>(normal.xy + clickNormal * 0.45, normal.z));

  let mobility = mix(1.6, 0.3, viscosity);
  let runnerPhase = radius * spikeScale * 2.3 - time * (8.0 + mobility * 7.0) + atan2(delta.y, delta.x) * 3.0;
  let runner = pow(max(0.0, sin(runnerPhase)), 15.0) * field;
  let displacementAspect = (-radial * height * (0.028 + attraction * 0.09)
    + tangent * runner * mobility * 0.045 + clickNormal * 0.025) * (1.0 + bass * 0.25);
  let displacedUV = clamp(uv + displacementAspect / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));

  let chroma = normal.xy * (0.002 + colorShift * 0.012 + treble * 0.003) / aspectVec;
  let sourceR = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let sourceG = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let sourceB = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let sourceA = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).a;
  let source = vec3<f32>(sourceR, sourceG, sourceB);

  let viewDir = normalize(vec3<f32>((uv - 0.5) * aspectVec * 0.5, 1.0));
  let key = normalize(vec3<f32>(-0.45, 0.62, 0.78));
  let rimLight = normalize(vec3<f32>(0.72, -0.28, 0.64));
  let halfKey = normalize(viewDir + key);
  let fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 4.0);
  let spec = pow(max(dot(normal, halfKey), 0.0), mix(28.0, 150.0, 1.0 - viscosity));
  let rim = pow(max(dot(normal, rimLight), 0.0), 20.0);
  let ridge = smoothstep(0.2, 0.78, height) + runner * 0.7 + clickFront * 0.55;
  let darkMetal = source * vec3<f32>(0.10, 0.12, 0.15) + vec3<f32>(0.006, 0.009, 0.014);
  var fluid = darkMetal + vec3<f32>(0.82, 0.9, 1.04) * (spec * 2.4 + rim * 0.7)
    + vec3<f32>(0.18, 0.32, 0.48) * fresnel * (1.0 + mids * 0.7)
    + vec3<f32>(1.0, 0.56, 0.22) * clickFront * (0.2 + treble * 0.45);
  fluid = hueRotate(fluid, colorShift * TAU * 0.72);

  let effectMask = clamp(smoothstep(0.78, 0.18, radius) * (0.35 + attraction * 0.65) + ridge * 0.28, 0.0, 1.0);
  var live = mix(source, fluid, effectMask);

  // Viscous display persistence. Offset the exact history along domain motion.
  let historyDrift = vec2<i32>(round((tangent * runner * 2.2 - radial * field * 1.4 + clickNormal) * mobility));
  let prev = textureLoad(dataTextureC, clampPixel(pixel - historyDrift, dims), 0);
  let trailWeight = mix(0.24, 0.78, viscosity) * effectMask;
  live = mix(live, prev.rgb * 0.972, trailWeight);
  live = max(live, fluid * 0.62);

  let alphaLive = mix(sourceA, clamp(0.42 + height * 0.48 + fresnel * 0.18, 0.0, 1.0), effectMask);
  let alpha = mix(alphaLive, prev.a * 0.97, trailWeight * 0.55);
  textureStore(dataTextureA, pixel, vec4<f32>(min(live, vec3<f32>(7.0)), alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(live), alpha));

  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let generatedDepth = clamp(height * 0.42 + field * 0.25 + runner * 0.12, 0.0, 0.9);
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.86, generatedDepth), 0.0, 0.0, 0.0));
}
