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
  let time = u.config.x;

  // Params
  let strength = u.zoom_params.x; // Distortion
  let speed = u.zoom_params.y;    // Pulse Speed
  let glowIntensity = u.zoom_params.z; // Neon Glow
  let radiusParam = u.zoom_params.w;   // Radius

  // Mouse interaction
  // u.zoom_config: x=Time, y=MouseX, z=MouseY, w=MouseDown (if mouse-driven)
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  // Adjusted coordinates for aspect ratio correct distance
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uvCorrected, mouseCorrected);

  // Dynamic radius pulse
  let pulse = sin(time * (speed * 5.0 + 1.0) - dist * 20.0) * 0.5 + 0.5;
  let effectRadius = radiusParam * 0.5 + 0.1;

  // Calculate falloff
  let falloff = smoothstep(effectRadius, 0.0, dist);

  // Distortion offset
  let angle = atan2(uv.y - mouse.y, uv.x - mouse.x);
  let wave = sin(dist * 40.0 - time * (speed * 10.0)) * falloff * strength * 0.05;
  let offset = vec2<f32>(cos(angle), sin(angle)) * wave;

  let distortedUV = uv + offset;

  // Edge detection / Neon glow
  // Sample surrounding pixels to detect edges
  let pixelSize = 1.0 / resolution;
  let c = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;
  let l = textureSampleLevel(readTexture, u_sampler, distortedUV - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
  let t = textureSampleLevel(readTexture, u_sampler, distortedUV - vec2<f32>(0.0, pixelSize.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(0.0, pixelSize.y), 0.0).rgb;

  let edgeX = length(l - r);
  let edgeY = length(t - b);
  let edge = sqrt(edgeX * edgeX + edgeY * edgeY);

  // Create neon color based on time and angle
  let hue = fract(time * 0.2 + dist * 2.0);
  let neonColor = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
  );

  // Mix original color with neon edge
  let glow = neonColor * edge * glowIntensity * 5.0 * falloff;
  let finalColor = c + glow;

  // Add the pulse ring
  let ring = smoothstep(0.02, 0.0, abs(dist - effectRadius * pulse));
  finalColor += neonColor * ring * glowIntensity;

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
