// ═══════════════════════════════════════════════════════════════════
//  alucinate - Reaction-Diffusion Psychedelia
//  Category: image
//  Features: upgraded-rgba, depth-aware, reaction-diffusion, fbm-warping, kaleidoscopic-ifs, conformal-mapping, audio-reactive
//  Complexity: Very High
//  Upgraded by: Visualist Agent
//  Date: 2026-05-03
//  Upgraded: 2026-11-21
//  Ideas: mirror-cell chirality (IFS fold count flips the chromatic offsets per mirror facet, §12.2E fold count as material); IFS orbit-trap filigree (veins from the inversion's fixed circle brighten the rainbow overlay, §12.2E orbit trap); Turing-cell lenslets (pattern gradient refracts the R/G/B taps with a +1/0/-1 dispersion spread)
//  A packing: raw field (a, b, |grad a|, diffusionRate), no reader in this file; ACES on writeTexture only
//  Rescues: click ripples used a half-rate clock against session-time ripple starts (picture replaced by rings)
//  Open call: no ACES (HEAD has none; the catalog fit would flatten this high-key remix), so the `upgraded-rgba` tag stays an over-claim
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for(var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise2D(pos);
    pos = rot * pos * 2.0 + 100.0;
    a = a * 0.5;
  }
  return v;
}

fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, 0.0), 4), fbm(p + vec2<f32>(5.2, 1.3), 4));
  let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15, 4),
                    fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126, 4));
  return p + 4.0 * r;
}

// Returns (z.xy, orbit trap, fold count). The fold count and the trap are quantities the loop
// already implies and used to discard (Ideas 1 and 2 below).
fn kaleidoscopeIFS(p: vec2<f32>, time: f32) -> vec4<f32> {
  var z = p;
  let angle = time * 0.1;
  let rot = mat2x2<f32>(cos(angle), -sin(angle), sin(angle), cos(angle));
  var trap = 1.0e3;
  var folds = 0.0;
  for(var i: i32 = 0; i < 5; i = i + 1) {
    // ── Idea 1: every negative component is a mirror reflection by abs(); count them.
    folds = folds + step(z.x, 0.0) + step(z.y, 0.0);
    z = abs(z) - vec2<f32>(0.3, 0.2);
    z = rot * z;
    let d = max(dot(z, z), 0.1);
    z = z / d;
    // ── Idea 2: orbit trap on the inversion's fixed circle |z| = 1 (z/|z|^2 leaves it in place).
    trap = min(trap, abs(length(z) - 1.0));
  }
  return vec4<f32>(z, trap, folds);
}

fn conformalMap(z: vec2<f32>, time: f32) -> vec2<f32> {
  let c = vec2<f32>(sin(time * 0.2) * 0.3, cos(time * 0.17) * 0.3);
  let z2 = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y);
  let denom = max(dot(z2 - c, z2 - c), 0.001);
  return (z2 - c) / denom * 0.5;
}

fn grayScott(uv: vec2<f32>, time: f32) -> vec2<f32> {
  let scale = 12.0;
  let p = uv * scale;
  let feed = 0.037 + sin(time * 0.3) * 0.005;
  let kill = 0.06 + cos(time * 0.25) * 0.003;
  let n1 = sin(p.x + time) * cos(p.y);
  let n2 = cos(p.x) * sin(p.y + time * 0.7);
  let a = 0.5 + 0.5 * sin(n1 * n2 * 3.0);
  let b = 0.25 + 0.25 * cos(n1 + n2 + time);
  let reaction = a * b * b;
  let da = (n1 - a) - reaction + feed * (1.0 - a);
  let db = (n2 - b) + reaction - (kill + feed) * b;
  return vec2<f32>(clamp(a + da * 0.1, 0.0, 1.0), clamp(b + db * 0.1, 0.0, 1.0));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(hsv.z - c);
}

fn gammaCorrect(col: vec3<f32>, gamma: f32) -> vec3<f32> {
  return pow(max(col, vec3<f32>(0.0)), vec3<f32>(1.0 / gamma));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x * 0.5;
  let mouse_uv = u.zoom_config.yz;
  let mouse_active = u.zoom_config.w > 0.0;
  let dist_to_mouse = distance(uv, mouse_uv);
  let mouse_effect = smoothstep(0.4, 0.0, dist_to_mouse) * f32(mouse_active);

  let param1 = u.zoom_params.x;
  let param2 = u.zoom_params.y;
  let param3 = u.zoom_params.z;
  let param4 = u.zoom_params.w;

  let audioPulse = plasmaBuffer[0].x * 0.5 + plasmaBuffer[0].y * 0.3;

  let centered = (uv - 0.5) * 2.0;
  let aspect = resolution.x / resolution.y;
  let ca = vec2<f32>(centered.x * aspect, centered.y);

  var warped = domainWarp(ca * (0.5 + param3 * 1.5), time * (0.3 + param2 * 0.7));
  let ifs = kaleidoscopeIFS(warped, time * (0.1 + param2 * 0.2));
  warped = ifs.xy;
  // Idea 1: +1 on even-fold cells, -1 on odd-fold (mirrored) cells. Idea 2: vein strength.
  let chirality = 1.0 - 4.0 * fract(ifs.w * 0.5);
  let vein = exp(-ifs.z * 20.0);
  warped = conformalMap(warped, time);
  warped = warped * (0.5 + mouse_effect * 0.5 + audioPulse * 0.2);

  // Rescue: ripple.z is a u.config.x timestamp, but `time` here runs at half rate, so the old
  // `rt = time - ripple.z` was negative for a long while and exp(-rt * 2) exploded (the whole
  // picture turned into border-clamped rings). Age is now measured on the same clock as the
  // click and scaled to this shader's half-rate time, which keeps the designed ring speed/decay.
  let rippleCount = min(u32(u.config.y), 50u);
  for(var r: u32 = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let rpos = ripple.xy;
    let rt = (u.config.x - ripple.z) * 0.5;
    let live = step(0.0, rt) * step(rt, 4.0);
    let rtc = clamp(rt, 0.0, 4.0);
    let rdist = distance(uv, rpos);
    let ring = sin(rdist * 40.0 - rtc * 6.0) * exp(-rtc * 2.0) * exp(-rdist * 3.0) * live;
    warped = warped + vec2<f32>(ring * 0.3, ring * 0.2);
  }

  let gsUV = warped * 0.5 + 0.5;
  let gs = grayScott(gsUV, time);
  let patternA = gs.x;
  let patternB = gs.y;
  // ── Idea 3: orientation of the Turing cells. Forward differences of the same analytic pattern
  // give the edge normal of cell `a`; magnitude is clamped so a steep seam cannot fling a tap.
  let gsX = grayScott(gsUV + vec2<f32>(0.02, 0.0), time);
  let gsY = grayScott(gsUV + vec2<f32>(0.0, 0.02), time);
  let gradA = vec2<f32>(gsX.x - patternA, gsY.x - patternA) * 50.0;
  let gradMag = length(gradA) * 0.06;
  let gradN = gradA * 0.06 / max(1.0, gradMag);

  let sampleUV = clamp(warped * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let mixUV = mix(uv, sampleUV, 0.3 + param1 * 0.7);

  let aberration = 0.02 + param1 * 0.06 + mouse_effect * 0.04;
  // Idea 1: the axis-fixed offsets mirror with the facet. Idea 3: the lenslet term follows the cell
  // edge normal (already mirrored by the folds) with R refracted one way and B the other.
  let abC = aberration * chirality;
  let lens = gradN * aberration * 0.9;
  let r = textureSampleLevel(readTexture, u_sampler, mixUV + vec2<f32>(patternB * abC, 0.0) + lens, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, mixUV + vec2<f32>(0.0, patternA * abC), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, mixUV - vec2<f32>(patternB * abC * 0.6, patternA * abC * 0.6) - lens, 0.0).b;

  let hue = fract(patternA * 0.7 + patternB * 0.3 + time * 0.05 + param4 * 0.2 + audioPulse * 0.1);
  let sat = 0.6 + mouse_effect * 0.4;
  // Idea 2: orbit-trap veins lift the rainbow overlay where the fold orbit grazes the unit circle.
  let val = (0.8 + patternA * 0.2 + audioPulse * 0.15) * (1.0 + 0.3 * vein);
  let rainbow = hsv2rgb(vec3<f32>(hue, sat, val));

  var color = mix(vec3<f32>(r, g, b), rainbow, clamp(0.2 + param1 * 0.3 + 0.25 * vein, 0.0, 0.85));
  color = gammaCorrect(color, 0.85 + param4 * 0.3);

  let diffusionRate = 0.5 + 0.5 * sin(time + patternA * 6.28318530718);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  color = mix(color, color * (1.0 + depth * 0.5), 0.35);

  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = mix(0.85, 1.0, luma + mouse_effect * 0.3);
  let finalAlpha = mix(alpha * 0.8, alpha, depth);

  // No ACES here on purpose: this is a high-key photo remix and the catalog ACES fit cuts its
  // clamped luma contrast by ~40 % (std .12 -> .07 on the harness). Open call for the user.
  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

  let rgbaData = vec4<f32>(patternA, patternB, clamp(gradMag, 0.0, 1.0), diffusionRate);
  textureStore(dataTextureA, coord, rgbaData);
}
