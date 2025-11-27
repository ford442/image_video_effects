@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;

  // Sample depth
  let center_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Mask: Only affect foreground (depth < 1.0).
  // depth 0 is near, 1 is far.
  // We want to affect things that are NOT at the far plane.
  // Let's say background is anything > 0.9.
  let fg_factor = 1.0 - smoothstep(0.8, 0.95, center_depth);

  var totalSlope = vec2<f32>(0.0, 0.0);
  var totalHeight = 0.0;

  if (fg_factor > 0.0) {
      let rippleCount = u32(u.config.y);
      for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rippleData = u.ripples[i];
        let timeSinceClick = currentTime - rippleData.z;

        // Metallic ripples last longer and travel faster
        if (timeSinceClick > 0.0 && timeSinceClick < 4.0) {
          let direction_vec = uv - rippleData.xy;
          let dist = length(direction_vec);

          if (dist > 0.0001) {
            let rippleOriginDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, rippleData.xy, 0.0).r;
            // Only create ripples if click was on foreground?
            // Or allow clicking anywhere but mask the effect?
            // Let's assume click interacts with the "fluid" everywhere, but visual is masked.

            let speed = 2.0;
            let freq = 30.0;
            let decay = 4.0;

            let phase = dist * freq - timeSinceClick * speed;
            let attenuation = 1.0 / (1.0 + timeSinceClick * decay + dist * 40.0);

            // Height: sin wave
            let h = sin(phase) * attenuation;

            // Slope (Derivative): cos wave * k
            // Directional slope
            let s = cos(phase) * freq * attenuation;
            let slopeVec = normalize(direction_vec) * s;

            totalHeight += h;
            totalSlope += slopeVec;
          }
        }
      }
  }

  // Combine ambient slope if desired, or keep it clean metal
  // Let's add slight ambient metal warping
  let time = currentTime * 0.5;
  let ambient = vec2<f32>(
      sin(uv.y * 10.0 + time),
      cos(uv.x * 10.0 + time)
  ) * 0.05;

  totalSlope += ambient * fg_factor;

  // --- 3D Lighting & Refraction ---

  // Refraction: Offset UVs based on surface slope
  let distortionStrength = 0.01;
  let displacedUV = uv + totalSlope * distortionStrength * fg_factor;

  // Clamp UVs
  let clampedUV = clamp(displacedUV, vec2(0.0), vec2(1.0));

  // Sample Color
  var color = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0).rgb;

  // Specular Lighting
  // Construct normal from slope.
  // Slope is (dz/dx, dz/dy). Normal is (-slope.x, -slope.y, 1).
  let normalStrength = 3.0; // Exaggerate geometry
  let normal = normalize(vec3<f32>(-totalSlope.x * normalStrength, -totalSlope.y * normalStrength, 1.0));

  // Lighting source (Mouse follows? or Static?)
  // Static top-left light for distinct 3D look
  let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));

  // Blinn-Phong Specular
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfDir = normalize(lightDir + viewDir);
  let NdotH = max(dot(normal, halfDir), 0.0);
  let specular = pow(NdotH, 128.0); // Sharp, metallic highlight

  // Environment reflection approximation (chromatic fringe)
  let fringe = vec3<f32>(totalSlope.x, totalSlope.y, 0.0) * 0.05;
  color += fringe * fg_factor;

  // Apply lighting
  let lightColor = vec3<f32>(1.0, 0.95, 0.9); // Warm light
  let finalColor = color + lightColor * specular * fg_factor * 0.8;

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

  // Pass through depth (or warp it too? Warping depth might cause artifacts in next frame if re-used)
  // Let's warp depth slightly to match refraction
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
