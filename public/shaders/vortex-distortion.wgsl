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

// Vortex Distortion
// Param1: Twist Strength
// Param2: Radius
// Param3: Aberration
// Param4: Center Darkness

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz; // Mouse (0-1)

  // Params
  let twistStrength = (u.zoom_params.x - 0.5) * 20.0; // -10 to 10
  let radius = u.zoom_params.y * 0.8 + 0.1; // 0.1 to 0.9
  let aberration = u.zoom_params.z * 0.05;
  let darkness = u.zoom_params.w;

  // Vector from mouse
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  var finalColor = vec4<f32>(0.0);

  if (dist < radius) {
      // Calculate twist amount based on distance (stronger at center)
      let percent = (radius - dist) / radius;
      let theta = percent * percent * twistStrength;
      let s = sin(theta);
      let c = cos(theta);

      // Rotate coordinates
      // We need to rotate dVec around (0,0) then add back to mousePos
      // But we must correct aspect ratio for rotation to be circular
      var centered = vec2<f32>(dVec.x * aspect, dVec.y);
      let rotated = vec2<f32>(
          centered.x * c - centered.y * s,
          centered.x * s + centered.y * c
      );
      // Restore aspect
      let uvOffset = vec2<f32>(rotated.x / aspect, rotated.y);
      let twistedUV = mousePos + uvOffset;

      // Chromatic Aberration
      if (aberration > 0.001) {
          let rUV = twistedUV + vec2<f32>(aberration * percent, 0.0);
          let gUV = twistedUV;
          let bUV = twistedUV - vec2<f32>(aberration * percent, 0.0);

          let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
          let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
          let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
          let a = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

          finalColor = vec4<f32>(r, g, b, a);
      } else {
          finalColor = textureSampleLevel(readTexture, u_sampler, twistedUV, 0.0);
      }

      // Darkness at center
      finalColor = vec4<f32>(finalColor.rgb * (1.0 - darkness * percent), finalColor.a);

  } else {
      finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  // Depth Pass-through
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
