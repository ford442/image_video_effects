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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=PulseSpeed, y=GlowStrength, z=EdgeThreshold, w=MouseRadius
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let mousePos = u.zoom_config.yz;

  let speed = u.zoom_params.x * 5.0;
  let glowStr = u.zoom_params.y * 2.0;
  let threshold = u.zoom_params.z;
  let radius = u.zoom_params.w; // 0 to 1

  // Sobel Edge Detection
  let texel = vec2<f32>(1.0) / resolution;

  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;

  let gx = length(l - r);
  let gy = length(t - b);
  let edge = sqrt(gx*gx + gy*gy);

  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  if (edge > threshold) {
      // Base Neon Color
      var neon = vec3<f32>(
          0.5 + 0.5 * sin(time * speed),
          0.5 + 0.5 * sin(time * speed + 2.0),
          0.5 + 0.5 * sin(time * speed + 4.0)
      );

      // Mouse Interaction
      let aspect = resolution.x / resolution.y;
      let dVec = uv - mousePos;
      let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

      // Pulse based on distance
      let pulse = 1.0 - smoothstep(0.0, radius, dist);

      // If mouse is close, intensify and shift color
      let interaction = pulse * glowStr * 2.0;

      neon = mix(neon, vec3<f32>(1.0, 1.0, 1.0), interaction);

      // Add glow to original color or replace it
      color = vec4<f32>(mix(color.rgb, neon, glowStr + interaction), color.a);
  }

  textureStore(writeTexture, global_id.xy, color);
}
