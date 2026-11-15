// ═══════════════════════════════════════════════════════════════════
//  Rainbow Cloud v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, volumetric-cloud, mie-scattering, upgraded-rgba
//  Complexity: Very High
//  Chunks From: rainbow-cloud, volumetric-raymarch, aces-tonemap
//  Created: 2026-05-31
//  Upgraded: 2026-05-31, 2026-11-15
//  Ideas: Henyey-Greenstein forward lobe from a per-pixel view angle (§12.2F); Beer-Powder self-shadow from the slices between sample and sun (back-to-front march); corona irisation fringes around the sun
//  A packing: unchanged 4-field param pack (cloudDensity, iridescence, depthFactor, alpha) in A - nothing reads it back as C; ACES on writeTexture only
//  Rescue: HEAD's optical depth (threshold 0.35 vs a field that peaks near 0.4, gain 2.5 over 10 slices of 0.1) left the veil invisible at every slider position
//  Rescue: bass turbulence scaled the absolute cloud coordinate (drift included), so each beat re-randomised the field by an amount that grew with uptime; it now swells about the screen centre (identical at bass=0)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3(0.0), vec3(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

fn noise3d(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0 + i.z * 113.0;
  // Rescue: HEAD's corner offsets were (x:+57, y:+113, z:+1) while the cell index strides are
  // (x:1, y:57, z:113), so neighbouring cells never shared corner values - every lattice
  // boundary was a hard seam (hidden only because HEAD drew no visible cloud).
  return mix(
    mix(mix(hash12(vec2(n, n + 1.0)), hash12(vec2(n + 1.0, n + 2.0)), u.x),
        mix(hash12(vec2(n + 57.0, n + 58.0)), hash12(vec2(n + 58.0, n + 59.0)), u.x), u.y),
    mix(mix(hash12(vec2(n + 113.0, n + 114.0)), hash12(vec2(n + 114.0, n + 115.0)), u.x),
        mix(hash12(vec2(n + 170.0, n + 171.0)), hash12(vec2(n + 171.0, n + 172.0)), u.x), u.y), u.z
  );
}

fn fbm3d(p: vec3<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + noise3d(f) * a;
    f = f * 2.03 + vec3(1.7, 3.1, 5.3);
    a = a * 0.5;
  }
  return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }
  // Rescue: pixel-centre uv (HEAD sampled the corner of every texel)
  let uv = (vec2<f32>(gid.xy) + vec2(0.5)) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let cloudScale = mix(1.0, 6.0, u.zoom_params.x);
  let driftSpeed = mix(0.02, 0.3, u.zoom_params.y);
  // Density slider: HEAD's mix(0.15, 0.9, z) put the whole 0..0.25 range under the cloud threshold (no cloud at all).
  // Same endpoint (z=1 -> 0.9) and same default (z=0.5 -> 0.525), but the low end now rises out of the floor.
  let zD = u.zoom_params.z;
  let densityParam = 0.3 * (1.0 + zD + zD * zD);
  let iridescence = mix(0.1, 1.0, u.zoom_params.w);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.3, 1.0, depth);

  // Ray direction and origin for volumetric march
  let aspect = dims.x / dims.y;
  let ro = vec3(uv.x * aspect, uv.y, 0.0);
  let rd = vec3(0.0, 0.0, 1.0);
  let lightDir = normalize(vec3(0.3, 0.5, 1.0));

  // Bass drives turbulence
  let turbulence = 1.0 + bass * 0.6;
  let turbC = vec3(0.5 * aspect, 0.5, 0.5);

  // Mouse scatters cloud particles
  let mouseScatter = 1.0 - smoothstep(0.0, 0.5, length(uv - mouse));

  // ── Idea 1: Henyey-Greenstein forward lobe, per-pixel view angle (§12.2F) ──
  // HEAD's cosTheta = dot(rd, lightDir) used the CONSTANT orthographic rd, so its
  // "Mie phase" was one number for the whole frame. Sampling stays orthographic
  // (no parallax change); only the PHASE gets a pixel-dependent view direction
  // toward a sun sitting behind the veil at the upper right.
  let sunUV = vec2(0.74, 0.17);
  let viewP = normalize(vec3((uv - vec2(0.5)) * vec2(aspect, 1.0) * 0.9, 1.0));
  let sunP = normalize(vec3((sunUV - vec2(0.5)) * vec2(aspect, 1.0) * 0.9, 1.0));
  let cosSun = clamp(dot(viewP, sunP), -1.0, 1.0);
  let gHG = 0.58;
  let hg = (1.0 - gHG * gHG) / pow(max(1.0 + gHG * gHG - 2.0 * gHG * cosSun, 0.02), 1.5);
  let cosTheta = dot(rd, lightDir);
  let miePhase = (1.0 + cosTheta * cosTheta) * 0.5;
  let phase = miePhase * 0.45 + hg * 0.16;
  // ── Idea 3: corona irisation — angular distance to the sun drives hue fringes ──
  let sunAng = sqrt(max(2.0 * (1.0 - cosSun), 0.0));

  var scatteredLight = vec3(0.0);
  var totalDensity = 0.0;
  let steps = 10;
  let stepSize = 1.0 / f32(steps);

  // ── Idea 2: Beer-Powder self-shadow (back-to-front march) ──
  // The sun sits BEHIND the veil, so the light reaching a slice has crossed every
  // slice deeper than it. Marching deep->near makes that optical depth a free running
  // sum (no extra fbm taps). Result is identical to HEAD's front-to-back
  // compositing (src*T + sum), plus the sunlight term. Cores go dark, sun-facing edges
  // stay silver-lined; powder thins the faintest fringes.
  var radiance = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var tauBehind = 0.0;
  for (var k = 0; k < steps; k = k + 1) {
    let i = steps - 1 - k;
    let t = f32(i) * stepSize;
    let pos = ro + rd * t;
    let cloudUV = pos * cloudScale + vec3(time * driftSpeed, time * driftSpeed * 0.3, time * driftSpeed * 0.1);
    // Bass swells the field about the screen centre. HEAD scaled the ABSOLUTE coordinate, drift included,
    // so every beat re-randomised the cloud by an amount that grew with uptime; the pivot form is exact at bass=0.
    let turbPos = cloudUV + (turbulence - 1.0) * (pos - turbC) * cloudScale + mouseScatter * 0.4;
    let d = fbm3d(turbPos) * densityParam * depthFactor;

    // Cloud density with soft edges.
    // Rescue: HEAD used max(d-0.35,0)*2.5 on a field that peaks near 0.4, so the optical depth over the
    // whole 10-slice march was ~0.01. Same shape, re-centred on the field's real range.
    let density = max(d - 0.13, 0.0) * 12.0;

    let lightAtten = exp(-density * 3.0);
    let sunT = exp(-tauBehind * 0.9);                       // sunlight surviving the deeper slices
    let powder = 1.0 - exp(-density * 2.5);                 // thin fringes scatter less than they transmit
    let lit = (0.28 + 0.95 * sunT) * mix(0.55, 1.0, powder);

    // Iridescent cloud colors (nacreous / polar stratospheric). Hue slope re-scaled with the density gain (2.0 -> 0.6).
    // Corona: the rings are a PERIODIC function of angle-to-sun (a linear hue ramp x per-pixel veil reads as grain).
    // sin() drives hue, cos() the brightness, so each band is a coherent coloured ring; the veil only sets its strength.
    let veil = 1.0 - smoothstep(0.15, 2.4, density);       // fringes survive through moderately thin cloud
    let ringPh = sunAng * 24.0;
    let coronaEnv = exp(-sunAng * 1.2);                    // bands cluster round the sun and fade outward
    let corona = 0.5 * sin(ringPh) * veil * coronaEnv * iridescence;
    let coronaRing = 1.0 + 0.6 * veil * coronaEnv * cos(ringPh);
    let hue = density * 0.6 + t * 0.8 + time * 0.06 + mids * 0.2 + corona;
    let iridColor = 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.25, 0.5) + hue));

    // HDR god rays through cloud gaps
    let godRay = smoothstep(0.05, 0.25, density) * (1.0 - lightAtten) * phase;
    let lightColor = (vec3(1.0, 0.95, 0.85) * godRay * 0.35 + iridColor * density * iridescence * 2.4 * coronaRing) * lit;

    let absorb = clamp(density * stepSize, 0.0, 0.95);
    radiance = radiance * (1.0 - absorb) + lightColor * absorb;
    tauBehind = tauBehind + density * stepSize;
    totalDensity = totalDensity + density;
  }

  var color = radiance;

  // Atmospheric perspective
  let atmFog = vec3(0.15, 0.18, 0.25) * (1.0 - depthFactor);
  color = mix(color, atmFog, 0.15);

  // ACES tone mapping
  color = aces(max(color, vec3(0.0)) * 1.1);

  let cloudDensity = clamp(totalDensity * 0.15, 0.0, 1.0);
  let alpha = clamp(cloudDensity * iridescence * depthFactor, 0.03, 0.95);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4(cloudDensity, iridescence, depthFactor, alpha));
}
