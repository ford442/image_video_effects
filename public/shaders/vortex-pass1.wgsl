// ═══════════════════════════════════════════════════════════════
//  Fluid Vortex – Pass 1: Velocity Field & Vorticity
//  Category: distortion
//  Features: multi-pass-1, vortex dynamics, Biot-Savart, vorticity confinement
//  Outputs: dataTextureA (velocity.x, velocity.y, vorticity, velMag)
// ═══════════════════════════════════════════════════════════════

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

fn hash2(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453;
  return fract(vec2<f32>(n, n * 1.618));
}

fn hash3(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  let a = hash2(i);
  let b = hash2(i + vec2<f32>(1.0, 0.0));
  let c = hash2(i + vec2<f32>(0.0, 1.0));
  let d = hash2(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a.x, b.x, f.x), mix(c.x, d.x, f.x), f.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * noise(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

struct Vortex {
  center: vec2<f32>,
  strength: f32,
  coreRadius: f32,
  rotationDir: f32,
};

fn calculateVorticity(uv: vec2<f32>, vortices: array<Vortex, 4>, time: f32, audioReactivity: f32) -> f32 {
  var vorticity = 0.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    let v = vortices[i];
    let toCenter = uv - v.center;
    let dist = length(toCenter);
    let core = exp(-dist * dist / (v.coreRadius * v.coreRadius));
    let tail = 1.0 / (1.0 + pow(dist / v.coreRadius, 2.0));
    let pulse = 1.0 + 0.1 * sin(time * 2.0 * audioReactivity + f32(i));
    vorticity = vorticity + v.strength * v.rotationDir * (core + 0.3 * tail) * pulse;
  }
  return vorticity;
}

fn calculateVelocity(uv: vec2<f32>, vortices: array<Vortex, 4>, time: f32) -> vec2<f32> {
  var velocity = vec2<f32>(0.0, 0.0);
  for (var i: i32 = 0; i < 4; i = i + 1) {
    let v = vortices[i];
    let toCenter = uv - v.center;
    let dist = length(toCenter);
    let softDist = max(dist, v.coreRadius * 0.1);
    let tangent = vec2<f32>(-toCenter.y, toCenter.x) / softDist;
    let speed = v.strength * softDist / sqrt(v.coreRadius * v.coreRadius + softDist * softDist);
    velocity = velocity + v.rotationDir * speed * tangent;
    let radialDir = -toCenter / softDist;
    let inflowStrength = 0.1 * v.strength * exp(-softDist / v.coreRadius);
    velocity = velocity + radialDir * inflowStrength;
  }
  return velocity;
}

fn vorticityConfinement(
  uv: vec2<f32>,
  vortices: array<Vortex, 4>,
  time: f32,
  epsilon: f32,
  audioReactivity: f32
) -> vec2<f32> {
  let eps = 0.01;
  let w_center = abs(calculateVorticity(uv, vortices, time, audioReactivity));
  let w_xp = abs(calculateVorticity(uv + vec2<f32>(eps, 0.0), vortices, time, audioReactivity));
  let w_xn = abs(calculateVorticity(uv - vec2<f32>(eps, 0.0), vortices, time, audioReactivity));
  let w_yp = abs(calculateVorticity(uv + vec2<f32>(0.0, eps), vortices, time, audioReactivity));
  let w_yn = abs(calculateVorticity(uv - vec2<f32>(0.0, eps), vortices, time, audioReactivity));
  let gradW = vec2<f32>(w_xp - w_xn, w_yp - w_yn) / (2.0 * eps);
  let gradWMag = length(gradW) + 0.0001;
  let N = gradW / gradWMag;
  let w = calculateVorticity(uv, vortices, time, audioReactivity);
  return epsilon * vec2<f32>(N.y * w, -N.x * w);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let audioOverall = u.zoom_config.x;
  let audioReactivity = 1.0 + audioOverall * 0.3;

  let vortexStrength = u.zoom_params.x;
  let coreSizeParam = u.zoom_params.y;
  let rotationSpeed = u.zoom_params.z;
  let turbulence = u.zoom_params.w;

  var vortices: array<Vortex, 4>;
  let strengthScale = mix(0.05, 0.3, vortexStrength);
  let coreScale = mix(0.03, 0.15, coreSizeParam);
  let speedScale = mix(0.2, 1.5, rotationSpeed);
  let turbAmount = turbulence * 0.02;

  let t1 = time * speedScale * audioReactivity;
  vortices[0] = Vortex(
    vec2<f32>(0.5 + 0.1 * sin(t1 * 0.3), 0.5 + 0.1 * cos(t1 * 0.4)),
    strengthScale, coreScale, 1.0
  );
  let orbitAngle = t1 * 0.5;
  vortices[1] = Vortex(
    vec2<f32>(0.5 + 0.25 * cos(orbitAngle), 0.5 + 0.25 * sin(orbitAngle)),
    strengthScale * 0.7, coreScale * 0.8, -1.0
  );
  vortices[2] = Vortex(
    vec2<f32>(0.3 + 0.15 * sin(t1 * 0.2 + 1.0), 0.7 + 0.1 * cos(t1 * 0.25)),
    strengthScale * 0.5, coreScale * 0.6, 1.0
  );
  vortices[3] = Vortex(
    vec2<f32>(0.7 + 0.08 * sin(t1 * 0.8), 0.3 + 0.08 * cos(t1 * 0.7)),
    strengthScale * 0.4, coreScale * 0.5, -1.0
  );

  var velocity = calculateVelocity(uv, vortices, time);
  let confinementForce = vorticityConfinement(uv, vortices, time, 0.02 * vortexStrength, audioReactivity);
  velocity = velocity + confinementForce;

  let turbUV = uv * 3.0 + time * 0.1 * audioReactivity;
  let turbulenceNoise = vec2<f32>(
    fbm(turbUV + vec2<f32>(0.0, time * 0.05 * audioReactivity), 3),
    fbm(turbUV + vec2<f32>(100.0, time * 0.05 * audioReactivity), 3)
  ) - 0.5;
  velocity = velocity + turbulenceNoise * turbAmount;

  let vorticity = calculateVorticity(uv, vortices, time, audioReactivity);
  let velMag = length(velocity);

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), inputColor);
  textureStore(dataTextureA, vec2<i32>(global_id.xy),
    vec4<f32>(velocity.x, velocity.y, vorticity, velMag));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
