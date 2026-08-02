struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Audio: bass deepens layering, mids lengthens shadows, treble softens edges
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params
  let num_layers = mix(2.0, 10.0, u.zoom_params.x) * (1.0 + bass * 0.3);
  let shadow_dist = u.zoom_params.y * 0.1 * (1.0 + mids * 0.5);
  let softness = clamp(u.zoom_params.z + treble * 0.3, 0.0, 1.0);
  let separation = u.zoom_params.w;

  let time = u.config.x;
  let rawMouse = u.zoom_config.yz;

  // Spring-damped light direction. A real top-left pointer position (0,0) is no
  // longer mistaken for an uninitialized mouse. State uses only [133..138].
  let hasSpringState = arrayLength(&extraBuffer) > 138u;
  var light_target = rawMouse;
  if (hasSpringState && extraBuffer[138] > 0.5) {
    light_target = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
    var springPos = light_target;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 6.5;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Calculate light direction (from mouse to pixel, or paper casting shadow away from light)
  // Let's make mouse the light source. Shadows point AWAY from mouse.
  let aspect = u.config.z / u.config.w;
  let dist_vec = (uv - light_target) * vec2<f32>(aspect, 1.0);
  let dist_to_light = length(dist_vec);
  let light_dir = select(vec2<f32>(0.0, 1.0), dist_vec / max(dist_to_light, 0.0001), dist_to_light > 0.0001);

  // Sample base color
  let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(base_color);

  // Quantize luma for "paper layers"
  let quantized_luma = floor(luma * num_layers) / num_layers;

  // Clicks punch expanding raised rings through the paper stack.
  var clickEmboss = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    let safeAge = max(age, 0.0);
    let live = step(0.0, age) * (1.0 - step(1.8, age));
    let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
    let ring = 1.0 - smoothstep(0.012, 0.05, abs(rd - safeAge * 0.30));
    clickEmboss = max(clickEmboss, ring * exp(-safeAge * 1.4) * live);
  }
  let raisedLuma = clamp(quantized_luma + clickEmboss * (0.08 + separation * 0.12), 0.0, 1.0);

  // Calculate shadow
  // We sample "upstream" (towards light) to see if there is a higher layer blocking light
  // Shadow offset depends on how "high" the blocking layer is.
  // Simplified: Check a fixed distance towards the light.

  var shadow = 0.0;
  let shadow_samples = 4;

  for (var i = 1; i <= shadow_samples; i++) {
    let t = f32(i) / f32(shadow_samples);
    let sample_offset = -light_dir * shadow_dist * t; // Look towards light
    let sample_uv = uv + sample_offset;

    // Boundary check
    if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
      continue;
    }

    let sample_col = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;
    let sample_luma = getLuma(sample_col);
    let sample_quant = floor(sample_luma * num_layers) / num_layers;

    // If the sample is "higher" (brighter) than current pixel, it casts a shadow
    // We assume brighter = higher layer
    if (sample_quant > quantized_luma + separation) {
      shadow += (1.0 - t) * (1.0 - softness);
    }
  }

  shadow = clamp(shadow + clickEmboss * (1.0 - softness) * 0.18, 0.0, 0.8);

  // Re-construct color based on quantized luma (posterized look)
  // To keep color, we normalize base color by luma and multiply by quantized luma
  let norm_color = base_color / (luma + 0.001);
  let layerBin = (u32(floor(raisedLuma * num_layers)) % 8u) + 1u;
  let layerVoice = plasmaBuffer[layerBin].x;
  let paper_color = norm_color * raisedLuma * (1.0 + layerVoice * 0.12);

  // Apply shadow
  var final_color = paper_color * (1.0 - shadow);
  final_color += vec3<f32>(1.0, 0.72, 0.38) * clickEmboss * (0.08 + treble * 0.06);
  let peak = max(max(final_color.r, final_color.g), final_color.b);
  final_color = max(final_color, vec3<f32>(0.0)) * min(1.0, 1.6 / max(peak, 0.001));

  // Layer-aware alpha: shadowed valleys recede, lit layers stay opaque
  let alpha = clamp(raisedLuma * (1.0 - shadow * 0.5) + clickEmboss * 0.15 + 0.2, 0.0, 1.0);
  let finalOut = vec4<f32>(final_color, alpha);
  textureStore(writeTexture, coord, finalOut);
  textureStore(dataTextureA, coord, finalOut);

  // Honest paper relief: brighter/raised layers and click rings sit forward.
  let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
  let depthOut = clamp(depth - raisedLuma * 0.04 - clickEmboss * 0.025, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
