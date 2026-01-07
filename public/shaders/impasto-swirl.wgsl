// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let brushSize = u.zoom_params.x * 0.1 + 0.01;
  let smudgeStrength = u.zoom_params.y; // 0 to 1
  let drySpeed = u.zoom_params.z * 0.1 + 0.001; // How fast it reverts to source
  let noiseAmt = u.zoom_params.w;

  // Aspect correct distance
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // Determine if we are under the "brush"
  let brushMask = smoothstep(brushSize, brushSize * 0.5, dist);

  // Read current input (video/image)
  let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  // Read history (previous state)
  let historyFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Initialize output
  var finalColor = currentFrame;

  // If this is the first frame or history is empty, initialize with current
  if (historyFrame.a == 0.0) {
      finalColor = currentFrame;
  } else {
      // Logic:
      // We want to "push" pixels if the mouse is moving.
      // Since we don't have velocity explicitly, we can just smear towards the mouse?
      // Or simply: at the mouse position, we blend strongly with history?
      // Actually "Impasto" implies mixing.
      // Let's create a swirl offset.
      let angle = time * 2.0;
      let offset = vec2<f32>(cos(angle), sin(angle)) * brushSize * 0.5;

      // If brush is active here
      if (brushMask > 0.0) {
         // Sample from slightly offset position in history to simulate dragging
         // We push pixels AWAY from center (spread) or rotate them.
         // Let's rotate.
         let rotUV = uv + vec2<f32>(dVec.y, -dVec.x) * smudgeStrength * 2.0;
         let mixedSample = textureSampleLevel(dataTextureC, u_sampler, rotUV, 0.0);

         // Mix current frame with smeared history
         // If smudge is high, we see more history.
         finalColor = mix(currentFrame, mixedSample, smudgeStrength * brushMask);
      } else {
         // Outside brush, slowly fade back to current frame (paint drying)
         finalColor = mix(historyFrame, currentFrame, drySpeed);
      }
  }

  // Noise texture overlay for canvas effect
  // Simple hash noise
  let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  finalColor = mix(finalColor, finalColor * (0.9 + 0.2 * noise), noiseAmt);

  // Ensure alpha is 1
  finalColor.a = 1.0;

  textureStore(writeTexture, global_id.xy, finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor); // Save to history

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
