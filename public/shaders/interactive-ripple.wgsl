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

// Interactive Ripple
// Param1: Wave Speed
// Param2: Frequency
// Param3: Decay
// Param4: Specular / Wetness

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let mousePos = u.zoom_config.yz;

  let waveSpeed = u.zoom_params.x * 5.0 + 1.0;
  let frequency = u.zoom_params.y * 50.0 + 10.0;
  let decayFactor = u.zoom_params.z * 5.0 + 1.0;
  let specularStr = u.zoom_params.w;

  var totalHeight = 0.0;
  var totalSlope = vec2<f32>(0.0, 0.0);

  // 1. Handle Clicks (Ripples)
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
      let rData = u.ripples[i];
      let rPos = rData.xy;
      let rStart = rData.z;

      let t = currentTime - rStart;
      if (t > 0.0 && t < 4.0) { // Limit lifetime
          let dVec = uv - rPos;
          // Correct aspect ratio for distance
          let aspect = resolution.x / resolution.y;
          let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

          if (dist > 0.001) {
             let phase = dist * frequency - t * waveSpeed;
             // Wave packet function: sin(phase) * envelope
             // Envelope decays with time and distance
             let amp = 1.0 / (1.0 + t * decayFactor + dist * 20.0);

             let h = sin(phase) * amp;
             let s = cos(phase) * frequency * amp; // Approx derivative magnitude

             totalHeight += h;
             totalSlope += normalize(dVec) * s;
          }
      }
  }

  // 2. Handle Mouse Hover (Continuous disturbance)
  if (mousePos.x >= 0.0) {
      let dVec = uv - mousePos;
      let aspect = resolution.x / resolution.y;
      let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

      // Wake / Bow wave effect? Or just a depression?
      // Let's make a local depression that moves with mouse.
      let radius = 0.05;
      if (dist < radius * 2.0) {
          let t = dist / radius;
          // Smooth bump
          let h = -1.0 * exp(-t * t * 4.0);
          // Slope
          let s = h * (-2.0 * t * 4.0 / radius); // Chain rule approx

          totalHeight += h * 0.2; // Weaker than clicks
          totalSlope += normalize(dVec) * s * 0.2;
      }
  }

  // Distort UVs
  let distortion = totalSlope * 0.005;
  let finalUV = clamp(uv - distortion, vec2<f32>(0.0), vec2<f32>(1.0));

  var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  // Lighting (Specular)
  if (specularStr > 0.0) {
      // Normal from slope: (-slope.x, -slope.y, 1.0)
      let n = normalize(vec3<f32>(-totalSlope.x * 20.0, -totalSlope.y * 20.0, 1.0));
      let lightDir = normalize(vec3<f32>(-0.5, -0.5, 0.8));
      let viewDir = vec3<f32>(0.0, 0.0, 1.0);
      let h = normalize(lightDir + viewDir);
      let spec = pow(max(dot(n, h), 0.0), 64.0);

      color = color + vec4<f32>(spec * specularStr);
  }

  textureStore(writeTexture, global_id.xy, color);

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
