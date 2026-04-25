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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;

  // Mouse position
  var mouse = u.zoom_config.yz;

  // Parameters
  let strength = u.zoom_params.x * 0.5;
  let decay = u.zoom_params.y;
  let glow = u.zoom_params.z;
  let exponent = mix(0.2, 3.0, u.zoom_params.w);

  let samples = 30;

  var color = vec4<f32>(0.0);

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let reactiveStrength = strength * (1.0 + bass * 0.3);

  // Vector from current pixel to mouse
  var dir = mouse - uv;

  // Accumulate
  for (var i = 0; i < samples; i++) {
    var t = f32(i) / f32(samples - 1);
    t = pow(t, exponent);

    // Sample position: move towards mouse
    let offset = dir * reactiveStrength * t;
    let sampleUV = uv + offset;

    var sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    sampleColor *= (1.0 - decay * t);
    color += sampleColor;
  }

  color = color / f32(samples);
  color *= (1.0 + glow);

  textureStore(writeTexture, vec2<i32>(global_id.xy), color);

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
