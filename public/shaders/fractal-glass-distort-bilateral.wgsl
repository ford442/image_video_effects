// ═══════════════════════════════════════════════════════════════════
//  fractal-glass-distort-bilateral — Recursive Glass & Bilateral Filter
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            fractal-glass-distortion, bilateral-filter, semantic-alpha, ACES
//  Complexity: Very High
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RotationSpeed, y=Scale, z=RefractStrength, w=BilateralMix
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, mouseDown);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 42.0;
    let damping = 12.96; // 2 * sqrt(42)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Exact parameter contracts
  let rot_speed = u.zoom_params.x * 3.14159265;
  let scale_base = mix(0.9, 1.3, u.zoom_params.y);
  let refract_str = mix(0.01, 0.07, u.zoom_params.z) * (1.0 + bass * 0.3);
  let bilateralMix = u.zoom_params.w;

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouse_p = (mouse - 0.5) * vec2<f32>(aspect, 1.0);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleWarp = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleWarp += rDir * wave * 0.04;
    }
  }

  // Fractal glass distortion
  var total_disp = vec2<f32>(0.0);
  var curr_p = p + rippleWarp;
  for (var i = 0; i < 4; i = i + 1) {
    let rel_p = curr_p - mouse_p;
    let angle = rot_speed * (f32(i) + 1.0) * 0.3 + held * 0.2;
    let rotated = rotate(rel_p, angle);
    let sine_warp = vec2<f32>(
      sin(rotated.y * 10.0 + time * (1.0 + mids * 0.5)),
      cos(rotated.x * 10.0 + time * (1.0 + treble * 0.5))
    );
    total_disp += sine_warp * refract_str / (f32(i) + 1.0);
    curr_p = rotated * scale_base + mouse_p;
  }

  let final_p = p + total_disp;
  let distortedUV = clamp(vec2<f32>(final_p.x / aspect, final_p.y) + 0.5, vec2<f32>(0.001), vec2<f32>(0.999));

  let distortedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

  // Bilateral edge-preserving filtering
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseFactor = exp(-mouseDist * mouseDist * 8.0);
  let spatialSigmaBase = mix(0.1, 1.0, bilateralMix);
  let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);
  let colorSigma = 0.3;

  let finalSigma = max(spatialSigma, 0.02);
  let radius = min(i32(ceil(finalSigma * 2.5)), 4);

  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;

  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighborUV = clamp(distortedUV + offset, vec2<f32>(0.001), vec2<f32>(0.999));
      let neighbor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0).rgb;

      let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
      let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
      let colorDist = length(neighbor - distortedColor.rgb);
      let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));

      let weight = spatialWeight * rangeWeight;
      accumColor += neighbor * weight;
      accumWeight += weight;
    }
  }

  var filtered = distortedColor.rgb;
  if (accumWeight > 0.001) {
    filtered = mix(distortedColor.rgb, accumColor / accumWeight, bilateralMix);
  }

  // Chromatic channel split on edge
  let aberration = 0.03 * bilateralMix * (1.0 + treble * 0.4);
  let r_uv = clamp(distortedUV + vec2<f32>(aberration, 0.0), vec2<f32>(0.001), vec2<f32>(0.999));
  let b_uv = clamp(distortedUV - vec2<f32>(aberration, 0.0), vec2<f32>(0.001), vec2<f32>(0.999));
  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = filtered.g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prevC, 0.07);

  let finalRGB = aces(color);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(0.4 + length(total_disp) * 8.0 + held * 0.15, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
