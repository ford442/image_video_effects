// ═══════════════════════════════════════════════════════════════════
//  Impasto Swirl
//  Category: interactive-mouse
//  Features: mouse-driven, upgraded-rgba
//  Upgraded: 2026-10-27
//  Ideas: knife ridge from stored thickness; lip bead at the brush edge
//  A packing: linear paint RGB + thickness in A.a. ACES on the display write only.
// ═══════════════════════════════════════════════════════════════════
//  The catalog body is a wet swirl: the pointer drags history around the
//  brush, paint thickens under the knife, and the stroke dries back to the
//  photo. The file on main had been replaced by an unrelated stipple; this
//  puts the oil-paint path back and adds the two ideas above.

#include "_prelude.wgsl"

fn canvasTexture(uv: vec2<f32>) -> f32 {
  let noise = fract(sin(dot(uv * 200.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  return 0.9 + 0.1 * noise;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadC(c: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  let hi = dims - vec2<i32>(1);
  return textureLoad(dataTextureC, clamp(c, vec2<i32>(0), hi), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(dims);
  let uv = vec2<f32>(coord) / resolution;
  let mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let brushSize = u.zoom_params.x * 0.1 + 0.01;
  let smudgeStrength = u.zoom_params.y;
  let drySpeed = u.zoom_params.z * 0.1 + 0.001;
  let paintLoad = u.zoom_params.w;

  let aspect = resolution.x / max(resolution.y, 1.0);
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  let brushMask = smoothstep(brushSize, brushSize * 0.5, dist);

  let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let historyFrame = loadC(coord, dims);

  let prev_thickness = historyFrame.a;
  var finalColor = currentFrame;
  var paint_thickness = prev_thickness;

  if (historyFrame.a == 0.0) {
    finalColor = currentFrame;
    paint_thickness = 0.5;
  } else {
    if (brushMask > 0.0) {
      let rotUV = clamp(uv + vec2<f32>(dVec.y, -dVec.x) * smudgeStrength * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
      let rotCoord = clamp(vec2<i32>(rotUV * resolution), vec2<i32>(0), dims - vec2<i32>(1));
      let mixedSample = loadC(rotCoord, dims);
      finalColor = vec4<f32>(mix(currentFrame.rgb, mixedSample.rgb, smudgeStrength * brushMask), currentFrame.a);
      let added_thickness = brushMask * paintLoad * 0.5;
      paint_thickness = min(1.0, paint_thickness + added_thickness);
    } else {
      finalColor = vec4<f32>(mix(historyFrame.rgb, currentFrame.rgb, drySpeed), currentFrame.a);
      paint_thickness = mix(paint_thickness, 0.7, drySpeed * 0.1);
    }
  }

  // ── Idea: lip bead. Paint piles where the knife is halfway on, halfway off.
  let lip = brushMask * (1.0 - brushMask) * 4.0;
  paint_thickness = min(1.0, paint_thickness + lip * paintLoad * 0.45);

  let canvas = canvasTexture(uv);
  finalColor = vec4<f32>(mix(finalColor.rgb, finalColor.rgb * (0.9 + 0.2 * canvas), 0.3), finalColor.a);

  var paint_alpha = mix(0.3, 0.95, paint_thickness * paint_thickness);
  let wet_factor = clamp(1.0 - drySpeed * 5.0, 0.0, 1.0);
  paint_alpha = mix(paint_alpha * 0.85, paint_alpha, wet_factor);
  paint_alpha = paint_alpha * mix(0.9, 1.0, canvas);
  let edge_thinning = smoothstep(0.0, 0.8, brushMask);
  let onLip = brushMask * (1.0 - step(0.8, brushMask));
  paint_alpha = paint_alpha * mix(1.0, mix(0.6, 1.0, edge_thinning), onLip);

  let thickness_saturation = mix(0.85, 1.15, paint_thickness);
  let thickness_value = mix(1.1, 0.9, paint_thickness);
  let luminance = dot(finalColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let chroma = finalColor.rgb - vec3<f32>(luminance);
  var rgb = (vec3<f32>(luminance) + chroma * thickness_saturation) * thickness_value;

  let specular = pow(max(canvas * paint_thickness - 0.3, 0.0), 4.0) * 0.3 * wet_factor;
  rgb = rgb + vec3<f32>(specular);

  // ── Idea: knife ridge. The slope of last frame's thickness shades the stroke.
  let tR = loadC(coord + vec2<i32>(1, 0), dims).a;
  let tL = loadC(coord + vec2<i32>(-1, 0), dims).a;
  let tD = loadC(coord + vec2<i32>(0, 1), dims).a;
  let tU = loadC(coord + vec2<i32>(0, -1), dims).a;
  let slope = clamp((tR - tL) * 0.55 + (tD - tU) * 0.4, -0.4, 0.4);
  rgb = rgb * (1.0 + slope * paint_thickness * 1.4);
  rgb = rgb + vec3<f32>(1.0, 0.96, 0.9) * max(slope, 0.0) * paint_thickness * 0.35;

  let stored = vec4<f32>(max(rgb, vec3<f32>(0.0)), paint_thickness);
  textureStore(dataTextureA, coord, stored);
  textureStore(writeTexture, coord, vec4<f32>(aces(stored.rgb), clamp(paint_alpha, 0.0, 1.0)));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(d - paint_thickness * 0.06, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
