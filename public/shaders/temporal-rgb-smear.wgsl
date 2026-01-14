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
  zoom_params: vec4<f32>,  // x=GreenLag, y=BlueLag, z=Feedback, w=unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Params
  // x: Green Channel Lag (0.0 - 1.0)
  // y: Blue Channel Lag (0.0 - 1.0)
  // z: Feedback amount (0.0 - 0.99)
  let greenLag = mix(0.1, 0.95, u.zoom_params.x);
  let blueLag = mix(0.2, 0.98, u.zoom_params.y);
  let feedback = u.zoom_params.z;

  // Mouse influence - reduce lag near mouse
  let mouse = u.zoom_config.yz;
  let dist = distance(uv, mouse);
  let mouseFactor = smoothstep(0.0, 0.3, dist); // 0 near mouse, 1 far

  // Modulate lag with mouse
  let gLag = greenLag * (0.5 + 0.5 * mouseFactor);
  let bLag = blueLag * (0.5 + 0.5 * mouseFactor);

  // Read current frame
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Read history (R=GreenHistory, G=BlueHistory)
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

  // Calculate new history values
  // We want: NewHistory = mix(Current, OldHistory, Lag)
  let newGreenHistory = mix(current.g, history.r, gLag);
  let newBlueHistory = mix(current.b, history.g, bLag);

  // Output color
  // R = Instant
  // G = Green History
  // B = Blue History
  let outputColor = vec4<f32>(current.r, newGreenHistory, newBlueHistory, current.a);

  // Store new history
  // Store G history in R, B history in G
  textureStore(dataTextureA, global_id.xy, vec4<f32>(newGreenHistory, newBlueHistory, 0.0, 1.0));

  // Write to screen
  textureStore(writeTexture, global_id.xy, outputColor);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
