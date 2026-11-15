// ═══════════════════════════════════════════════════════════════════
//  Smoke Trails Thermal
//  Category: advanced-hybrid
//  Features: simulation, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: MacCormack on density and temperature (§12.2D); blackbody chromaticity (§12.2F)
//  A packing: raw sim (density, temperature, velocity). ACES on display only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + vec3<f32>(b))) / (x * (c * x + vec3<f32>(d)) + vec3<f32>(e)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(41.13, 289.7))) * 43758.5453); }

// Tanner Helland chromaticity. Radiance is applied by the caller so cool
// wisps stay visible and Thermal Intensity still owns the gain.
fn blackbodyChromaticity(kelvin: f32) -> vec3<f32> {
  let t = clamp(kelvin, 1000.0, 12000.0) * 0.01;
  let hot = t >= 66.0;
  let r = select(1.0, clamp(329.69873 * pow(max(t - 60.0, 0.05), -0.13320476) / 255.0, 0.0, 1.0), hot);
  let gLo = clamp((99.4708026 * log(max(t, 0.05)) - 161.119568) / 255.0, 0.0, 1.0);
  let gHi = clamp((288.12217 * pow(max(t - 60.0, 0.05), -0.07551485)) / 255.0, 0.0, 1.0);
  let g = select(gLo, gHi, hot);
  let bLo = clamp((138.51773 * log(max(t - 10.0, 0.05)) - 305.0448) / 255.0, 0.0, 1.0);
  let b = select(select(0.0, bLo, t > 19.0), 1.0, hot);
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dimsU = textureDimensions(dataTextureC);
  if (gid.x >= dimsU.x || gid.y >= dimsU.y) { return; }
  let p = vec2<i32>(gid.xy);
  let dims = vec2<i32>(dimsU);
  let uv = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / vec2<f32>(dimsU);
  let densityScale = 0.35 + u.zoom_params.x * 1.8;
  let turbulence = u.zoom_params.y;
  let riseSpeed = 0.15 + u.zoom_params.z * 1.4;
  let thermal = 0.4 + u.zoom_params.w * 2.4;
  let dt = clamp(1.0 / 60.0, 0.0, 0.033);
  let c = stateAt(p, dims);
  let travel = c.zw * vec2<f32>(dimsU) * dt * 0.8 - vec2<f32>(0.0, riseSpeed * (0.5 + c.y) * dt * f32(dimsU.y));
  let origin = p - vec2<i32>(round(travel));
  let fwd = stateAt(origin, dims);
  let n = stateAt(p + vec2<i32>(0, 1), dims);
  let s = stateAt(p + vec2<i32>(0, -1), dims);
  let e = stateAt(p + vec2<i32>(1, 0), dims);
  let w = stateAt(p + vec2<i32>(-1, 0), dims);
  let avg = (n + s + e + w) * 0.25;

  // ── Idea 1: MacCormack on density and temperature (§12.2D) ────────
  let backTravel = fwd.zw * vec2<f32>(dimsU) * dt * 0.8 - vec2<f32>(0.0, riseSpeed * (0.5 + fwd.y) * dt * f32(dimsU.y));
  let back = stateAt(origin + vec2<i32>(round(backTravel)), dims);
  let macD = fwd.x + 0.5 * (c.x - back.x);
  let macT = fwd.y + 0.5 * (c.y - back.y);
  let dLo = min(c.x, min(n.x, min(s.x, min(e.x, w.x))));
  let dHi = max(c.x, max(n.x, max(s.x, max(e.x, w.x))));
  let tLo = min(c.y, min(n.y, min(s.y, min(e.y, w.y))));
  let tHi = max(c.y, max(n.y, max(s.y, max(e.y, w.y))));
  var density = mix(clamp(macD, dLo, dHi), avg.x, 0.028 + 0.055 * turbulence);
  var temp = mix(clamp(macT, tLo, tHi), avg.y, 0.04);
  var velocity = mix(fwd.zw, avg.zw, 0.035);
  let curl = vec2<f32>(n.x - s.x, w.x - e.x) * (0.3 + 1.4 * turbulence);
  let jitter = vec2<f32>(hash21(vec2<f32>(p) + u.config.x) - 0.5, hash21(vec2<f32>(p.yx) - u.config.x) - 0.5);
  velocity += curl + jitter * 0.025 * turbulence + vec2<f32>(0.0, riseSpeed * temp * 0.035);

  let aspect = u.config.zw.x / max(u.config.zw.y, 1.0);
  let pointer = u.zoom_config.yz;
  let q = (uv - pointer) * vec2<f32>(aspect, 1.0);
  let source = exp(-dot(q, q) * 260.0) * step(0.5, u.zoom_config.w);
  let audio = plasmaBuffer[0].xyz;
  density += source * (0.025 + 0.07 * audio.x) * densityScale;
  temp += source * (0.045 + 0.09 * audio.z) * thermal;
  velocity += source * vec2<f32>((audio.y - audio.z) * 0.08, 0.08 + audio.x * 0.12);
  let clickCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < clickCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = u.config.x - event.z;
    let live = age >= 0.0 && age < 2.0;
    let cp = event.xy;
    let cq = (uv - cp) * vec2<f32>(aspect, 1.0);
    let radius = 0.025 + age * 0.18;
    let delta = (length(cq) - radius) * 58.0;
    let ring = exp(-delta * delta) * exp(-age * 1.8);
    let add = select(0.0, ring, live);
    density += add * (0.012 + audio.y * 0.04);
    temp += add * (0.018 + audio.z * 0.05);
    velocity += normalize(cq + vec2<f32>(0.0001)) * add * 0.09;
  }
  density = clamp(density * exp(-dt * (0.22 + 0.22 / densityScale)), 0.0, 2.0);
  temp = clamp(temp * exp(-dt * (0.7 + 0.3 / thermal)), 0.0, 2.0);
  velocity = clamp(velocity * exp(-dt * 1.6), vec2<f32>(-1.5), vec2<f32>(1.5));
  textureStore(dataTextureA, p, vec4<f32>(density, temp, velocity));

  let warped = clamp(uv + velocity / vec2<f32>(dimsU) * (2.0 + 7.0 * temp), vec2<f32>(0.0), vec2<f32>(1.0));
  let scene = textureSampleLevel(readTexture, u_sampler, warped, 0.0).rgb;
  // ── Idea 2: Planck chromaticity of the stored temperature (§12.2F)
  let kelvin = mix(900.0, 7500.0, smoothstep(0.02, 1.25, temp));
  let chroma = blackbodyChromaticity(kelvin);
  let radiance = mix(0.22, 3.4, smoothstep(0.04, 1.1, temp)) * (0.55 + thermal * 0.35);
  let transmittance = exp(-density * densityScale);
  let smoke = chroma * radiance * density + vec3<f32>(audio.x, audio.y * 0.45, audio.z) * density * 0.12;
  let alpha = clamp(1.0 - transmittance, 0.0, 1.0);
  textureStore(writeTexture, p, vec4<f32>(aces(max(scene * transmittance + smoke, vec3<f32>(0.0))), alpha));
  let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(sceneDepth, 1.0 - clamp(density * 0.45, 0.0, 1.0), alpha), 0.0, 1.0), 0.0, 0.0, 0.0));
}
