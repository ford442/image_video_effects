@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;

  // --- Pixelation / Glitch Grid ---
  // Determine block size dynamically based on mouse activity?
  // Let's keep it constant for the "glitch" look.
  let blockSize = vec2<f32>(16.0, 16.0); // Pixels per block
  let blockUV = floor(uv * resolution / blockSize) * blockSize / resolution;

  // Use block center for calculations to keep blocks uniform
  let calculationUV = blockUV + (blockSize / resolution) * 0.5;

  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;

    if (timeSinceClick > 0.0 && timeSinceClick < 1.0) { // Short, sharp glitches
      let direction_vec = calculationUV - rippleData.xy;
      let dist = length(direction_vec);

      // Digital noise burst
      if (dist > 0.0001) {
        let speed = 5.0;
        let wave = step(0.8, sin(dist * 50.0 - timeSinceClick * speed)); // Square wave!
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick);

        // Randomize direction per block
        let rand = hash(blockUV * 100.0 + currentTime);
        let randDir = vec2<f32>(cos(rand * 6.28), sin(rand * 6.28));

        mouseDisplacement += randDir * wave * 0.05 * attenuation;
      }
    }
  }

  // Add some random "bad signal" offsets occasionally
  let noise = hash(vec2(floor(currentTime * 10.0), blockUV.y));
  if (noise > 0.98) {
      mouseDisplacement.x += 0.1;
  }

  let displacedUV = uv + mouseDisplacement; // Apply block offset to pixel UV

  // Chromatic Aberration (Vertical only, like VHS)
  let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2(0.01, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2(0.01, 0.0), 0.0).b;

  // Scanlines
  let scanline = sin(uv.y * resolution.y * 0.5) * 0.1;
  let color = vec3(r, g, b) - scanline;

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
