// Aerogel Smoke — advected silica density with dual scattering transport.
// A/C owns raw [density, scattering energy, velocity.xy]. B is unused.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let cell = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(cell), hash21(cell + vec2<f32>(1.0, 0.0)), s.x),
             mix(hash21(cell + vec2<f32>(0.0, 1.0)), hash21(cell + vec2<f32>(1.0)), s.x), s.y);
}

fn phaseHG(cosTheta: f32, anisotropy: f32) -> f32 {
  let g2 = anisotropy * anisotropy;
  let denominator = max(pow(1.0 + g2 - 2.0 * anisotropy * cosTheta, 1.5), 0.001);
  return (1.0 - g2) / (4.0 * PI * denominator);
}

fn stateAt(pixel: vec2<i32>, size: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let size = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let densityGain = 0.35 + u.zoom_params.x * 2.15;
  let blueScatter = 0.15 + u.zoom_params.y * 2.35;
  let lightPower = 0.15 + u.zoom_params.z * 1.35;
  let backgroundVisibility = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  let centerState = stateAt(coord, size);
  let velocityPixels = centerState.zw * resolution * (1.0 / 60.0);
  let advectedCoord = coord - vec2<i32>(round(velocityPixels));
  let advected = stateAt(advectedCoord, size);
  let north = stateAt(coord + vec2<i32>(0, -1), size);
  let south = stateAt(coord + vec2<i32>(0, 1), size);
  let east = stateAt(coord + vec2<i32>(1, 0), size);
  let west = stateAt(coord + vec2<i32>(-1, 0), size);
  let northeast = stateAt(coord + vec2<i32>(1, -1), size);
  let southwest = stateAt(coord + vec2<i32>(-1, 1), size);
  let neighborAverage = (north + south + east + west) * 0.25;

  var density = mix(advected.x, neighborAverage.x, 0.045 + audio.y * 0.012);
  var energy = mix(advected.y, neighborAverage.y, 0.07);
  var velocity = mix(advected.zw, neighborAverage.zw, 0.035);

  let densityGradient = vec2<f32>(east.x - west.x, south.x - north.x);
  let curlDriver = vec2<f32>(densityGradient.y, -densityGradient.x);
  let diagonalShear = vec2<f32>(northeast.x - southwest.x, northeast.y - southwest.y);
  let ambient = valueNoise(uv * 7.0 + vec2<f32>(time * 0.035, -time * 0.021));
  let micro = valueNoise(uv * 19.0 - vec2<f32>(time * 0.018, time * 0.027));
  let seed = smoothstep(0.48, 0.82, ambient * 0.72 + micro * 0.28);
  density += seed * (0.0028 + audio.x * 0.0035) * densityGain;
  energy += seed * (0.0018 + audio.z * 0.0045) * lightPower;
  velocity += curlDriver * (0.11 + audio.y * 0.04) + diagonalShear * 0.012;
  velocity += vec2<f32>(0.006 * sin(time * 0.37 + uv.y * 19.0), -0.008 - audio.x * 0.004);

  let mouseDelta = (uv - mouse) * aspectVec;
  let mouseDistance = length(mouseDelta);
  let mouseDirection = mouseDelta / max(mouseDistance, 0.0001);
  let hoverLight = exp(-mouseDistance * mouseDistance * 13.0);
  let heldPlume = select(0.0, exp(-mouseDistance * mouseDistance * 180.0), held);
  density += heldPlume * (0.035 + audio.x * 0.055) * densityGain;
  energy += heldPlume * (0.06 + audio.z * 0.1) * lightPower;
  velocity += heldPlume * (-mouseDirection * (0.10 + audio.y * 0.05) + vec2<f32>(0.0, -0.12));

  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let delta = (uv - ripple.xy) * aspectVec;
      let distanceToClick = length(delta);
      let plumeRadius = age * (0.12 + audio.x * 0.025);
      let shell = exp(-pow((distanceToClick - plumeRadius) * 34.0, 2.0)) * exp(-age * 0.85);
      let core = exp(-distanceToClick * distanceToClick * 95.0) * exp(-age * 1.45);
      density += (shell * 0.045 + core * 0.025) * densityGain;
      energy += (shell * 0.08 + core * 0.04) * lightPower * (0.6 + audio.z);
      velocity += (delta / max(distanceToClick, 0.0001)) * shell * 0.09 + vec2<f32>(0.0, -core * 0.12);
    }
  }

  density = clamp(density * exp(-0.006 - 0.004 * backgroundVisibility), 0.0, 2.5);
  energy = clamp(energy * exp(-0.014), 0.0, 3.0);
  velocity = clamp(velocity * 0.985, vec2<f32>(-0.75), vec2<f32>(0.75));
  textureStore(dataTextureA, coord, vec4<f32>(density, energy, velocity));

  let sourceUV = clamp(uv + velocity * 0.012, vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let opticalDepth = density * (0.65 + densityGain * 0.85);
  let transmittance = exp(-opticalDepth);
  let normal = normalize(vec3<f32>(-densityGradient * 4.0, 1.0));
  let lightVector = normalize(vec3<f32>((mouse - uv) * aspectVec, 0.22 + hoverLight * 0.35));
  let cosTheta = clamp(dot(vec3<f32>(0.0, 0.0, 1.0), lightVector), -1.0, 1.0);
  let rayleighPhase = 0.75 * (1.0 + cosTheta * cosTheta);
  let hgPhase = phaseHG(cosTheta, 0.68);
  let surfaceScatter = pow(clamp(dot(normal, lightVector), 0.0, 1.0), 2.0);
  let rayleigh = vec3<f32>(0.18, 0.62, 1.75) * rayleighPhase * blueScatter;
  let mie = vec3<f32>(1.35, 1.05, 0.72) * hgPhase * (0.65 + audio.x * 0.7);
  let cursorLight = (0.18 + hoverLight * 1.8 + heldPlume * 2.4) * lightPower;
  let inScatter = (rayleigh + mie) * density * (0.08 + surfaceScatter * 0.65) * cursorLight;
  let multipleScatter = vec3<f32>(0.16, 0.48, 1.1) * energy * (0.35 + audio.y * 0.4);
  var hdr = source.rgb * mix(1.0, transmittance, 0.45 + 0.55 * backgroundVisibility);
  hdr += inScatter + multipleScatter + density * audio * vec3<f32>(0.05, 0.08, 0.12);
  let alpha = clamp((1.0 - transmittance) * (0.78 + blueScatter * 0.08) + energy * 0.045, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);

  let sourceDepth = textureLoad(readDepthTexture, coord, 0).r;
  let volumetricDepth = mix(sourceDepth, 0.5, alpha * 0.5);
  textureStore(writeDepthTexture, coord, vec4<f32>(volumetricDepth, 0.0, 0.0, 0.0));
}
