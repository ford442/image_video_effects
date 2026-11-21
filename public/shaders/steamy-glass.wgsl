// ═══════════════════════════════════════════════════════════════════
//  Steamy Glass
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-21, 2026-11-21
//  Ideas: runoff rivulets; beaded wipe edge; low-pane linger; contact line
//  A packing: raw sim (steam, droplets, runoff, wipe memory). ACES on writeTexture only.
//  B and extraBuffer are intentionally unused; C reads are exact and bounded.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
    max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
    vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn sourceAt(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler,
    clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let texel = 1.0 / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let fogTarget = mix(0.08, 1.15, u.zoom_params.x);
  let returnRate = mix(0.002, 0.038, u.zoom_params.y);
  let wipeRadius = mix(0.035, 0.34, u.zoom_params.z);
  let blurRadius = mix(0.5, 5.5, u.zoom_params.w);

  let state = stateAt(pixel, dims);
  let left = stateAt(pixel + vec2<i32>(-1, 0), dims);
  let right = stateAt(pixel + vec2<i32>(1, 0), dims);
  let top = stateAt(pixel + vec2<i32>(0, -1), dims);
  let bottom = stateAt(pixel + vec2<i32>(0, 1), dims);
  let average = (left + right + top + bottom) * 0.25;
  var steam = mix(state.r, average.r, 0.045);
  // ── Idea 1: low-pane linger ────────────────────────────────────────
  // The lower glass stays wet after the top has started to clear.
  // Fade Speed stays the rate. y = 0 is the top of the pane.
  let lowPane = smoothstep(0.2, 1.0, uv.y);
  steam += (fogTarget - steam) * returnRate * (1.0 + audio.y * 0.35) * (0.55 + 0.9 * lowPane);
  var droplets = mix(state.g, average.g, 0.025);
  droplets += max(steam - 0.46, 0.0) * (0.004 + audio.z * 0.003);
  // Idea 1 — runoff rivulets. Drops grow at sparse, fixed nucleation sites until heavy, then
  // let go: the whole droplet mass becomes a bead in `runoff` that runs down one texel per
  // frame (it reads the texel above), picks up the droplets on its path and wipes a clear
  // track through the steam. Tuned on a CPU port: onset ~10 s at default fog, a few % of
  // the pane tracked at max fog, no drips in light fog.
  let site = hash21(vec2<f32>(pixel) + vec2<f32>(0.0, 3.0)) > 0.9965;
  let release = select(0.0, droplets, site && droplets > 0.28);
  var runoff = max(top.b * 0.975, state.b * 0.90) + release;
  let pickup = droplets * min(runoff, 1.0) * 0.25;
  droplets = max(droplets - pickup - release, 0.0);
  runoff += pickup * 0.5;
  let track = clamp(runoff * 2.0, 0.0, 0.85);
  steam *= 1.0 - track;
  droplets *= 1.0 - track * 0.8;
  var wipeMemory = state.a * 0.982;

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDistance = length(p - mouseP);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let wipe = (1.0 - smoothstep(wipeRadius * 0.45, wipeRadius,
    mouseDistance)) * held;
  steam *= 1.0 - wipe * 0.82;
  droplets *= 1.0 - wipe * 0.7;
  wipeMemory = max(wipeMemory, wipe);
  // Idea 2 — beaded wipe edge. A wipe pushes condensate aside, so droplets pile up in beads
  // along the rim of the wiped patch (and can later drip from it).
  let wipeRim = wipe * (1.0 - wipe) * 4.0;
  let bead = step(0.55, hash21(floor(vec2<f32>(pixel) / 3.0)));
  droplets += wipeRim * 0.03 * (0.4 + bead);

  var clickClear = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 2.8) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = length(q);
      let ring = exp(-abs(d - age * 0.31) * 34.0 - age * 0.85);
      clickClear += ring;
    }
  }
  steam *= 1.0 - clamp(clickClear * 0.28, 0.0, 0.72);
  droplets += clickClear * 0.014;
  runoff = clamp(runoff * 0.992 + audio.x * 0.0015, 0.0, 1.0);
  steam = clamp(steam, 0.0, 1.25);
  droplets = clamp(droplets * 0.995, 0.0, 1.0);
  textureStore(dataTextureA, pixel,
    vec4<f32>(steam, droplets, runoff, wipeMemory));

  let gradient = vec2<f32>(right.g - left.g, bottom.g - top.g)
    + vec2<f32>(right.b - left.b, bottom.b - top.b) * 0.5;
  let refractedUV = clamp(uv + gradient * (0.018 + droplets * 0.024),
    vec2<f32>(0.0), vec2<f32>(1.0));
  var blurred = vec4<f32>(0.0);
  var weight = 0.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let delta = vec2<f32>(f32(x), f32(y));
      let w = select(0.65, 1.0, x == 0 && y == 0);
      blurred += sourceAt(refractedUV + delta * texel * blurRadius) * w;
      weight += w;
    }
  }
  blurred /= max(weight, 0.001);
  let clearSource = sourceAt(refractedUV);
  let opticalDepth = steam * (1.2 + droplets * 0.8);
  let transmittance = exp(-opticalDepth);
  let fogColor = vec3<f32>(0.72, 0.84, 0.92) *
    (0.78 + audio.y * 0.12) + vec3<f32>(0.12, 0.05, 0.18) * audio.x;
  var rgb = mix(blurred.rgb, fogColor, 1.0 - transmittance);
  rgb = mix(rgb, clearSource.rgb, clamp(wipeMemory * 0.82, 0.0, 0.9));
  // ── Idea 2: contact line ───────────────────────────────────────────
  // The droplet gradient already refracts. Where it is steep and the
  // drop is not a solid bead, the edge of the drop darkens.
  let contact = smoothstep(0.004, 0.045, length(gradient)) * smoothstep(0.55, 0.08, droplets);
  rgb *= 1.0 - contact * 0.32;
  let glint = pow(clamp(droplets, 0.0, 1.0), 1.6) *
    (0.35 + audio.z * 0.5);
  rgb += vec3<f32>(0.68, 0.9, 1.0) * glint * 0.25;
  rgb += vec3<f32>(0.8, 0.95, 1.0) * smoothstep(0.05, 0.3, runoff) * 0.3;
  let alpha = clamp(clearSource.a * transmittance +
    (1.0 - transmittance) * 0.82 + droplets * 0.08, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(aces(rgb), alpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    refractedUV, 0.0).r;
  textureStore(writeDepthTexture, pixel,
    vec4<f32>(clamp(mix(depth, 0.9, (1.0 - transmittance) * 0.22), 0.0, 1.0), 0.0, 0.0, 0.0));
}
