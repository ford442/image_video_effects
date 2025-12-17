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
  let tileSizeParam = max(0.01, u.zoom_params.x); // 0.0 to 1.0
  let tileSizeY = 0.05 + tileSizeParam * 0.15; // Range 0.05 to 0.2
  let tileSizeX = tileSizeY / aspect; // Square tiles

  let rotationStrength = u.zoom_params.y * 6.28; // Full circle range
  let influenceRadius = u.zoom_params.z; // 0 to 1

  // Grid calculations
  let tileGrid = vec2<f32>(1.0/tileSizeX, 1.0/tileSizeY);
  let tileIndex = floor(uv * tileGrid);
  let tileCenterUV = (tileIndex + 0.5) / tileGrid;

  // Distance from tile center to mouse (aspect corrected)
  let diff = tileCenterUV - mouse;
  let dist = length(diff * vec2<f32>(aspect, 1.0));

  // Rotation angle based on distance
  let angle = (1.0 - smoothstep(0.0, influenceRadius, dist)) * rotationStrength;

  // Rotate pixel relative to tile center
  let relUV = uv - tileCenterUV;

  // Correct aspect for rotation to keep square shape
  let relUV_corr = vec2<f32>(relUV.x * aspect, relUV.y);

  let cosA = cos(angle);
  let sinA = sin(angle);

  let rotated_corr = vec2<f32>(
    relUV_corr.x * cosA - relUV_corr.y * sinA,
    relUV_corr.x * sinA + relUV_corr.y * cosA
  );

  // Restore aspect
  let rotatedUV = vec2<f32>(rotated_corr.x / aspect, rotated_corr.y);

  let finalUV = tileCenterUV + rotatedUV;

  // Edge clamping? Texture sampler usually clamps or repeats.
  // For twist effect, we might want to clamp to tile?
  // Or just let it sample neighbors (cooler).

  let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
  textureStore(writeTexture, global_id.xy, color);
}
