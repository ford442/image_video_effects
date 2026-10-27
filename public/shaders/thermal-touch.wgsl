// ═══════════════════════════════════════════════════════════════════
//  Thermal Touch
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-27
//  Ideas: stored-field conduction (§12.2D 9-point); inverse-square touch and isotherms (§12.2F)
//  A packing: raw heat in A.r (C.r read back). ACES on display only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=HeatIntensity, y=Radius, z=AmbientTemp, w=CoolingRate

// ═══ CHUNK: aces_tonemap (standard) ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: blackbody_radiation ═══
fn blackbodyColor(t: f32) -> vec3<f32> {
  let v = clamp(t, 0.0, 1.0);
  let s1 = smoothstep(0.00, 0.15, v);
  let s2 = smoothstep(0.15, 0.30, v);
  let s3 = smoothstep(0.30, 0.50, v);
  let s4 = smoothstep(0.50, 0.70, v);
  let s5 = smoothstep(0.70, 0.85, v);
  let s6 = smoothstep(0.85, 1.00, v);
  var c = mix(vec3(0.0, 0.0, 0.0), vec3(0.1, 0.0, 0.15), s1);
  c = mix(c, vec3(0.4, 0.0, 0.0), s2);
  c = mix(c, vec3(0.8, 0.1, 0.0), s3);
  c = mix(c, vec3(1.0, 0.4, 0.0), s4);
  c = mix(c, vec3(1.0, 0.8, 0.1), s5);
  c = mix(c, vec3(1.0, 1.0, 0.9), s6);
  return c;
}

// ═══ CHUNK: local_glow ═══
fn localGlow(heat: f32) -> vec3<f32> {
  let h1 = blackbodyColor(clamp(heat + 0.05, 0.0, 1.0));
  let h2 = blackbodyColor(clamp(heat + 0.15, 0.0, 1.0));
  let h3 = blackbodyColor(clamp(heat + 0.25, 0.0, 1.0));
  return (h1 * 0.2 + h2 * 0.12 + h3 * 0.06) * heat * heat;
}

fn heatAt(c: vec2<i32>, maxC: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, clamp(c, vec2<i32>(0), maxC), 0).r;
}

// ── Idea: 9-point laplacian on stored heat (§12.2D).
fn heatLap(c: vec2<i32>, maxC: vec2<i32>) -> f32 {
  var s = 0.0;
  s = s + 0.20 * (heatAt(c + vec2<i32>(1, 0), maxC) + heatAt(c + vec2<i32>(-1, 0), maxC)
                + heatAt(c + vec2<i32>(0, 1), maxC) + heatAt(c + vec2<i32>(0, -1), maxC));
  s = s + 0.05 * (heatAt(c + vec2<i32>(1, 1), maxC) + heatAt(c + vec2<i32>(-1, 1), maxC)
                + heatAt(c + vec2<i32>(1, -1), maxC) + heatAt(c + vec2<i32>(-1, -1), maxC));
  return s - heatAt(c, maxC);
}

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2(123.34, 456.21));
  return fract(dot(q, vec2(12.9898, 78.233)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let time = u.config.x;
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let maxC = vec2<i32>(resolution) - vec2<i32>(1);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let clickBoost = select(1.0, 1.8, mouseDown);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let heatIntensity = mix(0.1, 2.5, u.zoom_params.x) * (1.0 + bass * 0.4);
  let radius = mix(0.03, 0.5, u.zoom_params.y) * clickBoost;
  let ambientTemp = u.zoom_params.z;
  let coolingRate = u.zoom_params.w * 0.5 + 0.05;

  let aspect = resolution.x / max(resolution.y, 0.001);
  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);

  let pulse = sin(time * (2.0 + bass * 6.0)) * 0.5 + 0.5;
  // ── Idea: inverse-square touch (§12.2F). Radius is the core size r0.
  let r0 = max(radius * 0.42, 0.02);
  let touch = heatIntensity * (0.75 + pulse * 0.25) / ((dist * dist) / (r0 * r0) + 1.0);

  var clickHeat = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let livePkt = step(0.0, age) * (1.0 - step(1.6, age));
    let cd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
    let packet = livePkt * exp(-age * 1.35) * heatIntensity / ((cd * cd) / (r0 * r0) + 1.0);
    clickHeat = max(clickHeat, packet);
  }

  let prevHeat = heatAt(coord, maxC);
  let spreadK = mix(0.55, 1.15, depth);
  let cooled = clamp(prevHeat + heatLap(coord, maxC) * spreadK, 0.0, 1.5) * exp(-coolingRate * 0.12);

  let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(texColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let baseHeat = luma * 0.3;

  var heat = max(cooled, baseHeat);
  heat = max(heat, touch);
  heat = max(heat, clickHeat * 0.85);
  heat = mix(heat, ambientTemp, 0.3 * step(0.001, ambientTemp));
  heat = heat + bass * 0.05 * (1.0 - smoothstep(0.0, 0.5, dist));
  heat = clamp(heat, 0.0, 1.0);

  let shimmer = hash21(uv * 200.0 + time * (2.0 + mids * 10.0)) * 0.04 * (1.0 + mids * 2.0);
  let displayHeat = clamp(heat + shimmer, 0.0, 1.0);
  // ── Idea: isotherms — a few contour lines on the blackbody plate.
  let band = abs(fract(displayHeat * 5.0) - 0.5);
  let iso = (1.0 - smoothstep(0.015, 0.055, band)) * smoothstep(0.08, 0.22, displayHeat);
  let plate = blackbodyColor(displayHeat) + localGlow(displayHeat) + vec3<f32>(0.95, 0.97, 1.0) * iso * 0.22;
  let tonemapped = aces_tonemap(max(plate, vec3<f32>(0.0)));

  let alpha = clamp(heat * 0.75 + iso * 0.2 + touch * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(tonemapped, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(heat, 0.0, 0.0, alpha));
}
