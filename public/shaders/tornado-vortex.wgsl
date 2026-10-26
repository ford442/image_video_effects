// ═══════════════════════════════════════════════════════════════════
//  Tornado Vortex
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-26
//  Ideas: clear eye; breakdown bulb
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
// tornado-vortex.wgsl — Interactivist upgrade (Batch 16)
// Rankine vortex with OkLab mixing, blackbody lightning, volumetric fog.
// Radial inflow / vertical updraft now actually advect debris (dead physics
// activated). Clicks spawn decaying satellite vortices via ripples[].
// Per-bin treble FFT drives lightning branch count so strikes follow hi-hats.

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash31(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453123);
}

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
    let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
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

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// Interactivist: engine treble FFT bins 1..8 live in plasmaBuffer[1].xyzw
// and plasmaBuffer[2].xyzw (plasmaBuffer[0] = bass/mids/treble bands).
fn plasmaBin(idx: u32) -> f32 {
    let v = plasmaBuffer[1u + idx / 4u];
    return v[idx % 4u];
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Slider wiring (saved-preset contract: ids/defaults unchanged).
  let intensity = u.zoom_params.x;      // Rankine circulation + inflow/updraft strength
  let spinSpeed = u.zoom_params.y * 5.0; // funnel spiral + debris swirl rate
  let debrisAmt = u.zoom_params.z;       // debris count, size, brightness
  let lightningAmt = u.zoom_params.w;    // flash probability + bolt energy

  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let dist = length(p);
  let angle = atan2(p.y, p.x);

  // Rankine vortex
  // ── Idea 2: breakdown bulb ─────────────────────────────────────────
  // A strong funnel swells at mid-height. Intensity still owns the circulation.
  let midH = uv.y - 0.42;
  let bulb = exp(-(midH * midH) / 0.028) * intensity;
  let coreRadius = 0.04 * (1.0 + mids * 0.5) * (1.0 + 0.9 * bulb);
  let circulation = 0.15 * intensity * (1.0 + bass * 0.4);
  let vTheta = select(circulation / (6.28318530718 * dist), circulation * dist / (6.28318530718 * coreRadius * coreRadius), dist > coreRadius);
  let vRadial = -0.02 * intensity * smoothstep(0.3, 0.0, dist);
  let vVertical = 0.1 * intensity * smoothstep(-0.3, 0.4, uv.y) * smoothstep(0.0, 0.1, dist) * (1.0 - 0.85 * bulb);

  // Interactivist: clicks spawn satellite vortices with decaying circulation.
  // Each ripple lives ~2s, spinning its own mini-funnel and tugging the main
  // funnel field while it is alive.
  var satellite = 0.0;
  var satellitePull = vec2<f32>(0.0, 0.0);
  let satCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < satCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    let alive = step(0.0, age) * (1.0 - step(2.0, age));
    let sPos = (rp.xy - 0.5) * vec2<f32>(aspect, 1.0);
    let rel = p - sPos;
    let sDist = max(length(rel), 1e-3);
    let decay = clamp(1.0 - age * 0.5, 0.0, 1.0) * alive;
    let sCore = 0.025 + age * 0.015;
    let sCirc = 0.12 * decay * decay;
    let sVTheta = select(sCirc / (6.28318530718 * sDist), sCirc * sDist / (6.28318530718 * sCore * sCore), sDist > sCore);
    let sAngle = atan2(rel.y, rel.x);
    let sBands = sin(sAngle * 3.0 + sVTheta * time * 50.0 - age * 6.0) * 0.5 + 0.5;
    let sMask = smoothstep(0.16, 0.02, sDist) * decay;
    satellite = satellite + sMask * sBands;
    satellitePull = satellitePull - (rel / sDist) * sVTheta * 0.35 * sMask;
  }

  // Volumetric fog density (Beer-Lambert)
  // ── Idea 1: clear eye ──────────────────────────────────────────────
  // Fog used to be densest on axis. Suppress it inside the Rankine core.
  let eye = 1.0 - smoothstep(coreRadius * 0.3, coreRadius, dist);
  let fogDensity = exp(-dist * 3.0) * 0.15 * intensity * (1.0 - 0.88 * eye);

  var color = vec3<f32>(0.02, 0.03, 0.06);
  var debrisDensity = 0.0;
  var condensation = 0.0;

  // Funnel condensation (satellite vortices dent the funnel wall while alive)
  let funnelWidth = coreRadius + (uv.y + 0.5) * 0.22 * (1.0 + mids * 0.4);
  let funnelDist = abs(dist - funnelWidth * (0.55 + sin(uv.y * 12.0 + time * 0.8) * 0.08 * intensity) + satellite * 0.018);
  condensation = smoothstep(0.045 * intensity, 0.0, funnelDist) * smoothstep(-0.5, 0.5, uv.y);
  let sss = condensation * condensation * vec3<f32>(0.35, 0.42, 0.48) * 0.6;

  // Spiral streaks
  let spiralPhase = angle + vTheta * time * spinSpeed * 40.0 + uv.y * 18.0;
  let spiral = sin(spiralPhase) * 0.5 + 0.5;
  let spiralMask = condensation * spiral * (0.4 + mids * 0.4);

  // Debris advection — Interactivist: the previously dead vRadial / vVertical
  // terms now visibly drive the particles: debris spirals inward along the
  // radial inflow, climbs with the updraft, and brightens as it rises.
  let debrisCount = 8 + i32(debrisAmt * 24.0);
  for (var di = 0; di < debrisCount; di = di + 1) {
    let df = f32(di);
    let seed = hash21(vec2<f32>(df, 0.0));
    let dh = fract(df / f32(debrisCount) + time * 0.08 * (1.0 + bass) + seed * 0.3);
    let dAngle = df * 2.39996 + dh * 8.0 + time * spinSpeed * 0.25 + vTheta * 10.0 + vRadial * dh * 20.0;
    let dRadius = max(0.015 + dh * funnelWidth * 1.1 + vRadial * dh * 9.0, 0.004);
    let dLift = vVertical * dh * 3.0;
    let dPos = vec2<f32>(cos(dAngle), sin(dAngle)) * dRadius + vec2<f32>(0.0, dLift) + satellitePull * 0.25;
    let dd = length(p - dPos);
    let dSize = 0.0025 * (1.0 + debrisAmt) * (1.0 + depth * 0.5);
    let particle = smoothstep(dSize, 0.0, dd);
    let sizeFade = 1.0 - smoothstep(0.0, 0.35, dh);
    let liftGlow = 1.0 + vVertical * 6.0 * dh;
    debrisDensity = debrisDensity + particle * sizeFade;
    color = color + vec3<f32>(0.55, 0.50, 0.45) * particle * debrisAmt * sizeFade * liftGlow;
  }

  // Mouse probe
  let mouseWorld = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(p - mouseWorld);
  let fling = smoothstep(0.12, 0.0, mouseDist) * vTheta * 3.0 * intensity;
  color = color + vec3<f32>(0.7, 0.65, 0.55) * fling;

  // Satellite vortex glow (small OkLab-mixed condensation funnel per click)
  let satBody = clamp(satellite, 0.0, 1.0);
  let satBase = mixOkLab(vec3<f32>(0.10, 0.12, 0.15), vec3<f32>(0.38, 0.42, 0.48), satellite * 0.5);
  color = mixOkLab(color, satBase, satBody * 0.45);

  // Lightning with blackbody temperature — Interactivist: branch count and
  // strike probability follow the high treble FFT bins (hi-hats), not only
  // the global treble band.
  var binSum = 0.0;
  var hiSum = 0.0;
  for (var bi = 0u; bi < 8u; bi = bi + 1u) {
    let bv = plasmaBin(bi);
    binSum = binSum + bv;
    hiSum = hiSum + select(0.0, bv, bi >= 5u);
  }
  binSum = binSum * 0.125;
  hiSum = hiSum * 0.3333;
  let branchCount = 5.0 + floor(clamp(hiSum, 0.0, 1.0) * 7.0);
  let flashTime = floor(time * (6.0 + treble * 8.0 + binSum * 6.0));
  let flash = hash31(vec3<f32>(flashTime, 0.0, 0.0));
  var lightning = step(1.0 - lightningAmt * 0.12 - treble * 0.08 - hiSum * 0.10, flash) * smoothstep(0.35, 0.0, dist);
  let lightningBranch = sin(angle * branchCount + flashTime * 3.7) * 0.5 + 0.5;
  lightning = lightning * (0.4 + lightningBranch * 0.6) * (0.5 + lightningAmt * 0.5);
  let lightningTemp = blackbodyRGB(6500.0 + treble * 8000.0 + hiSum * 4000.0);
  color += lightningTemp * lightning * (1.5 + treble * 2.0 + binSum * 1.5);

  // Ground dust
  let dust = hash21(uv * 55.0 + time * 0.4) * smoothstep(0.0, -0.25, uv.y) * 0.25 * intensity;
  color += vec3<f32>(0.38, 0.33, 0.28) * dust;

  // Build final color with OkLab mixing for funnel
  let funnelBase = mixOkLab(vec3<f32>(0.12, 0.14, 0.16), vec3<f32>(0.35, 0.40, 0.45), spiralMask);
  color = mixOkLab(color, funnelBase, condensation * 0.6);
  color += sss;

  // HDR bloom on lightning
  color += lightningTemp * lightning * lightning * 0.6;

  // Fog attenuation
  color = mix(color, vec3<f32>(0.04, 0.05, 0.08) * blackbodyRGB(3500.0), fogDensity);

  // Tonemap & Dither Stack
  color = hue_preserve_clamp(color, 8.0);
  color = aces(color * 1.5);
  let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  color += vec3<f32>(dither);

  // Depth fade
  let depthFade = 1.0 - depth * 0.2;
  color *= depthFade;

  // Bloom-weight alpha
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let bloomWeight = pow(max(0.0, luma - 0.45), 2.0) * 2.5 + lightning * 0.3 + condensation * 0.15 + satBody * 0.1;
  let a = clamp(bloomWeight, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, a));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, a));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(condensation * 0.5 + debrisDensity * 0.2 + satBody * 0.1, 0.0, 0.0, 0.0));
}
