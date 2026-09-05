// Photonic Caustics — refractive height-field convergence with multi-spectral caustic ribbons and chromatic dispersion.
// A/C stores ACES display RGBA for continuous caustic irradiance persistence; B is unused; depth passes through refracted depth.

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let q = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), q.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), q.x), q.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
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
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let texel = 1.0 / resolution;
  let time = u.config.x;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let ior = mix(1.05, 1.85, u.zoom_params.x);
  let lightSize = mix(0.04, 0.4, u.zoom_params.y);
  let dispersion = mix(0.01, 0.22, u.zoom_params.z);
  let intensity = (0.4 + u.zoom_params.w * 3.5) * (1.0 + bass * 0.4);

  // Sample local surface height from depth
  let hL = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hR = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hT = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hB = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;

  let rippleNoise = noise(uv * (10.0 + mids * 4.0) + vec2<f32>(time * 0.12, -time * 0.09));
  let normal = normalize(vec3<f32>(
    (hL - hR) * 8.0 + sin(uv.y * 45.0 + time) * 0.09,
    (hT - hB) * 8.0 + cos(uv.x * 40.0 - time * 0.8) * 0.09,
    1.0
  ));

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let lightPos = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  let toLight = (lightPos - uv) * aspectVec;
  let lightDist = length(toLight);
  let aperture = exp(-lightDist * (2.8 + 8.0 * (1.0 - lightSize))) * select(1.0, 1.6, held);

  // Refraction bending
  let bend = normal.xy * (ior - 1.0) * (0.02 + lightSize * 0.025);
  let focus = 1.0 / (0.035 + abs(dot(normalize(toLight + vec2<f32>(0.0001)), normalize(bend + vec2<f32>(0.0001)))));

  // Chromatic dispersion wave bands
  let wavePhase = (uv.x + normal.x * 0.08) * 75.0 + (uv.y + normal.y * 0.08) * 60.0 + rippleNoise * 8.0 - time * (1.5 + mids * 1.8);
  let bands = pow(0.5 + 0.5 * cos(vec3<f32>(wavePhase - dispersion * 20.0, wavePhase, wavePhase + dispersion * 20.0)), vec3<f32>(5.5));

  // Click ripple interactions
  var clickLight = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.32 + bass * 0.12);
      clickLight += exp(-age * 1.4) * exp(-abs(rd - front) * 35.0);
    }
  }

  let spectral = vec3<f32>(1.15 + bass * 0.25, 0.95 + mids * 0.2, 1.25 + treble * 0.35);
  let fresh = bands * spectral * intensity * (0.08 + aperture * 0.55 + clamp(focus * 0.025, 0.0, 0.85))
            + clickLight * vec3<f32>(0.5, 0.95, 2.0) * intensity;

  // Exact previous frame history load for continuous caustic accumulation
  let history = historyAt(uv, resolution);
  let persistence = clamp(0.85 + lightSize * 0.1 - treble * 0.02, 0.75, 0.96);
  let irradiance = mix(fresh, history.rgb * persistence, 0.68);

  // Sample underlying source with refractive displacement
  let refractUV = clamp(uv + bend + normalize(toLight + vec2<f32>(0.0001)) * clickLight * 0.008, vec2<f32>(0.0), vec2<f32>(1.0));
  let src = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0);

  let fresnel = pow(1.0 - clamp(normal.z, 0.0, 1.0), 4.0);
  let hdr = src.rgb * (0.75 + fresnel * 0.25) + irradiance;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let causticAlpha = clamp(max(max(irradiance.r, irradiance.g), irradiance.b) * 0.4 + aperture * 0.2, 0.0, 1.0);
  let alpha = clamp(src.a * 0.6 + causticAlpha * 0.5 + fresnel * 0.15, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth - causticAlpha * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
