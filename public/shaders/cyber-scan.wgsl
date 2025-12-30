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

// Cyber Scan
// Param1: Scan Width
// Param2: Grid Intensity
// Param3: Color Speed
// Param4: Edge Strength

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz; // Mouse (0-1)
  let time = u.config.x;

  // Params
  let scanWidth = u.zoom_params.x * 0.4 + 0.05; // 0.05 to 0.45
  let gridIntensity = u.zoom_params.y;
  let colorSpeed = u.zoom_params.z * 5.0;
  let edgeStrength = u.zoom_params.w * 5.0;

  // Scan band calculation
  // y distance to mouse y
  let distY = abs(uv.y - mousePos.y);
  // Smooth falloff
  let scanMask = 1.0 - smoothstep(scanWidth * 0.5, scanWidth, distY);

  var finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  if (scanMask > 0.01) {
    // Edge Detection (Sobel-ish)
    let stepX = 1.0 / resolution.x;
    let stepY = 1.0 / resolution.y;

    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;

    let edgeX = length(r - l);
    let edgeY = length(b - t);
    let edgeVal = length(vec2<f32>(edgeX, edgeY));

    // Grid Overlay
    let gridScale = 50.0;
    let gridX = abs(sin(uv.x * gridScale * 3.14159));
    let gridY = abs(sin(uv.y * gridScale * 3.14159));
    let gridVal = smoothstep(0.95, 1.0, max(gridX, gridY));

    // Cyber Color
    let hue = (time * colorSpeed) % 6.28;
    let cyberColor = vec3<f32>(
        0.5 + 0.5 * sin(hue),
        0.5 + 0.5 * sin(hue + 2.09),
        0.5 + 0.5 * sin(hue + 4.18)
    );

    // Apply effects based on scanMask
    let effectColor = mix(finalColor.rgb, cyberColor, gridVal * gridIntensity);
    let edgeColor = cyberColor * edgeVal * edgeStrength;

    // Combine
    let mixed = finalColor.rgb + edgeColor;

    // Add scanlines
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.1;

    let processed = mix(mixed, effectColor, gridVal * gridIntensity * 0.5) + scanline;

    finalColor = vec4<f32>(mix(finalColor.rgb, processed, scanMask), finalColor.a);
  } else {
      // Slightly dim outside
      finalColor = vec4<f32>(finalColor.rgb * 0.8, finalColor.a);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  // Depth Pass-through
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
