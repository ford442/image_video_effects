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

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
      return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Params
  let layerParam = u.zoom_params.x; // Number of layers (normalized 0-1)
  let shadowStrength = u.zoom_params.y; // Shadow intensity
  let smoothness = u.zoom_params.z; // Edge smoothness
  let separationParam = u.zoom_params.w; // Layer height separation

  let layers = floor(mix(2.0, 8.0, layerParam));
  let separation = mix(0.002, 0.02, separationParam);

  // Mouse interaction for light direction
  let mouse = u.zoom_config.yz;

  // Calculate light direction from mouse to center (or mouse acts as light source)
  // Let's make mouse the light source.
  // Light Vector = Pixel - Mouse.
  // Shadow is cast away from light.

  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);

  // Normalized vector from mouse to pixel
  var lightDir = uvCorrected - mouseCorrected;
  let dist = length(lightDir);
  if (dist > 0.001) {
      lightDir = normalize(lightDir);
  } else {
      lightDir = vec2<f32>(0.0, 0.0);
  }

  // Adjust lightDir back to UV space
  lightDir = vec2<f32>(lightDir.x / aspect, lightDir.y);

  // Get current pixel color and quantize it to determine its "height" (layer)
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let gray = getLuminance(baseColor);

  // Quantize gray to find which layer this pixel belongs to (0 to 1)
  // 0.0 = Bottom, 1.0 = Top
  // We use quantized gray as height
  let layerHeight = floor(gray * layers) / (layers - 1.0);

  // To render shadows, we check if a "higher" layer casts a shadow on current pixel.
  // We step towards the light source (inverse of shadow direction) to see if we hit a higher layer.
  // Actually, shadow is cast *away* from light.
  // If light is at mouse, shadow falls away from mouse.
  // To check if I am in shadow, I look *towards* the light.
  // If I find a pixel closer to the light that has a height > my height, I am in shadow.

  var shadowFactor = 0.0;
  let steps = 5;

  // We only check a short distance determined by separation
  let stepSize = separation * 2.0;

  for (var i = 1; i <= 5; i++) {
      let sampleUV = uv - lightDir * (f32(i) * stepSize);

      // Check bounds
      if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) {
          continue;
      }

      let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      let sampleGray = getLuminance(sampleColor);
      let sampleLayer = floor(sampleGray * layers) / (layers - 1.0);

      // If the sampled pixel is on a higher layer than current pixel
      if (sampleLayer > layerHeight) {
          // It casts a shadow on us
          // Closer samples cast harder shadows
          shadowFactor = max(shadowFactor, (1.0 - f32(i)/f32(steps)) * shadowStrength);
      }
  }

  // Apply posterization to color
  // We preserve the hue/sat but snap the value
  // Simple way: multiply rgb by scalar
  let quantizedGray = floor(gray * layers) / layers;
  // Normalize back to 0-1 range approx
  let valMult = (quantizedGray + (0.5/layers)) / (gray + 0.001);
  var finalColor = baseColor * valMult;

  // Apply smoothness to edges of quantization?
  // Maybe too complex for now. The "cutout" look implies sharp edges.
  // But we can anti-alias the quantization threshold.

  // Apply Shadow
  finalColor = finalColor * (1.0 - shadowFactor);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
}
