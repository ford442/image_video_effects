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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Parameters
  let gridScale = mix(10.0, 150.0, u.zoom_params.x);   // Param 1: Tile Size (Frequency)
  let focusRadius = u.zoom_params.y * 0.8;             // Param 2: Radius
  let edgeHardness = u.zoom_params.z;                  // Param 3: Edge Hardness
  let satBoost = u.zoom_params.w;                      // Param 4: Saturation Boost

  // Aspect ratio correction for hexagonal grid
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);

  // Hex Grid Math
  let r = vec2<f32>(1.0, 1.7320508); // 1, sqrt(3)
  let h = r * 0.5;

  let uvScaled = uv * aspectVec * gridScale;

  let uvA = uvScaled / r;
  let idA = floor(uvA + 0.5);
  let uvB = (uvScaled - h) / r;
  let idB = floor(uvB + 0.5);

  let centerA = idA * r;
  let centerB = idB * r + h;

  let distA = distance(uvScaled, centerA);
  let distB = distance(uvScaled, centerB);

  // Find closest center
  let center = select(centerB, centerA, distA < distB);

  // Map back to UV space (0-1)
  let centerUV = center / gridScale / aspectVec;

  // Sample texture at hex center
  var hexColor = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);
  let origColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Saturation Boost (Simple)
  let gray = dot(hexColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  hexColor = mix(vec4<f32>(gray, gray, gray, 1.0), hexColor, 1.0 + satBoost);

  // Mouse Interaction
  let mousePos = u.zoom_config.yz;
  let d = distance(uv * aspectVec, mousePos * aspectVec);

  // Calculate mask: 0 = Clear (near mouse), 1 = Hex (far)
  let mask = smoothstep(focusRadius, focusRadius + (1.0 - edgeHardness) * 0.2, d);

  var finalColor = mix(origColor, hexColor, mask);
  finalColor.a = 1.0;

  textureStore(writeTexture, global_id.xy, finalColor);

  // Passthrough depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
