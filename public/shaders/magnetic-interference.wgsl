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
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Scanlines
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Mouse interaction
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

  let dist = distance(uv_corrected, mouse_corrected);

  // Params
  let strength = u.zoom_params.x; // Magnet Strength
  let radius = u.zoom_params.y;   // Radius
  let aberration = u.zoom_params.z; // Chromatic Aberration
  let scanline_intensity = u.zoom_params.w;

  // Magnetic distortion (pull towards mouse)
  // Falloff 1 / (d^2)
  let pull = strength * 0.05 / (pow(dist, 2.0) + 0.01);
  let influence = smoothstep(radius, 0.0, dist); // Only affect within radius

  let dir = uv - mouse;
  let displacement = dir * pull * influence;

  // Chromatic Aberration (R, G, B shift differently)
  let r_uv = uv - displacement * (1.0 + aberration);
  let g_uv = uv - displacement;
  let b_uv = uv - displacement * (1.0 - aberration);

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Scanlines (CRT effect) - localized distortion
  // Distort the scanlines themselves based on the magnetic field
  let scanline_uv_y = uv.y + length(displacement) * 10.0;
  let scanline = sin(scanline_uv_y * resolution.y * 0.5 + time * 5.0);
  let scanline_mask = 1.0 - (scanline * 0.5 + 0.5) * scanline_intensity;

  color = color * scanline_mask;

  // Update depth (pass through)
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
