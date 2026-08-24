// Spectrogram Displace — Batch 58D live-audio temporal upgrade
// A owns the scrolling spectrogram display history; B is intentionally unwritten.

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

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.42, 0.36, 0.48) + vec3<f32>(0.58, 0.54, 0.52) *
         cos(TAU * (vec3<f32>(t) + vec3<f32>(0.02, 0.35, 0.68)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res; let time = u.config.x;
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  // Saved mapping: intensity, scroll speed, scale, spectral detail.
  let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
  let speed = clamp(u.zoom_params.y, 0.0, 1.0);
  let scale = clamp(u.zoom_params.z, 0.0, 1.0);
  let detail = clamp(u.zoom_params.w, 0.0, 1.0);

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 10.0; let decay = exp(-omega * dt); let delta = springPos - rawMouse; let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay; springPos = rawMouse + (delta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  // The engine FFT is read-only at [5..132]; logarithmic y selects one of 128 bins.
  let logY = pow(clamp(1.0 - uv.y, 0.0, 1.0), mix(2.4, 0.65, scale));
  let bin = u32(clamp(logY * 127.0, 0.0, 127.0));
  let fft = extraBuffer[5u + bin];
  let bandBlend = mix(bass, mix(mids, treble, smoothstep(0.55, 1.0, logY)), smoothstep(0.18, 0.72, logY));
  var magnitude = clamp(mix(bandBlend, fft, 0.55 + detail * 0.35) * (0.6 + intensity * 1.4), 0.0, 2.0);

  let pointerDist = length((uv - springPos) * aspectVec);
  let pointerBand = exp(-abs(uv.y - springPos.y) * (18.0 + detail * 30.0)) * exp(-pointerDist * 2.0);
  magnitude += pointerBand * select(0.18, 0.55, u.zoom_config.w > 0.5);
  var clickEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let dist = length((uv - ripple.xy) * aspectVec);
    let front = exp(-pow((dist - age * 0.20) * 20.0, 2.0)) * (1.0 - age / 2.0);
    clickEnergy += front;
  }
  magnitude = clamp(magnitude + clickEnergy * 0.8, 0.0, 2.5);

  // Exact-C scrolling turns A into a real spectrogram conveyor.
  let scrollPixels = 1 + i32(speed * 4.0 + bass * 2.0);
  let historyPixel = vec2<i32>(clamp(pixel.x - scrollPixels, 0, dims.x - 1), clamp(pixel.y, 0, dims.y - 1));
  let previous = textureLoad(dataTextureC, historyPixel, 0);
  let newColumn = 1.0 - smoothstep(0.0, 0.018 + speed * 0.035, uv.x);
  let spectralInk = palette(logY * 0.75 + time * 0.025 + mids * 0.1) * magnitude;
  let spectrogram = mix(previous.rgb * (0.955 + detail * 0.025), spectralInk, newColumn);

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let displacement = vec2<f32>((magnitude - 0.5) * (source.r - source.b), (source.g - 0.5) * magnitude * (1.0 - uv.y)) *
                     intensity * vec2<f32>(0.035, 0.025);
  let displacedUv = clamp(uv + displacement + springVel * pointerBand * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
  var hdr = textureSampleLevel(readTexture, u_sampler, displacedUv, 0.0).rgb;
  hdr += spectrogram * (0.25 + detail * 0.45);
  let effectEnergy = clamp(length(displacement) * 16.0 + magnitude * 0.28 + clickEnergy * 0.35 + previous.a * 0.15, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(dataTextureA, pixel, display); textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
