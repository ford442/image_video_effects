// Spectrum Bleed — Composer batch cyber/digital/glitch
// Sprung spectrum-ink diffusion with bounded click splatters, plasma bin
// shimmer, exact-C persistence, display RGBA in A, ACES output.

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

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let mx = max(max(c.r, c.g), c.b); let mn = min(min(c.r, c.g), c.b); let d = mx - mn;
  var h = 0.0;
  if (d > 0.00001) {
    if (mx == c.r) { h = (c.g - c.b) / d + select(0.0, 6.0, c.g < c.b); }
    else if (mx == c.g) { h = (c.b - c.r) / d + 2.0; }
    else { h = (c.r - c.g) / d + 4.0; }
    h /= 6.0;
  }
  return vec3<f32>(h, select(0.0, d / mx, mx > 0.0), mx);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = abs(fract(hsv.x + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0));
  return hsv.z * mix(vec3<f32>(1.0), clamp(k - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn blurSource(uv: vec2<f32>, radius: f32) -> vec3<f32> {
  let texel = radius / u.config.zw;
  var sum = vec3<f32>(0.0);
  sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-texel.x, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>( texel.x, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-texel.x,  texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  sum += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>( texel.x,  texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  return sum * 0.25;
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

  // Saved mapping: intensity, hue speed, blur scale, saturation detail.
  var blendFactor = u.zoom_params.x * 0.6;
  let hueSpeed = u.zoom_params.y;
  let blurRadius = mix(1.0, 4.0, u.zoom_params.z);
  let saturationBoost = u.zoom_params.w * 0.5;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 9.5; let decay = exp(-omega * dt); let delta = springPos - rawMouse; let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay; springPos = rawMouse + (delta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lensDist = length((uv - springPos) * aspectVec);
  let lens = smoothstep(0.36, 0.0, lensDist) * select(0.5, 1.0, u.zoom_config.w > 0.5);
  blendFactor = clamp(blendFactor + lens * 0.3, 0.0, 1.0);
  var hsv = rgb2hsv(blurSource(uv, blurRadius));
  var clickInk = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 1.5) { continue; }
    let dist = length((uv - ripple.xy) * aspectVec);
    let ink = smoothstep(0.30 + age * 0.04, 0.0, dist) * exp(-age * 2.0);
    clickInk += ink; hsv.y = min(hsv.y + ink * 0.4, 1.0);
  }

  let band = min(u32(clamp(uv.x * 128.0, 0.0, 127.0)), 7u);
  let fftVoice = plasmaBuffer[band + 1u].x;
  hsv.x = fract(hsv.x + hueSpeed * time * 0.1 + fftVoice * 0.2 + mids * 0.04);
  hsv.y = min(hsv.y + saturationBoost + treble * 0.08, 1.0);
  var hdr = mix(source.rgb, hsv2rgb(hsv), blendFactor);

  let historyUv = clamp(uv - springVel * lens * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let previous = textureLoad(dataTextureC, historyCoord(historyUv, dims), 0);
  let persistence = clamp(0.12 + u.zoom_params.x * 0.2 + clickInk * 0.22, 0.0, 0.58);
  hdr = mix(hdr, previous.rgb * (0.93 + bass * 0.02), persistence);
  hdr += vec3<f32>(0.10, 0.02, 0.16) * fftVoice * treble * blendFactor;
  let effectEnergy = clamp(blendFactor * 0.65 + clickInk * 0.35 + previous.a * persistence * 0.3, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(dataTextureA, pixel, display); textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
