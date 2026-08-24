// ═══════════════════════════════════════════════════════════════════
//  Liquid Chrome Ripple — capillary sheet, caustics, RGB reflection
//  A owns HDR display history; C is exact previous display state.
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

fn waveHeight(p: vec2<f32>, mouse: vec2<f32>, time: f32, frequency: f32, flow: f32) -> f32 {
  let delta = p - mouse;
  let radius = length(delta);
  var h = sin(radius * frequency - time * (3.5 + flow * 5.0)) * exp(-radius * 2.8);
  h += sin(dot(p, normalize(vec2<f32>(0.82, 0.57))) * frequency * 0.72 + time * flow * 3.1) * 0.24;
  h += sin(dot(p, normalize(vec2<f32>(-0.36, 0.93))) * frequency * 0.46 - time * flow * 2.2) * 0.18;
  h += sin(length(p - vec2<f32>(0.25, 0.68)) * frequency * 0.62 + time * 1.7) * 0.12;
  return h;
}

fn schlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
  return f0 + (vec3<f32>(1.0) - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
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
  let mouse = u.zoom_config.yz * aspectVec;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Saved-preset contract: flow, distort, metal, freq.
  let flow = mix(0.12, 1.25, u.zoom_params.x);
  let distortion = mix(0.015, 0.16, u.zoom_params.y);
  let metalness = u.zoom_params.z;
  let frequency = mix(9.0, 55.0, u.zoom_params.w) * (1.0 + treble * 0.12);
  let held = select(0.7, 1.35, u.zoom_config.w > 0.5);

  var clickHeight = 0.0;
  var clickSlope = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri += 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.6) {
      let delta = (uv - ripple.xy) * aspectVec;
      let radius = length(delta);
      let phase = radius * frequency * 0.82 - age * (8.0 + flow * 5.0);
      let envelope = exp(-radius * 3.2 - age * 0.85);
      let wave = sin(phase) * envelope;
      clickHeight += wave;
      clickSlope += delta / max(radius, 0.001) * cos(phase) * envelope;
    }
  }

  let eps = 1.4 / resolution.y;
  let baseHeight = waveHeight(p, mouse, time, frequency, flow) * held + clickHeight * 0.85;
  let hL = waveHeight(p - vec2<f32>(eps, 0.0), mouse, time, frequency, flow);
  let hR = waveHeight(p + vec2<f32>(eps, 0.0), mouse, time, frequency, flow);
  let hD = waveHeight(p - vec2<f32>(0.0, eps), mouse, time, frequency, flow);
  let hU = waveHeight(p + vec2<f32>(0.0, eps), mouse, time, frequency, flow);
  var slope = vec2<f32>(hL - hR, hD - hU) / max(2.0 * eps, 0.0001);
  slope += clickSlope * frequency * 0.055;
  let normal = normalize(vec3<f32>(slope * distortion * 0.62, 1.0));

  let viewDir = normalize(vec3<f32>((uv - 0.5) * aspectVec * 0.55, 1.0));
  let refractOffset = normal.xy * distortion / aspectVec;
  let dispersion = (0.004 + metalness * 0.008 + treble * 0.003) * distortion / 0.16;
  let rUV = clamp(uv + refractOffset * (0.74 - dispersion), vec2<f32>(0.001), vec2<f32>(0.999));
  let gUV = clamp(uv + refractOffset, vec2<f32>(0.001), vec2<f32>(0.999));
  let bUV = clamp(uv + refractOffset * (1.26 + dispersion), vec2<f32>(0.001), vec2<f32>(0.999));
  let sourceR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let sourceG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let sourceB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  let sourceA = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;
  let refracted = vec3<f32>(sourceR, sourceG, sourceB);

  let f0 = mix(vec3<f32>(0.04), vec3<f32>(0.72, 0.76, 0.82), metalness);
  let fresnel = schlick(max(dot(normal, viewDir), 0.0), f0);
  let key = normalize(vec3<f32>(-0.42, 0.63, 0.66));
  let fill = normalize(vec3<f32>(0.72, -0.18, 0.67));
  let hKey = normalize(viewDir + key);
  let hFill = normalize(viewDir + fill);
  let specKey = pow(max(dot(normal, hKey), 0.0), mix(30.0, 180.0, metalness));
  let specFill = pow(max(dot(normal, hFill), 0.0), mix(18.0, 96.0, metalness));
  let caustic = pow(clamp(abs(slope.x * slope.y) * distortion * 0.35, 0.0, 1.0), 0.65);
  let thinFilm = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.86, 1.0, 1.18)
    * (baseHeight * 0.22 + fresnel.g * 0.18 + time * flow * 0.025) + vec3<f32>(0.0, 0.17, 0.34)));
  let environment = mix(vec3<f32>(0.08, 0.11, 0.16), thinFilm, 0.32 + metalness * 0.48);
  var live = refracted * (vec3<f32>(1.0) - fresnel * 0.68)
    + environment * fresnel * (0.75 + metalness * 0.85)
    + vec3<f32>(1.05, 0.98, 0.86) * specKey * (1.1 + bass * 0.5)
    + vec3<f32>(0.48, 0.72, 1.0) * specFill * 0.45
    + thinFilm * caustic * (0.18 + mids * 0.28);

  // Advected display persistence gives ripples a chrome afterimage without
  // turning the buffer into an undocumented simulation state.
  let historyDrift = vec2<i32>(round(normal.xy * (1.0 + flow * 3.0) + clickSlope * 1.5));
  let prev = textureLoad(dataTextureC, clampPixel(pixel - historyDrift, dims), 0);
  let motionMask = clamp(length(slope) * distortion * 0.18 + abs(clickHeight) * 0.28, 0.0, 1.0);
  let persistence = mix(0.16, 0.52, metalness) * motionMask;
  live = mix(live, prev.rgb * 0.965, persistence);

  let fresnelLuma = dot(fresnel, vec3<f32>(0.2126, 0.7152, 0.0722));
  let alphaLive = clamp(mix(sourceA * 0.72, 0.96, metalness) + fresnelLuma * 0.12 + motionMask * 0.08, 0.0, 1.0);
  let alpha = mix(alphaLive, prev.a * 0.96, persistence * 0.45);
  textureStore(dataTextureA, pixel, vec4<f32>(min(live, vec3<f32>(8.0)), alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(live), alpha));

  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let generatedDepth = clamp(abs(baseHeight) * 0.12 + motionMask * 0.24, 0.0, 0.72);
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.88, generatedDepth), 0.0, 0.0, 0.0));
}
