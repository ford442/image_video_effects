// Underwater Caustics — analytic Gerstner derivatives and Jacobian light focusing.
// A/C stores ACES display RGBA, matching the effect's existing display history role.
// B is unused. Depth remains caustic/volume coverage as in the original effect.

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

struct SurfaceSample {
  height: f32,
  gradient: vec2<f32>,
  hxx: f32,
  hxy: f32,
  hyy: f32,
};

const PI: f32 = 3.14159265359;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn surfaceAt(p: vec2<f32>, time: f32, waveScale: f32, audio: vec3<f32>) -> SurfaceSample {
  let directions = array<vec2<f32>, 5>(
    normalize(vec2<f32>(1.0, 0.16)),
    normalize(vec2<f32>(0.42, 0.91)),
    normalize(vec2<f32>(-0.72, 0.69)),
    normalize(vec2<f32>(0.86, -0.51)),
    normalize(vec2<f32>(-0.18, 0.98))
  );
  let wavelengths = array<f32, 5>(1.4, 0.76, 0.41, 0.23, 0.13);
  let amplitudes = array<f32, 5>(0.052, 0.031, 0.017, 0.009, 0.0045);
  var result = SurfaceSample(0.0, vec2<f32>(0.0), 0.0, 0.0, 0.0);
  for (var i = 0; i < 5; i = i + 1) {
    let direction = directions[i];
    let wavelength = wavelengths[i] / max(waveScale, 0.1);
    let waveNumber = 2.0 * PI / wavelength;
    let speed = sqrt(9.81 / waveNumber) * (0.75 + f32(i) * 0.06);
    let amplitude = amplitudes[i] * (1.0 + audio.x * select(0.28, 0.08, i > 1));
    let phase = waveNumber * (dot(p, direction) - speed * time) + f32(i) * 1.37;
    let sinePhase = sin(phase);
    let cosinePhase = cos(phase);
    result.height += amplitude * sinePhase;
    result.gradient += amplitude * waveNumber * direction * cosinePhase;
    let curvature = -amplitude * waveNumber * waveNumber * sinePhase;
    result.hxx += curvature * direction.x * direction.x;
    result.hxy += curvature * direction.x * direction.y;
    result.hyy += curvature * direction.y * direction.y;
  }
  return result;
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

fn godRay(uv: vec2<f32>, sun: vec2<f32>, time: f32, clarity: f32, treble: f32) -> f32 {
  let delta = sun - uv;
  var ray = 0.0;
  for (var i = 0; i < 10; i = i + 1) {
    let t = (f32(i) + 0.5) / 10.0;
    let samplePosition = uv + delta * t;
    let dapple = 0.5 + 0.5 * sin(samplePosition.x * 61.0 + sin(samplePosition.y * 27.0 - time * 0.7) * 3.0 + time);
    let grain = 0.55 + 0.45 * hash21(floor(samplePosition * vec2<f32>(48.0, 31.0)));
    ray += pow(dapple, 5.0) * grain * (1.0 - t) * exp(-t * (1.6 - clarity * 0.7)) / 10.0;
  }
  return ray * (0.7 + treble * 0.35);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let waveScale = 0.65 + u.zoom_params.x * 2.4;
  let causticIntensity = 0.2 + u.zoom_params.y * 2.2;
  let waterDepth = 0.25 + u.zoom_params.z * 3.4;
  let clarity = 0.22 + u.zoom_params.w * 0.78;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let sun = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  var surface = surfaceAt(uv * aspectVec * 2.7, time, waveScale, audio);
  let sunDelta = (uv - sun) * aspectVec;
  let sunDistance = length(sunDelta);
  let heldSwell = select(0.0, exp(-sunDistance * sunDistance * 38.0), held);
  let swellDirection = sunDelta / max(sunDistance, 0.0001);
  surface.height += heldSwell * (0.035 + audio.x * 0.02) * sin(time * 5.0 - sunDistance * 32.0);
  surface.gradient += swellDirection * heldSwell * (0.18 + audio.y * 0.06);

  var rippleLight = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let delta = (uv - ripple.xy) * aspectVec;
      let rd = length(delta);
      let front = age * (0.19 + audio.x * 0.035);
      let ring = sin((rd - front) * 82.0) * exp(-abs(rd - front) * 31.0) * exp(-age * 0.9);
      rippleLight += abs(ring);
      surface.gradient += delta / max(rd, 0.0001) * ring * 0.12;
    }
  }

  let refractiveScale = 0.018 + waterDepth * 0.012;
  let j00 = 1.0 - refractiveScale * surface.hxx;
  let j01 = -refractiveScale * surface.hxy;
  let j10 = -refractiveScale * surface.hxy;
  let j11 = 1.0 - refractiveScale * surface.hyy;
  let jacobianDeterminant = j00 * j11 - j01 * j10;
  let focus = min(7.0, 1.0 / max(abs(jacobianDeterminant), 0.12));
  let causticRidge = pow(clamp((focus - 0.75) / 5.5, 0.0, 1.0), 1.55);
  let normal = normalize(vec3<f32>(-surface.gradient, 1.0));
  let lightDirection = normalize(vec3<f32>((sun - uv) * aspectVec, 0.7));
  let specular = pow(max(dot(reflect(-lightDirection, normal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 42.0);
  let rays = godRay(uv, sun, time, clarity, audio.z);

  let refractedUV = clamp(uv - surface.gradient / aspectVec * refractiveScale, vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0);
  let absorption = vec3<f32>(0.72, 0.24, 0.11) * waterDepth * (1.15 - clarity * 0.55);
  let transmitted = source.rgb * exp(-absorption);
  let deepWater = mix(vec3<f32>(0.005, 0.055, 0.12), vec3<f32>(0.01, 0.24, 0.32), clarity);
  let sunColor = vec3<f32>(1.25, 1.05, 0.62);
  let cyanScatter = vec3<f32>(0.04, 0.42, 0.55);
  let history = historyAt(uv - surface.gradient / aspectVec * 0.002, resolution);
  var hdr = transmitted + deepWater * (0.45 + waterDepth * 0.18);
  hdr += sunColor * (causticRidge * causticIntensity * (0.7 + audio.y * 0.35) + specular * 0.65 + rippleLight * 0.12);
  hdr += cyanScatter * rays * (0.65 + causticIntensity * 0.3);
  hdr += history.rgb * clamp(0.018 + causticRidge * 0.045 + rippleLight * 0.012, 0.0, 0.085);
  let volumeCoverage = 1.0 - exp(-waterDepth * (0.28 + clarity * 0.12));
  let alpha = clamp(volumeCoverage * 0.42 + causticRidge * 0.5 + rays * 0.22 + rippleLight * 0.08, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(alpha, 0.0, 0.0, 0.0));
}
