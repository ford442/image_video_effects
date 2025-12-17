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
  let time = u.config.x;

  // Parameters
  let waveSpeed = mix(1.0, 10.0, u.zoom_params.x);     // Param 1: Speed
  let waveFreq = mix(10.0, 100.0, u.zoom_params.y);    // Param 2: Frequency
  let intensity = u.zoom_params.z;                     // Param 3: Intensity
  let waveWidth = mix(0.1, 0.5, u.zoom_params.w);      // Param 4: Width

  // Mouse Position (corrected for aspect ratio)
  let aspect = resolution.x / resolution.y;
  let mousePos = u.zoom_config.yz;

  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uv_corrected, mouse_corrected);

  // Sonar Pulse Logic
  // A series of expanding rings
  let phase = dist * waveFreq - time * waveSpeed;
  // Use a sawtooth or sharp sine for "sonar" look
  let wave = sin(phase);

  // Sharpen the wave to make it look like a pulse
  let pulse = smoothstep(1.0 - waveWidth, 1.0, wave);

  // Falloff with distance so it doesn't cover the whole screen equally
  let falloff = 1.0 / (1.0 + dist * 2.0);

  // Calculate Color Shift
  // We displace the UV slightly or add brightness
  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Add a green/blue tint based on pulse
  let pulseColor = vec4<f32>(0.0, 1.0, 0.5, 1.0) * pulse * intensity * falloff;

  // Also distort UV slightly
  let distortAmt = 0.02 * pulse * intensity;
  var offsetDir = vec2<f32>(0.0, 0.0);
  if (dist > 0.001) {
    offsetDir = normalize(uv_corrected - mouse_corrected);
  }
  let distortedUV = uv - offsetDir * distortAmt;
  let distortedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

  // Mix original with pulse
  var finalColor = mix(distortedColor, distortedColor + pulseColor, 0.5);

  // Ensure alpha is 1.0
  finalColor.a = 1.0;

  textureStore(writeTexture, global_id.xy, finalColor);

  // Passthrough depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
