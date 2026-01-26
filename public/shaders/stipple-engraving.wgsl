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

fn hash12(p: vec2<f32>) -> f32 {
	var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Params
  let density = u.zoom_params.x * 2.0 + 0.5; // 0.5 to 2.5
  let contrast = u.zoom_params.y * 2.0 + 0.5;
  let radius = u.zoom_params.z;
  let intensity = u.zoom_params.w;

  // Mouse interaction
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uvCorrected, mouseCorrected);

  // Sample texture
  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Calculate Luminance
  var lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));

  // Apply Contrast
  lum = (lum - 0.5) * contrast + 0.5;

  // Mouse Spotlight: Brighten the area under the mouse
  // This effectively reduces the stipple density (more white space)
  let spotlight = smoothstep(radius, 0.0, dist) * intensity;
  lum += spotlight;
  lum = clamp(lum, 0.0, 1.0);

  // Generate Noise
  // Scale UV by resolution and density for pixel-perfect or scaled noise
  let noiseUV = uv * resolution * (0.5 / density);
  let noise = hash12(noiseUV);

  // Stipple Comparison
  // If noise < luminance, we draw white (paper).
  // If noise > luminance, we draw black (ink).
  // But let's allow for some color blending if desired, or strict B&W.
  // Let's do strict B&W for the "Engraving" look.

  var finalColor = vec3<f32>(0.0);
  if (noise < lum) {
    finalColor = vec3<f32>(1.0); // Paper
  } else {
    finalColor = vec3<f32>(0.1, 0.1, 0.15); // Ink (dark blueish grey)
  }

  // Optional: Mix in a bit of original color based on mouse?
  // No, let's keep it purely stipple for style.

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
}
