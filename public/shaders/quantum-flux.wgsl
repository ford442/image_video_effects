// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// Pseudo-random function
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
      return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Params
  let jitterAmount = u.zoom_params.x; // Jitter intensity
  let freq = u.zoom_params.y;         // Wave frequency
  let driftSpeed = u.zoom_params.z;   // Color drift speed
  let radiusParam = u.zoom_params.w;  // Radius

  // Mouse interaction
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);

  // Calculate distance from mouse with aspect correction
  let dist = distance(uvCorrected, mouseCorrected);

  // Influence falls off with distance
  let influenceRadius = radiusParam * 0.8 + 0.1;
  let influence = smoothstep(influenceRadius, 0.0, dist);

  // High frequency quantum vibration (jitter)
  // Random offset per pixel, animated over time
  let seed = uv + vec2<f32>(time * 0.1, time * 0.1);
  let noiseX = (rand(seed) - 0.5) * 2.0;
  let noiseY = (rand(seed + vec2<f32>(1.0, 1.0)) - 0.5) * 2.0;

  let jitter = vec2<f32>(noiseX, noiseY) * jitterAmount * 0.05 * influence;

  // Probability wave distortion
  let wave = sin(dist * (freq * 50.0) - time * 5.0) * 0.02 * influence;

  // Apply distortion separately for RGB (chromatic aberration)
  // Red channel gets +jitter +wave
  // Green gets -jitter
  // Blue gets +wave -jitter

  let split = jitterAmount * 0.02 * influence;

  let uvR = uv + jitter + vec2<f32>(wave + split, 0.0);
  let uvG = uv - jitter + vec2<f32>(0.0, wave);
  let uvB = uv + jitter * 0.5 - vec2<f32>(split + wave, 0.0);

  let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Quantum Color Drift (Shift Hue based on probability)
  if (driftSpeed > 0.0 && influence > 0.01) {
      var hsv = rgb2hsv(color);
      // Shift hue based on local probability density (intensity + time)
      hsv.x = fract(hsv.x + (time * driftSpeed * 0.5) + (dist * 2.0));
      hsv.y = min(1.0, hsv.y + influence * 0.2); // Boost saturation near source
      color = hsv2rgb(hsv);
  }

  // Add interference patterns (scanline-ish)
  let interference = sin(uv.y * resolution.y * 0.5 + time * 10.0) * 0.5 + 0.5;
  color = mix(color, color * (0.8 + 0.2 * interference), influence * 0.5);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
