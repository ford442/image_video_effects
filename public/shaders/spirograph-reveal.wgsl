// ═══════════════════════════════════════════════════════════════════
//  Spirograph Reveal
//  Category: artistic
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: pen-head trace; ink pooling at crossings; ballpoint pressure
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let aspect = resolution.x / resolution.y;
  let center = mouse;
  let p = (uv - center) * vec2<f32>(aspect, 1.0);
  let r = length(p);
  let a = atan2(p.y, p.x);

  // Gear parameters modulated by mouse and params
  let outerTeeth = 3.0 + floor(u.zoom_params.x * 12.0);
  let innerTeeth = 1.0 + floor(u.zoom_params.y * 8.0);
  let speed = u.zoom_params.z * 2.0 * (1.0 + bass * 0.3);
  let thickness = 0.02 + u.zoom_params.w * 0.08;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(time - event.z, 0.0);
    if (age > 2.5) { continue; }
    clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 64.0);
  }

  // Depth creates 3D spirograph depth layers
  let depthLayers = 1.0 + depth * 2.0;

  var totalDensity = 0.0;
  var totalBloom = 0.0;
  var sumDensity = 0.0;
  var maxDensity = 0.0;

  // Multiple rotating gears with epicycloid/hypocycloid math
  for (var gear: u32 = 0u; gear < 3u; gear = gear + 1u) {
    let g = f32(gear);
    let gearRatio = (outerTeeth + g) / (innerTeeth + g * 0.5);
    let gearSpeed = speed * (1.0 + g * 0.3) * (1.0 + bass * 0.4 + mids * 0.2);
    let t = time * gearSpeed + g * 2.094;

    // Epicycloid when ratio > 0, hypocycloid variation
    let k = gearRatio;
    let theta = a * (k + 1.0) + t;
    let rho = r * 10.0 * depthLayers;

    // True spirograph: R * ( (1-k)*cos(t) + l*k*cos((1-k)/k*t) )
    let l = 0.5 + mouse.x * 0.5 + held * (mouse.y - 0.5) * 0.25;
    let spiro = sin(theta) + l * sin((1.0 - k) * theta / max(k, 0.1));
    let cusp = cos(rho - spiro * 3.0);

    let wave = sin(rho * 0.5 + spiro * 5.0 + cusp * 2.0);
    let val = abs(wave);
    // Idea 3: ballpoint pressure — stroke weight swells and thins round the
    // ring (integer angular harmonics, so no seam), skipping at the lightest.
    let press = 1.0 + 0.22 * sin(a * 3.0 + g * 2.1 + t * 0.5) + 0.1 * sin(a * 7.0 - g + t * 0.9);
    let lineField = smoothstep(0.0, thickness * (1.0 + g * 0.3) * press, val);
    let density = (1.0 - lineField) * smoothstep(0.68, 0.76, press);
    sumDensity = sumDensity + density;
    maxDensity = max(maxDensity, density);

    // Specular highlight at cusps
    let cuspSharp = pow(1.0 - smoothstep(0.0, 0.15, val), 3.0);
    totalBloom = totalBloom + cuspSharp * (0.5 + depth * 0.5);
    totalDensity = totalDensity + density * (0.6 - g * 0.15);
  }

  totalDensity = clamp(totalDensity, 0.0, 1.0);

  // Idea 1: pen-head trace — a pen orbits the centre drawing the figure; the
  // lines it has just passed glow (angular trail behind a bright head).
  let penAngle = time * (0.35 + u.zoom_params.z * 1.8);
  let behind = fract((penAngle - a) / 6.2831853);
  let penTrail = exp(-behind * 5.0) * (1.0 - smoothstep(0.9, 1.0, behind));
  let penHead = exp(-behind * 40.0) * (1.0 - smoothstep(0.0, 1.0, abs(r - 0.35 - 0.1 * sin(time * 0.7)) * 6.0));
  let pen = clamp(penTrail * 0.6 + penHead, 0.0, 1.0);
  totalBloom = clamp(totalBloom * (1.0 + pen * 0.8), 0.0, 1.0);

  // Idea 2: ink pooling at crossings — where gear layers overlap, ink pools.
  let pool = clamp(sumDensity - maxDensity, 0.0, 1.0);

  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Metallic ink aesthetic
  let inkColor = vec3<f32>(0.85, 0.82, 0.78) * (0.4 + 0.6 * gray);
  let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + a * outerTeeth + time * (0.5 + treble));
  let specColor = mix(vec3<f32>(1.0, 0.95, 0.85), spectral, 0.45 + treble * 0.35) * totalBloom * 2.0;
  let gradientFill = mix(
    vec3<f32>(0.2, 0.05, 0.4),
    vec3<f32>(0.05, 0.3, 0.5),
    fract(r * 2.0 + time * 0.1)
  );

  // Combine metallic ink with gradient fill along curve length
  var outColor = mix(inkColor, gradientFill, totalDensity * 0.4);
  let pooledInk = gradientFill * 0.45 + vec3<f32>(0.04, 0.0, 0.10);
  outColor = mix(outColor, pooledInk, pool * 0.45);
  outColor = outColor + specColor;
  outColor = outColor + vec3<f32>(1.0, 0.93, 0.8) * totalDensity * pen * 0.3;

  // Depth fade
  let fade = smoothstep(1.2, 0.2, r);
  let finalMask = totalDensity * fade;

  // Reveal image through spirograph mask (pooled crossings reveal a little more)
  outColor = mix(outColor, color.rgb, clamp(finalMask * 0.5 + pool * fade * 0.15, 0.0, 1.0));

  // HDR bloom at cusps added on top
  outColor = outColor + specColor * 0.5 + spectral * clickFront * 0.28;

  // Alpha: curve density × depth_occlusion
  let depthOcclusion = 1.0 - depth * 0.5;
  let alpha = clamp(totalDensity * depthOcclusion * fade + totalBloom * 0.3, 0.0, 1.0);

  let display = acesToneMap(max(outColor, vec3<f32>(0.0)));
  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(display, alpha));
}
