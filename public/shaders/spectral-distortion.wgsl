// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Spectral Distortion
// Param1: RGB Separation
// Param2: Warp Scale
// Param3: Mouse Influence
// Param4: Speed

fn noise(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Simple value noise
fn value_noise(st: vec2<f32>) -> f32 {
    let i = floor(st);
    let f = fract(st);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(noise(i + vec2<f32>(0.0, 0.0)),
                   noise(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(noise(i + vec2<f32>(0.0, 1.0)),
                   noise(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let separation = u.zoom_params.x * 0.1; // Max 0.1 UV units
  let warpScale = u.zoom_params.y * 20.0 + 1.0;
  let mouseInf = u.zoom_params.z;
  let speed = u.zoom_params.w * 2.0;

  var warpStr = 0.02; // Base warp strength

  // Increase warp near mouse
  if (mousePos.x >= 0.0) {
      let aspect = resolution.x / resolution.y;
      let dVec = uv - mousePos;
      let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

      let influenceRadius = 0.3;
      let influence = 1.0 - smoothstep(0.0, influenceRadius, dist);
      warpStr += influence * mouseInf * 0.1;
  }

  // Generate warp fields for R, G, B
  let t = time * speed;
  let nR = value_noise(uv * warpScale + vec2<f32>(t, t));
  let nG = value_noise(uv * warpScale + vec2<f32>(t + 10.0, -t));
  let nB = value_noise(uv * warpScale + vec2<f32>(-t, t + 5.0));

  let offR = vec2<f32>(nR - 0.5, value_noise(uv * warpScale + 100.0) - 0.5) * warpStr + vec2<f32>(separation, 0.0);
  let offG = vec2<f32>(nG - 0.5, value_noise(uv * warpScale + 200.0) - 0.5) * warpStr;
  let offB = vec2<f32>(nB - 0.5, value_noise(uv * warpScale + 300.0) - 0.5) * warpStr - vec2<f32>(separation, 0.0);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + offG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + offB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}
