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
  let time = u.config.x;

  // Params
  let radius = u.zoom_params.x * 0.5; // 0.0 to 0.5
  let intensity = u.zoom_params.y;
  let mixVal = u.zoom_params.z;
  let pulseSpeed = u.zoom_params.w * 5.0;

  let mousePos = u.zoom_config.yz;

  // Aspect ratio correction
  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uvCorrected, mouseCorrected);

  // Pulsing radius
  let currentRadius = radius + sin(time * pulseSpeed) * 0.02;

  // Aura Mask (1.0 inside, 0.0 outside, with smooth edge)
  let mask = 1.0 - smoothstep(currentRadius, currentRadius + 0.05, dist);

  // Base Color
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Effect Color (Edge Detection / High Pass)
  let offset = 1.0 / resolution.x;
  let left = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-offset, 0.0), 0.0);
  let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0);
  let top = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -offset), 0.0);
  let bottom = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset), 0.0);

  let edges = abs(left - right) + abs(top - bottom);
  let effectColor = edges * 2.0 + vec4<f32>(0.0, 0.5, 1.0, 1.0) * intensity; // Cyan glow

  // Combine
  // Inside aura: mix between base and effect
  let inside = mix(baseColor, effectColor, mixVal);

  // Add a glowing ring at the edge
  let ring = smoothstep(currentRadius - 0.01, currentRadius, dist) * smoothstep(currentRadius + 0.01, currentRadius, dist);
  let ringColor = vec4<f32>(1.0, 1.0, 1.0, 1.0) * ring * intensity * 2.0;

  var finalColor = mix(baseColor, inside, mask) + ringColor;

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
