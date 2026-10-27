// ═══════════════════════════════════════════════════════════════════
//  Paper Cutout
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware, click-reactive
//  Complexity: Medium
//  Upgraded: 2026-10-27
//  Ideas: height-weighted shadows; lit cut edge; hand-cut jitter; deckle; paper tooth (§12.2C)
//  A packing: ACES display RGBA (same as writeTexture; C is not read)
// ═══════════════════════════════════════════════════════════════════
//  The photo is posterized by luma into stacked paper sheets (brighter = higher).
//  The pointer is the light; sheets cast shadows away from it. Clicks emboss rings.
//  Floor: removed the dead plasmaBuffer[layerBin] strata voice (plasmaBuffer[1..] reads 0,
//  so the old multiplier was always 1.0). HEAD's peak limiter is replaced by ACES at
//  exposure 0.72, which maps display 0.2 -> 0.20 and 0.5 -> 0.50 (upper layers compress).

#include "_prelude.wgsl"

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 3 — hand-cut layer jitter: a fixed per-sheet placement error of 1..2 px.
fn layerJitterPx(layerIndex: f32) -> vec2<f32> {
  let h = fract(sin(vec2<f32>(layerIndex * 127.1 + 11.3, layerIndex * 311.7 + 57.1)) * 43758.5453);
  let ang = h.x * 6.2831853;
  return vec2<f32>(cos(ang), sin(ang)) * (1.0 + h.y);
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

  // Idea 3 — hand-cut layer jitter. Find the sheet under this pixel, then read the photo
  // through that sheet's own placement offset, so each sheet sits slightly off-register.
  let texel = 1.0 / vec2<f32>(dims);
  let reg_luma = getLuma(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb);
  let reg_layer = floor(reg_luma * num_layers);
  let sheet_uv = clamp(uv - layerJitterPx(reg_layer) * texel, vec2<f32>(0.0), vec2<f32>(1.0));

  // Sample base color
  let base_color = textureSampleLevel(readTexture, u_sampler, sheet_uv, 0.0).rgb;
  let luma = getLuma(base_color);

  // Quantize luma for "paper layers"
  let layer_index = floor(luma * num_layers);
  let quantized_luma = layer_index / num_layers;

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
  // Idea 1 — height-weighted shadows: the smallest step that clears `separation` keeps
  // HEAD's weight 1.0; each extra layer of stack height darkens the cast shadow.
  let min_cast_layers = floor(separation * num_layers) + 1.0;

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
      let layers_higher = round((sample_quant - quantized_luma) * num_layers);
      let height_w = min(1.0 + 0.5 * max(layers_higher - min_cast_layers, 0.0), 2.2);
      shadow += (1.0 - t) * (1.0 - softness) * height_w;
    }
  }

  shadow = clamp(shadow + clickEmboss * (1.0 - softness) * 0.18, 0.0, 0.8);

  // Re-construct color based on quantized luma (posterized look)
  // To keep color, we normalize base color by luma and multiply by quantized luma
  let norm_color = base_color / (luma + 0.001);
  let paper_color = norm_color * raisedLuma;

  // Apply shadow
  var final_color = paper_color * (1.0 - shadow);

  // Idea 2 — lit cut edge. One pixel toward the light (in this sheet's frame): if the
  // neighbour is a lower sheet, this is the cut face turned to the light and shows the
  // paper's white core. One pixel away from the light: a lower neighbour means the far
  // cut face, which reads as a thin dark rim.
  let edge_step = light_dir * texel;
  let toward_uv = clamp(sheet_uv - edge_step, vec2<f32>(0.0), vec2<f32>(1.0));
  let away_uv = clamp(sheet_uv + edge_step, vec2<f32>(0.0), vec2<f32>(1.0));
  let toward_layer = floor(getLuma(textureSampleLevel(readTexture, u_sampler, toward_uv, 0.0).rgb) * num_layers);
  let away_layer = floor(getLuma(textureSampleLevel(readTexture, u_sampler, away_uv, 0.0).rgb) * num_layers);
  let lit_edge = step(toward_layer + 0.5, layer_index);
  let far_rim = step(away_layer + 0.5, layer_index);
  let cut_core = vec3<f32>(1.5, 1.46, 1.38);
  // ── Idea: deckle. The lit core is a torn paper edge, not a straight cut.
  let deckleN = fract(sin(reg_layer * 127.1 + floor((sheet_uv.x * aspect + sheet_uv.y) * 140.0) * 311.7) * 43758.5453);
  let torn = lit_edge * (0.42 + 0.58 * deckleN);
  final_color = mix(final_color, cut_core, torn * (0.55 - 0.3 * softness) * (1.0 - shadow));
  final_color *= 1.0 - far_rim * (0.4 - 0.2 * softness);
  // ── Idea: paper tooth (§12.2C). Fibre shows in the sheet, more inside the shadow.
  let tooth = fract(sin(dot(floor(uv * vec2<f32>(dims) * 0.5), vec2<f32>(127.1, 311.7))) * 43758.5453);
  let toothAmt = (0.045 + shadow * 0.09) * (1.0 - softness * 0.45);
  final_color = final_color * (1.0 - toothAmt * tooth);

  final_color += vec3<f32>(1.0, 0.72, 0.38) * clickEmboss * (0.08 + treble * 0.06);
  // ACES on display RGB; exposure 0.72 keeps the 0.2..0.5 midtones at HEAD's level.
  final_color = acesToneMap(clamp(final_color, vec3<f32>(0.0), vec3<f32>(2.0)) * 0.72);

  // Layer-aware alpha: shadowed valleys recede, lit layers stay opaque
  let alpha = clamp(raisedLuma * (1.0 - shadow * 0.5) + clickEmboss * 0.15 + 0.2, 0.0, 1.0);
  let finalOut = vec4<f32>(final_color, alpha);
  textureStore(writeTexture, coord, finalOut);
  textureStore(dataTextureA, coord, finalOut);

  // Honest paper relief: brighter/raised layers and click rings sit forward.
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(depth - raisedLuma * 0.04 - clickEmboss * 0.025, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
