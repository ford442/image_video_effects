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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;

  // Params
  let density = 20.0 + u.zoom_params.x * 100.0; // Grid density
  let influenceRadius = u.zoom_params.y; // 0-1
  let contrast = 0.5 + u.zoom_params.z * 2.0;

  // Correct UV for aspect to get circular dots
  let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
  let scale = vec2<f32>(density, density);

  let gridUV = aspectUV * scale;
  let cellIndex = floor(gridUV);
  let cellLocalUV = fract(gridUV); // 0-1 within cell
  let cellCenter = vec2<f32>(0.5, 0.5);

  // Reconstruct UV of the cell center to sample texture
  let cellCenterUV = (cellIndex + cellCenter) / scale;
  // Un-correct aspect for texture sampling
  let sampleUV = vec2<f32>(cellCenterUV.x / aspect, cellCenterUV.y);

  // Sample texture
  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Mouse Influence
  let distToMouse = length((sampleUV - mouse) * vec2<f32>(aspect, 1.0));
  let influence = smoothstep(influenceRadius, 0.0, distToMouse); // 1.0 near mouse

  // Determine Dot Radius
  // Base radius depends on luma
  var radius = luma * 0.5; // max 0.5

  // Mouse interaction: Make dots bigger near mouse (highlight)
  radius = radius * (1.0 + influence * 0.8);
  radius = clamp(radius, 0.0, 0.6); // Allow slightly overlapping

  // Distance from current pixel to cell center
  let distToDotCenter = length(cellLocalUV - cellCenter);

  var finalColor = vec3<f32>(0.0);

  // Soft edge for anti-aliasing
  let edgeWidth = 0.05 * (1.0 + influence); // Sharper near mouse? No, smoother.
  let alpha = 1.0 - smoothstep(radius - edgeWidth, radius + edgeWidth, distToDotCenter);

  // Mix color
  finalColor = mix(vec3<f32>(0.0), color.rgb, alpha);

  // Apply contrast
  finalColor = pow(finalColor, vec3<f32>(contrast));

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
