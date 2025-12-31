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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SwirlStrength, y=Radius, z=Smoothness, w=AutoRotation
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  let mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let strength = (u.zoom_params.x - 0.5) * 10.0; // -5 to 5
  let radius = u.zoom_params.y * 0.8 + 0.01;
  let smoothness = u.zoom_params.z;
  let autoRot = (u.zoom_params.w - 0.5) * 4.0;

  // Calculate distance to center (mouse)
  let aspect = resolution.x / resolution.y;
  let center = mousePos;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let center_corrected = vec2<f32>(center.x * aspect, center.y);
  let dist = distance(uv_corrected, center_corrected);

  // Twist calculation
  if (dist < radius) {
      let percent = (radius - dist) / radius;
      let theta = percent * percent * (strength + autoRot * time);
      let s = sin(theta);
      let c = cos(theta);

      let d = uv - center;
      // Correct aspect for rotation to keep it circular
      d.x = d.x * aspect;

      let new_d = vec2<f32>(
          d.x * c - d.y * s,
          d.x * s + d.y * c
      );

      // Uncorrect aspect
      new_d.x = new_d.x / aspect;

      var finalUV = center + new_d;

      // Smooth mixing at edges to prevent harsh lines
      // Actually standard swirl naturally falls off if percent goes to 0 at radius

      // Bounds check
      finalUV = clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0));

      let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
      textureStore(writeTexture, global_id.xy, color);
  } else {
      let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
      textureStore(writeTexture, global_id.xy, color);
  }
}
