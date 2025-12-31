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
  let uv = vec2<f32>(global_id.xy) / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Parameters
  let edgeThreshold = u.zoom_params.x;
  let lightRadius = u.zoom_params.y;
  let glowIntensity = u.zoom_params.z;
  let colorCycle = u.zoom_params.w;

  // Mouse Position (y=MouseX, z=MouseY in zoom_config)
  let mousePos = u.zoom_config.yz;

  // Aspect Ratio Correction for distance
  let aspect = resolution.x / resolution.y;
  let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);

  // Sobel Edge Detection
  let texelSize = 1.0 / resolution;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).rgb;
  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).rgb;

  let lum = vec3<f32>(0.299, 0.587, 0.114);
  let gx = dot(r - l, lum);
  let gy = dot(b - t, lum);
  let edge = sqrt(gx*gx + gy*gy);

  // Threshold
  let isEdge = smoothstep(edgeThreshold, edgeThreshold + 0.05, edge);

  // Light falloff
  let light = smoothstep(lightRadius, 0.0, dist);

  // Base Color
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Edge Color
  // Rainbow cycle based on time/colorCycle param + angle
  let angle = atan2(distVec.y, distVec.x);
  let hue = u.config.x * colorCycle + angle * 0.5;
  let rgb = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
  );

  // Combine
  let edgeGlow = rgb * isEdge * glowIntensity * (light + 0.2); // +0.2 ambient
  let reveal = baseColor.rgb * (light * 0.8 + 0.1); // Dim original image outside light

  // Mix: mostly edge glow, but reveal original image under the light too
  let finalColor = mix(reveal, edgeGlow + reveal, isEdge);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

  // Pass through depth (required for depth chain)
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
