// ═══════════════════════════════════════════════════════════════════
//  Spore Galaxy
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, oklab-mix,
//            blackbody-temp, volumetric-fog, ign-dither
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
//  Upgraded: 2026-07-22 (Visualist pass: feedback semantics fixed so
//            dataTextureA carries display color and dataTextureB carries
//            the arm/spore/dust masks, per-arm FFT band voices, and
//            mouse-down spore burst rings via ripples[])
//  Upgraded: 2026-10-19
//  Ideas: wavelength-dependent dust lane on the upstream arm edge (§12.2F Beer–Lambert,
//         reddening, τ ∝ Nebula); density-wave spore ignition just downstream of the
//         arm crest; golden-angle sporangium core (§12.2E golden-angle layout)
//  A packing: A = linear hue-preserved display colour (pre-ACES) + alpha, read back as
//             colour history via exact C; B = (armCore, spore, dust, burst) masks
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(43.2, 17.8)));
}

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
  let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
  let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
  let l_ = pow(max(l, 0.0), 1.0/3.0); let m_ = pow(max(m, 0.0), 1.0/3.0); let s_ = pow(max(s, 0.0), 1.0/3.0);
  return vec3<f32>(0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
                   1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
                   0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
  let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
  let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
  let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
  return vec3<f32>(4.0767416621*l-3.3077115913*m+0.2309699292*s,
                  -1.2684380046*l+2.6097574011*m-0.3413193965*s,
                  -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (t <= 66.0) { r = 1.0; }
  else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t <= 19.0) { b = 0.0; }
  else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  let s = min(1.0, max_lum / max(l, 1e-4));
  return c * s;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Idea 3: golden-angle sporangium core (§12.2E golden-angle layout) ──
// Seed i sits at θ = i·2.39996 + spin, r = c·√i. The nearest seed to q is found
// by testing the Fibonacci neighbours of n0 = (r/c)² (phyllotactic parastichies).
fn sporangium(q: vec2<f32>, spin: f32, c: f32, sharp: f32) -> f32 {
  let n0 = round(dot(q, q) / (c * c));
  var best = 1e3;
  var fib = array<f32, 9>(0.0, 1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 21.0, 34.0);
  for (var k = 0; k < 18; k = k + 1) {
    let sgn = select(-1.0, 1.0, (k & 1) == 0);
    let idx = n0 + sgn * fib[k >> 1];
    let ok = idx >= 1.0 && idx <= 260.0;
    let th = idx * 2.39996323 + spin;
    let sp = c * sqrt(max(idx, 0.0)) * vec2<f32>(cos(th), sin(th));
    let dd = length(q - sp);
    best = select(best, min(best, dd), ok);
  }
  return exp(-best * best * sharp);
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.5);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.5);
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  // Slider contract: x = arm count + core sharpness, y = swirl + rotation
  // speed + trail persistence, z = spore grid density + emission gate,
  // w = nebula dust amount + fog density.
  let arms = mix(2.0, 8.0, u.zoom_params.x);
  let armSharp = mix(0.35, 0.14, u.zoom_params.x);
  let swirl = mix(0.2, 3.0, u.zoom_params.y);
  let rotSpeed = mix(0.05, 0.30, u.zoom_params.y);
  let trailDecay = mix(0.86, 0.96, u.zoom_params.y);
  let density = mix(15.0, 120.0, u.zoom_params.z);
  let sporeGate = mix(0.85, 0.65, u.zoom_params.z);
  let nebula = mix(0.0, 1.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p - mouse * 0.15;

  let r = length(p);
  let a = atan2(p.y, p.x);
  let armAngle = a + r * swirl * (3.0 + bass * 3.0) - time * rotSpeed;
  let armPhase = fract(armAngle * arms / 6.28318);
  let armDist = abs(armPhase - 0.5) * 2.0;
  let armCore = smoothstep(armSharp, 0.0, armDist) * exp(-r * 2.5);

  // Per-arm voice: successive arms listen to bass / mids / treble in turn, so
  // different arms flare to different bands instead of all pulsing with the
  // global bass. (HEAD read plasmaBuffer[1..8], which the host never writes —
  // only plasmaBuffer[0].xyz carries audio — so the voices were silent.)
  let armCount = max(round(arms), 1.0);
  let armIdxF = clamp(floor(fract(armAngle / 6.28318) * armCount), 0.0, armCount - 1.0);
  let armIdx = u32(armIdxF);
  let bands = vec3<f32>(bass, mids, treble);
  let armBand = clamp(bands[armIdx % 3u] * 1.1, 0.0, 1.5);

  // Signed offset from the arm crest (−1..1 across one arm period); HEAD folded
  // it away with abs(). Positive = upstream (concave) side of the trailing arm.
  let armSigned = (armPhase - 0.5) * 2.0;
  // ── Idea 1: wavelength-dependent dust lane (§12.2F Beer–Lambert) ──
  // A density-wave arm compresses gas on its upstream edge: a dark lane that
  // absorbs the arm light, harder in blue than red (interstellar reddening).
  // τ rides the Nebula slider's existing "dust amount" role.
  let laneD = abs(armSigned - armSharp * 0.9);
  let laneMask = smoothstep(armSharp * 0.55, 0.0, laneD) * exp(-r * 1.4) * smoothstep(0.04, 0.18, r);
  let laneTau = laneMask * nebula * 2.4;
  let laneT = exp(-laneTau * vec3<f32>(0.55, 0.8, 1.25));
  // ── Idea 2: density-wave spore ignition ──
  // Spores are the young stars here: they flare just downstream of the crest,
  // where the wave has just swept through, and cool toward the blue blackbody.
  let ignite = smoothstep(armSharp * 1.8, 0.0, abs(armSigned + armSharp * 1.2)) * exp(-r * 1.2);

  let gridUV = uv * density + vec2<f32>(time * 0.02, -time * 0.015);
  let cell = floor(gridUV);
  let local = fract(gridUV) - 0.5;
  let rnd = hash22(cell);
  let sporeD = length(local - (rnd - 0.5) * 0.8);
  let spore = exp(-sporeD * sporeD * (50.0 + treble * 40.0)) * step(sporeGate, hash21(cell + vec2<f32>(13.3, 7.1)));
  // Idea 3: phyllotactic cap of seeds in the bulge, spinning with the arms.
  let capSeed = sporangium(p, -time * rotSpeed * 1.6, 0.021, 9000.0) * exp(-r * 5.5);

  let dust = hash21(floor(uv * 300.0 + time * 0.05)) * exp(-r * 1.8) * nebula;

  // Spore burst: every mouse-down launches a radial exp-decay emission
  // ring of spores outward from the cursor — a visible shockwave.
  var burst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let elapsed = time - rp.z;
    if (rp.z > 0.0 && elapsed > 0.0 && elapsed < 3.0) {
      // Click and pixel in the same centred, aspect-corrected frame (HEAD
      // compared 0..1 uv against a centred click, so rings sat off-cursor).
      let clickPos = (rp.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
      let cd = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) - clickPos);
      let frontR = elapsed * 0.65;
      let ring = exp(-abs(cd - frontR) * 16.0) * exp(-elapsed * 1.8);
      burst = burst + ring;
    }
  }

  // Dynamic temperature from audio-reactive blackbody
  let warmTemp = 2500.0 + bass * 3500.0;
  let coolTemp = 7000.0 + treble * 5000.0;
  let warmCol = blackbodyRGB(warmTemp);
  let coolCol = blackbodyRGB(coolTemp);

  // Palette-driven arm hues with OkLab mixing; the arm's own FFT band
  // offsets its palette phase so arms sing in different hues.
  let armHue = palette(armPhase + bass * 0.2 + armBand * 0.35,
    vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5),
    vec3<f32>(1.0,1.0,0.5), vec3<f32>(0.0,0.1,0.2));
  let armCol = mixOkLab(warmCol * vec3<f32>(1.2,0.9,0.6), armHue, 0.35);

  // HDR accumulation in linear space
  var color = vec3<f32>(0.01, 0.01, 0.03);
  // Idea 1: arm light passes through the upstream dust lane.
  color = color + armCol * armCore * (2.5 + bass * 1.5 + armBand * 1.2) * laneT;
  let sporeCol = mixOkLab(coolCol, vec3<f32>(0.35,0.95,0.65), 0.4);
  // Idea 2: spores downstream of the crest ignite, bluer and brighter.
  let igniteCol = mix(sporeCol, coolCol * vec3<f32>(0.8, 0.95, 1.3), ignite * 0.6);
  color = color + igniteCol * spore * (1.2 + mids * 0.8) * (1.0 + ignite * 2.2) * mix(vec3<f32>(1.0), laneT, 0.7);
  // Idea 3: sporangium cap seeds glow warm-to-spore as they leave the core.
  color = color + mixOkLab(warmCol, sporeCol, smoothstep(0.0, 0.3, r)) * capSeed * (1.1 + bass * 0.6);
  color = color + vec3<f32>(0.3,0.5,1.0) * dust * 0.8 * (1.0 + treble * 0.3);

  // Burst ring emits spore-colored light and briefly seeds extra spores
  // along the shockwave front.
  let burstCol = mixOkLab(coolCol, vec3<f32>(0.9,0.6,1.0), 0.5);
  color = color + burstCol * burst * (1.4 + treble * 0.8);
  color = color + mixOkLab(coolCol, vec3<f32>(0.35,0.95,0.65), 0.4) * burst * spore * 2.0;

  // Volumetric fog (Beer-Lambert depth falloff)
  let fogDensity = 0.7 + nebula * 1.5;
  let fog = exp(-r * fogDensity);
  color = color * fog + mixOkLab(vec3<f32>(0.005,0.008,0.02), warmCol * 0.15, 0.5) * (1.0 - fog);

  // Temporal feedback: dataTextureC now carries last frame's DISPLAY
  // COLOR (written to dataTextureA below), so this mix produces genuine
  // star-trail persistence instead of feeding masks back as color.
  let prev = textureLoad(dataTextureC, coord, 0);
  color = mix(color, prev.rgb * trailDecay, 0.05 + bass * 0.02);

  // Hue-preserve clamp → ACES → dither → premultiplied write
  color = hue_preserve_clamp(max(color, vec3<f32>(0.0)), 4.0);
  let feedbackColor = color;
  color = aces(color);
  let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // Bloom-weight alpha
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 3.0;
  let alpha = sat(0.08 + sat(armCore * 0.9 * (1.0 - laneMask * nebula * 0.5) + spore * 0.7 + capSeed * 0.6 + dust * 0.4 + burst * 0.6) * 0.92);
  let finalAlpha = max(alpha, bloomWeight * 0.6);
  let depth = sat(0.92 - armCore * 0.6 - spore * 0.25 - capSeed * 0.2 - burst * 0.15);

  let outRGB = pow(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(1.0/2.2));
  textureStore(writeTexture, coord, vec4<f32>(outRGB * finalAlpha, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  // A = display color (linear, hue-preserved) for next-frame feedback.
  textureStore(dataTextureA, coord, vec4<f32>(feedbackColor, finalAlpha));
  // B = per-channel masks for debug / downstream passes.
  // (Previously these masks lived in A and were read back AS color.)
  textureStore(dataTextureB, coord, vec4<f32>(armCore, spore, dust, burst));
}
