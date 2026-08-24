// Cellular Automata 3D — Batch 68 stateful projected-volume upgrade.
// A owns the projected volume display history; B is intentionally unwritten.

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

struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };
const TAU: f32 = 6.28318530718;

fn hash31(p: vec3<f32>) -> f32 {
  var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}
fn cellDensity(p: vec3<f32>, epoch: f32, density: f32, shock: f32) -> f32 {
  let cell = floor((p + vec3<f32>(1.0)) * 14.0);
  let current = step(1.0 - density, hash31(cell + vec3<f32>(floor(epoch))));
  var neighbors = 0.0;
  for (var z = -1; z <= 1; z++) { for (var y = -1; y <= 1; y++) { for (var x = -1; x <= 1; x++) {
    if (x == 0 && y == 0 && z == 0) { continue; }
    neighbors += step(0.55, hash31(cell + vec3<f32>(f32(x), f32(y), f32(z)) + vec3<f32>(floor(epoch - 1.0))));
  } } }
  let born = step(4.0 - shock * 2.0, neighbors) * step(neighbors, 6.0 + shock * 3.0);
  let survives = step(5.0, neighbors) * step(neighbors, 7.0);
  return mix(born, survives, current);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let time = u.config.x; let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let evolutionSpeed = mix(0.1, 2.0, u.zoom_params.x);
  let initialDensity = mix(0.1, 0.5, u.zoom_params.y);
  let colorCycling = u.zoom_params.z; let cameraRotation = u.zoom_params.w * TAU;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) { springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 8.0; let springDecay = exp(-omega * dt); let delta = springPos - rawMouse;
  let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * springDecay; springPos = rawMouse + (delta + temp) * springDecay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) { extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0; }

  var shock = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let dist = length((uv - ripple.xy) * aspectVec);
    shock += exp(-pow((dist - age * 0.28) * 28.0, 2.0)) * (1.0 - age / 2.0);
  }

  let pointer = (springPos * 2.0 - 1.0) * aspectVec;
  let camAngle = time * 0.12 * evolutionSpeed * (1.0 + bass * 0.7) + cameraRotation + pointer.x * 0.3;
  let ro = vec3<f32>(cos(camAngle) * 4.2, pointer.y * 1.1 + sin(camAngle * 0.47), sin(camAngle) * 4.2);
  let forward = normalize(-ro); let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward)); let up = cross(forward, right);
  let screen = (uv * 2.0 - 1.0) * aspectVec;
  let rd = normalize(forward + right * screen.x * 0.52 + up * screen.y * 0.52);

  var travel = 0.0; var transmittance = 1.0; var volumeColor = vec3<f32>(0.0); var volumeAlpha = 0.0;
  for (var stepIndex = 0; stepIndex < 72; stepIndex++) {
    let pos = (ro + rd * travel) * 0.24;
    if (all(abs(pos) < vec3<f32>(1.05))) {
      let projectedDist = length((pos.xy * 0.5 + vec2<f32>(0.5) - springPos) * aspectVec);
      let attraction = exp(-projectedDist * projectedDist * 18.0) * (0.15 + 0.65 * u.zoom_config.w);
      let cell = cellDensity(pos, time * evolutionSpeed * (1.0 + mids * 0.5), initialDensity, clamp(shock + attraction, 0.0, 1.0));
      if (cell > 0.5) {
        let age = hash31(floor((pos + vec3<f32>(1.0)) * 14.0)); let hue = fract(age + time * colorCycling * 0.08 + treble * 0.2);
        let emission = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(TAU * (vec3<f32>(hue) + vec3<f32>(0.0, 0.33, 0.67)));
        let density = 0.12 + 0.08 * bass + shock * 0.05;
        volumeColor += transmittance * emission * density; transmittance *= 1.0 - density; volumeAlpha = 1.0 - transmittance;
        if (transmittance < 0.03) { break; }
      }
    }
    travel += 0.075;
  }

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let previous = textureLoad(dataTextureC, historyCoord(clamp(uv - springVel * 0.012, vec2<f32>(0.0), vec2<f32>(1.0)), dims), 0);
  let persisted = max(volumeColor, previous.rgb * (0.90 + 0.05 * u.zoom_params.y));
  let effectEnergy = clamp(volumeAlpha + shock * 0.45 + dot(persisted, vec3<f32>(0.12)), 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(source.rgb * (1.0 - volumeAlpha * 0.65) + persisted), alpha);
  textureStore(dataTextureA, pixel, display); textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
