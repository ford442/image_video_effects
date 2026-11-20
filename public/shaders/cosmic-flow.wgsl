// ═══════════════════════════════════════════════════════════════════
//  Cosmic Flow Pro — braided magnetohydrodynamic nebula currents
//  Features: depth-aware, mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-20
//  Ideas: dust lanes with 1/λ reddening (Beer–Lambert, §12.2F); point-spread stars with Airy core + diffraction spikes (§12.2F)
//  A packing: HDR pre-tonemap RGB + semantic alpha (A owns the gas/source history, C is the exact previous A copy; the star layer is composited after the history blend and is NOT stored in A)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let cell = floor(p);
  let f = fract(p);
  let w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(
    mix(hash21(cell), hash21(cell + vec2<f32>(1.0, 0.0)), w.x),
    mix(hash21(cell + vec2<f32>(0.0, 1.0)), hash21(cell + vec2<f32>(1.0, 1.0)), w.x),
    w.y
  );
}

fn fbm(p0: vec2<f32>) -> f32 {
  var p = p0;
  var sum = 0.0;
  var amplitude = 0.52;
  let spin = mat2x2<f32>(0.87758, -0.47943, 0.47943, 0.87758);
  for (var octave = 0; octave < 5; octave += 1) {
    sum += amplitude * valueNoise(p);
    p = spin * p * 2.03 + vec2<f32>(17.1, 9.2);
    amplitude *= 0.5;
  }
  return sum;
}

fn curlField(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.018;
  let drift = vec2<f32>(t * 0.13, -t * 0.09);
  let dx = fbm(p + drift + vec2<f32>(e, 0.0)) - fbm(p + drift - vec2<f32>(e, 0.0));
  let dy = fbm(p + drift + vec2<f32>(0.0, e)) - fbm(p + drift - vec2<f32>(0.0, e));
  return vec2<f32>(dy, -dx) / (2.0 * e);
}

// §12.3 F1 Airy disc (2·J1(x)/x)², Taylor J1 — only valid to the first zero
// (x = 3.8317); the argument is clamped there and faded out so it never blows up.
fn airyCore(x: f32) -> f32 {
  let xs = clamp(abs(x), 1e-4, 3.83);
  let j1 = xs * (0.5 - xs * xs * (0.0625 - xs * xs * (0.0026042 - xs * xs * 0.0000543)));
  let v = 2.0 * j1 / xs;
  return v * v * (1.0 - smoothstep(2.6, 3.83, abs(x)));
}

fn cosinePalette(t: f32, shift: f32) -> vec3<f32> {
  let phase = vec3<f32>(0.03, 0.19, 0.38) + shift;
  return vec3<f32>(0.48, 0.42, 0.56)
    + vec3<f32>(0.46, 0.48, 0.42) * cos(TAU * (vec3<f32>(0.82, 0.91, 1.03) * t + phase));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn clampPixel(pixel: vec2<i32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let centered = (uv - 0.5) * aspectVec;
  let time = u.config.x;

  // Saved-preset contract: speed, scale, intensity, color_shift.
  let speed = mix(0.08, 0.72, u.zoom_params.x);
  let scale = mix(1.6, 6.8, u.zoom_params.y);
  let intensity = u.zoom_params.z;
  let colorShift = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let audioEnergy = dot(vec3<f32>(bass, mids, treble), vec3<f32>(0.45, 0.35, 0.20));

  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec;
  let mouseRadius = length(mouseDelta);
  let mouseDir = mouseDelta / max(mouseRadius, 0.001);
  let mouseTangent = vec2<f32>(-mouseDir.y, mouseDir.x);
  let held = select(0.35, 1.0, u.zoom_config.w > 0.5);
  let lens = exp(-mouseRadius * mouseRadius * 9.0) * held;

  var clickWave = 0.0;
  var clickCurl = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri += 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let delta = (uv - ripple.xy) * aspectVec;
      let radius = length(delta);
      let front = smoothstep(0.035, 0.0, abs(radius - age * (0.24 + speed * 0.16))) * exp(-age * 0.9);
      let direction = delta / max(radius, 0.001);
      clickWave += front;
      clickCurl += vec2<f32>(-direction.y, direction.x) * front * select(-1.0, 1.0, (ri % 2u) == 0u);
    }
  }

  let flowTime = time * speed * (1.0 + bass * 0.28);
  var p = centered * scale;
  p += mouseTangent * lens * (0.5 + u.zoom_params.y * 0.8);
  p += clickCurl * 0.55;

  let q = vec2<f32>(
    fbm(p + vec2<f32>(flowTime * 0.9, -flowTime * 0.25)),
    fbm(p + vec2<f32>(5.2 - flowTime * 0.35, 1.3 + flowTime * 0.7))
  );
  let r = vec2<f32>(
    fbm(p + q * (2.5 + bass) + vec2<f32>(1.7, 9.2) + flowTime * 0.45),
    fbm(p + q.yx * (3.0 + mids) + vec2<f32>(8.3, 2.8) - flowTime * 0.38)
  );
  let curl = curlField(p * 0.72 + r * 2.0, flowTime);
  let field = fbm(p + r * 3.8 + curl * 0.32);

  // Phase-related ridges read as braided plasma rather than undifferentiated FBM.
  let phase = dot(p, normalize(vec2<f32>(0.73, 0.41))) + (q.x - q.y) * 5.0;
  let braidA = pow(abs(sin(phase * 1.7 - flowTime * 3.1)), 9.0);
  let braidB = pow(abs(sin(phase * 2.35 + r.x * 5.0 + flowTime * 2.2)), 13.0);
  let filament = (braidA * 0.7 + braidB * 0.45) * smoothstep(0.28, 0.82, field);
  let knots = pow(max(0.0, 1.0 - abs(q.x - r.y) * 5.5), 7.0) * smoothstep(0.48, 0.9, field);
  let density = clamp(field * field * 0.75 + filament + knots * 0.65 + clickWave * 0.5, 0.0, 2.5);

  // ── Idea 1: dust lanes with reddening (Beer–Lambert, §12.2F) ──────────────
  // Real nebulae absorb as well as emit: dark dust threads run between the
  // bright braids and redden whatever shines through them. The lane is the
  // quadrature of braidA's phase (so it tracks the braids), the optical depth
  // gates on the gas field, and the transmission is exp(−τ·k(λ)) with
  // k ∝ 1/λ at 650/550/450 nm → blue is absorbed most.
  let laneWave = pow(abs(cos(phase * 1.7 - flowTime * 3.1)), 7.0);
  let dustTau = 0.95 * laneWave * smoothstep(0.30, 0.65, field);
  let dustT = exp(-dustTau * vec3<f32>(0.85, 1.0, 1.22));

  // Depth gradients bend the flow around existing scene geometry.
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let dL = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0).r;
  let dR = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(1, 0), dims), 0).r;
  let dD = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(0, -1), dims), 0).r;
  let dU = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(0, 1), dims), 0).r;
  let depthCurl = vec2<f32>(dU - dD, dL - dR);

  let sourceOffset = (curl * (0.003 + intensity * 0.009) + depthCurl * 0.025 + clickCurl * 0.004) / aspectVec;
  let red = textureSampleLevel(readTexture, u_sampler, clamp(uv + sourceOffset * (1.0 + treble * 0.35), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let green = textureSampleLevel(readTexture, u_sampler, clamp(uv + sourceOffset * 0.25, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).g;
  let blue = textureSampleLevel(readTexture, u_sampler, clamp(uv - sourceOffset * (0.8 + bass * 0.25), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let source = vec3<f32>(red, green, blue) * dustT;

  let palette = max(cosinePalette(field + q.x * 0.35 + audioEnergy * 0.12, colorShift), vec3<f32>(0.0));
  let core = vec3<f32>(1.25, 1.05, 0.78) * (filament * 0.65 + knots * 1.2 + clickWave * 0.45);
  // Only the gas behind a lane is cut: half-strength on the emission.
  let nebula = palette * density * (0.55 + intensity * 1.75) * (0.75 + audioEnergy * 0.5)
    * mix(vec3<f32>(1.0), dustT, 0.5);

  // Star placement, seed gate, twinkle shape and treble gate are HEAD's. HEAD
  // painted the whole cell flat (a ~10 px tile) before the history blend, so
  // stars were dragged into jagged smears.
  // Rescue: HEAD derived the twinkle rate AND phase from the same seed that
  // gates the star (seed > 0.96), i.e. from a 4 % wide range — every star
  // pulsed in unison and the sky was dark ~85 % of each 2 s cycle. Rate and
  // phase now come from an independent hash of the same cell.
  let starGrid = (centered + curl * 0.007) * (86.0 + scale * 5.0);
  let starCell = floor(starGrid);
  let starSeed = hash21(starCell);
  let starPhase = hash21(starCell + 29.9);
  let twinkle = pow(max(0.0, sin(time * (1.2 + starPhase * 2.0) + starPhase * TAU)), 18.0)
    * step(0.972 - treble * 0.012, starSeed) * (0.5 + filament);

  // ── Idea 2: point-spread stars with diffraction spikes (Airy, §12.2F) ─────
  // A star is a point source seen through a telescope: a jittered centre, an
  // Airy core and a 4-point cross whose spikes grow on the rarest seeds. The
  // profile is faded to zero at the cell edge so no tile seam shows.
  let starFl = fract(starGrid) - 0.5;
  let starJit = vec2<f32>(hash21(starCell + 17.3), hash21(starCell + 41.7)) - 0.5;
  let sd = starFl - starJit * 0.5;
  let bigStar = smoothstep(0.972, 1.0, starSeed);
  let spikeDecay = mix(3.2, 1.2, bigStar);
  let spikes = (exp(-abs(sd.y) * 46.0 - abs(sd.x) * spikeDecay)
              + exp(-abs(sd.x) * 46.0 - abs(sd.y) * spikeDecay)) * (0.35 + 0.9 * bigStar);
  let cellFade = (1.0 - smoothstep(0.30, 0.5, abs(starFl.x))) * (1.0 - smoothstep(0.30, 0.5, abs(starFl.y)));
  let star = twinkle * (airyCore(length(sd) * 14.0) * 2.4 + spikes) * cellFade;
  // Foreground point sources shine through the dust: dimmed and reddened by it.
  let starLight = vec3<f32>(0.7, 0.85, 1.2) * star * dustT;

  var live = source * (0.78 - density * 0.10) + nebula + core;

  // Exact C history, advected by the current curl. A remains authoritative.
  let historyOffset = vec2<i32>(round((curl * 1.4 + mouseTangent * lens * 1.2 + clickCurl) * (1.0 + speed * 2.0)));
  let prev = textureLoad(dataTextureC, clampPixel(pixel - historyOffset, dims), 0);
  let historyWeight = clamp(0.72 + (1.0 - speed) * 0.12, 0.0, 0.88);
  let temporal = mix(live, prev.rgb * 0.965, historyWeight * smoothstep(0.03, 0.38, density));
  live = max(temporal, live * 0.72);

  let alphaLive = clamp(density * 0.48 + filament * 0.35 + knots * 0.3 + star * 0.2 + (1.0 - dustT.y) * 0.2, 0.0, 1.0);
  let alpha = mix(alphaLive, prev.a * 0.95, historyWeight * 0.45);
  // A keeps the gas + source history; the star layer is added to the display only.
  textureStore(dataTextureA, pixel, vec4<f32>(min(live, vec3<f32>(8.0)), alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(live + starLight), alpha));

  let generatedDepth = clamp(density * 0.28 + knots * 0.25 + lens * 0.08, 0.0, 0.82);
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(depth * 0.82, generatedDepth), 0.0, 0.0, 0.0));
}
