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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=WindSpeed, y=Decay, z=Threshold, w=DirectionNoise
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Params
  let speed = mix(0.0, 0.05, u.zoom_params.x); // Max displacement
  let decay = mix(0.8, 0.99, u.zoom_params.y);
  let threshold = u.zoom_params.z;
  let noiseAmt = u.zoom_params.w;

  // Mouse wind direction
  let mouse = u.zoom_config.yz;
  // If mouse is at center (default 0,0 or similar), default wind is to right
  var windDir = vec2<f32>(1.0, 0.0);
  if (mouse.x > 0.0 && mouse.y > 0.0) {
      windDir = normalize(uv - mouse); // Blow away from mouse
  }

  // Get current frame
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = luminance(current.rgb);

  // Read previous state (simulation)
  // We want to sample UPWIND
  // Since we write to 'uv', we look at 'uv - windDir'

  // Modulate wind speed by luminance (lighter = faster)
  // If pixel is dark, it doesn't move much.
  var localSpeed = speed * luma;
  if (luma < threshold) { localSpeed = 0.0; }

  // Add noise to direction
  let noise = (hash12(uv * 100.0 + time) - 0.5) * noiseAmt;
  let noisyWind = normalize(windDir + vec2<f32>(0.0, noise));

  let sourceUV = uv - noisyWind * localSpeed;

  // Sample the accumulated history from 'sourceUV'
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, sourceUV, 0.0);

  // Mix current frame into history
  // If we just use history, it smears forever. We need to inject new color.
  // Injection rate depends on if we are "source" or "trail".
  // High injection rate = less smear.
  let injection = 0.1;
  let newColor = mix(history, current, injection);

  // Apply decay to fade out old trails
  let finalColor = newColor * decay;

  // Store simulation state
  textureStore(dataTextureA, global_id.xy, finalColor);

  // Output to screen
  textureStore(writeTexture, global_id.xy, finalColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
