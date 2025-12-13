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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

// Cyber Lens Effect
// Param1: Lens Radius
// Param2: Zoom Strength
// Param3: Grid Intensity
// Param4: Chromatic Aberration

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Mouse position passed via zoom_config.yz
  let mousePos = u.zoom_config.yz;

  // Parameters
  let lensRadius = max(0.01, u.zoom_params.x * 0.5); // Max radius 0.5
  let zoomStrength = 1.0 + u.zoom_params.y * 4.0; // 1.0 to 5.0
  let gridIntensity = u.zoom_params.z;
  let aberration = u.zoom_params.w * 0.1;

  // Calculate distance to mouse
  // Adjust for aspect ratio
  let aspect = resolution.x / resolution.y;
  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_aspect = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = length(uv_aspect - mouse_aspect);

  var finalUV = uv;
  var inLens = 0.0;

  if (mousePos.x >= 0.0 && dist < lensRadius) {
    // Lens distortion (Bulge)
    // Map dist from 0..radius to 0..1
    let t = dist / lensRadius;
    // Distortion function: sin(t * PI / 2) makes it bulge out
    // Better: t * pow(t, zoomStrength) or similar.
    // Let's use simple magnification.
    // P_new = Center + (P - Center) / zoom
    // But we want non-linear.

    // Fish-eye
    let theta = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
    let r = dist; // Real distance
    // Distorted radius: r' = r / zoom at center, r at edge.
    // Function that maps 0->0 and R->R, but slope at 0 is 1/zoom.
    // r' = r * (1 + (zoom-1) * (r/R)^k) ? No

    // Let's use: r_new = r * (1.0 - smoothstep(0.0, lensRadius, r) * (1.0 - 1.0/zoomStrength));
    // Actually standard fish eye: r_new = r^k.

    // Let's interpolate UV.
    let mag = mix(1.0 / zoomStrength, 1.0, smoothstep(0.0, lensRadius, dist));
    // Relative vector
    let offset = uv - mousePos;
    finalUV = mousePos + offset * mag;

    // Soft edge for lens mask
    inLens = smoothstep(lensRadius, lensRadius - 0.02, dist);
  }

  // --- Grid Effect inside lens ---
  var gridColor = vec3<f32>(0.0);
  if (inLens > 0.0 && gridIntensity > 0.0) {
      // Grid based on distorted UVs to look like it's on the lens surface
      let gridSize = 40.0;
      let gridUV = finalUV * gridSize;
      let gridX = abs(fract(gridUV.x - time * 0.5) - 0.5);
      let gridY = abs(fract(gridUV.y + time * 0.2) - 0.5);
      let gridLine = smoothstep(0.45, 0.48, max(gridX, gridY));

      let pulse = 0.5 + 0.5 * sin(time * 5.0);
      gridColor = vec3<f32>(0.0, 1.0, 0.8) * gridLine * gridIntensity * pulse;
  }

  // --- Chromatic Aberration ---
  var color = vec4<f32>(0.0);
  if (inLens > 0.0 && aberration > 0.0) {
      // Radial aberration
      let dir = normalize(uv - mousePos);
      let rUV = finalUV - dir * aberration * inLens;
      let bUV = finalUV + dir * aberration * inLens;

      let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
      let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
      let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

      color = vec4<f32>(r, g, b, 1.0);
  } else {
      color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
  }

  // Combine grid
  color = vec4<f32>(color.rgb + gridColor * inLens, color.a);

  // Lens Border
  let border = smoothstep(lensRadius - 0.005, lensRadius, dist) * smoothstep(lensRadius + 0.005, lensRadius, dist);
  color = mix(color, vec4<f32>(0.0, 1.0, 1.0, 1.0), border * inLens * 2.0);

  // Write output
  textureStore(writeTexture, global_id.xy, color);

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
