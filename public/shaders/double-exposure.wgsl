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

fn rotate2d(uv: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(
        uv.x * c - uv.y * s,
        uv.x * s + uv.y * c
    );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Params
  // Zoom: Map 0.0-1.0 to 0.5x - 3.0x
  let zoomParam = u.zoom_params.x;
  let zoom = 0.5 + zoomParam * 2.5;

  // Rotation: Map 0.0-1.0 to -PI/4 to PI/4 (approx)
  let rotParam = u.zoom_params.y;
  let angle = (rotParam - 0.5) * 1.57; // +/- 45 degrees

  let opacity = u.zoom_params.z;
  let saturation = u.zoom_params.w;

  // Mouse interaction
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  // Sample 1: Base Image
  let c1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Sample 2: Transformed Image
  // Correct aspect ratio for rotation/scale pivot
  var p = uv - mouse;
  p.x *= aspect;

  // Rotate
  p = rotate2d(p, angle);

  // Scale (Zoom)
  // To zoom IN, we divide the UV coordinates
  p = p / zoom;

  // Restore aspect and origin
  p.x /= aspect;
  let uv2 = p + mouse;

  // Check bounds for uv2 to avoid clamping artifacts if desired,
  // but textureSampleLevel usually handles clamping or wrapping.
  // Using u_sampler which usually repeats or clamps.
  let c2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0);

  // Blend Logic
  // Screen Blend: 1 - (1-a)*(1-b)
  var blended = 1.0 - (1.0 - c1.rgb) * (1.0 - c2.rgb * opacity);

  // Optional Saturation adjustment for the overlay effect
  let gray = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
  blended = mix(vec3<f32>(gray), blended, 0.5 + saturation * 0.5);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(blended, 1.0));
}
