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

  // Params
  // x: Radius (2 to 10)
  // y: Saturation Boost (0.0 to 1.0)
  // z: Mouse Falloff (0.0 to 1.0) - How much mouse clears the effect
  // w: Hardness (0.0 to 1.0) - Sharpness of the segments

  let radiusParam = u.zoom_params.x * 8.0 + 2.0; // Range 2-10
  let satBoost = u.zoom_params.y * 2.0;
  let mouseFalloff = u.zoom_params.z;
  let hardness = u.zoom_params.w; // Actually used for mixing variance weight or similar

  // Mouse interaction
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

  // Modulate radius based on mouse distance
  // If mouseFalloff is high, radius is 0 near mouse (clear image)
  let mouseFactor = smoothstep(0.0, 0.5, dist);
  // If we want clear near mouse:
  let effectiveRadius = mix(radiusParam, 0.0, (1.0 - mouseFactor) * mouseFalloff);

  if (effectiveRadius < 1.0) {
    // Optimization: Just sample directly if radius is small
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    textureStore(writeTexture, global_id.xy, color);
    return;
  }

  let radius = i32(effectiveRadius);
  let pixelSize = 1.0 / resolution;

  // Kuwahara Filter (simplified sector logic)
  // 4 sectors: TL, TR, BL, BR

  var mean: array<vec3<f32>, 4>;
  var sigma: array<vec3<f32>, 4>;

  // Initialize
  for(var i=0; i<4; i++) {
    mean[i] = vec3<f32>(0.0);
    sigma[i] = vec3<f32>(0.0);
  }

  let offsets = array<vec2<i32>, 4>(
    vec2<i32>(-radius, -radius), // TL
    vec2<i32>(0, -radius),       // TR
    vec2<i32>(-radius, 0),       // BL
    vec2<i32>(0, 0)              // BR
  );

  // Loop through sectors
  // We can optimize by not iterating fully 4 times separately but let's be explicit

  for (var k = 0; k < 4; k++) {
      var count = 0.0;
      let start = offsets[k];

      for (var j = 0; j <= radius; j++) {
          for (var i = 0; i <= radius; i++) {
              let sampleUV = uv + vec2<f32>(f32(start.x + i), f32(start.y + j)) * pixelSize;
              let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
              mean[k] += col;
              sigma[k] += col * col;
              count += 1.0;
          }
      }
      mean[k] /= count;
      sigma[k] = abs(sigma[k] / count - mean[k] * mean[k]);
  }

  // Find sector with min variance
  var minVar = 1000.0;
  var finalColor = vec3<f32>(0.0);

  for (var k = 0; k < 4; k++) {
      let v = sigma[k].r + sigma[k].g + sigma[k].b;
      if (v < minVar) {
          minVar = v;
          finalColor = mean[k];
      }
  }

  // Apply saturation boost
  let lum = dot(finalColor, vec3<f32>(0.2126, 0.7152, 0.0722));
  let satColor = mix(vec3<f32>(lum), finalColor, 1.0 + satBoost);

  textureStore(writeTexture, global_id.xy, vec4<f32>(satColor, 1.0));
}
