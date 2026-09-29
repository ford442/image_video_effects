// ═══════════════════════════════════════════════════════════════════
//  Sonar Reveal
//  Category: lighting-effects
//  Features: mouse-driven, click-reactive, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: PPI sweep arm with phosphor afterglow wedge; contact blips on image edges at ring fronts; outward-drifting echo return
//  A packing: ACES display RGB + semantic coverage alpha; C read back as colour (exact textureLoad, manual bilinear) for the echo
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.283185307;

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma_at(p: vec2<i32>, maxC: vec2<i32>) -> f32 {
  let q = clamp(p, vec2<i32>(0), maxC);
  return dot(textureLoad(readTexture, q, 0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// Exact C read (no filtering sampler on rgba32float): manual bilinear from 4 texel loads.
fn load_c_bilinear(pos: vec2<f32>, maxC: vec2<i32>) -> vec4<f32> {
  let s = pos - vec2<f32>(0.5);
  let i0 = vec2<i32>(floor(s));
  let f = s - floor(s);
  let c00 = textureLoad(dataTextureC, clamp(i0, vec2<i32>(0), maxC), 0);
  let c10 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0);
  let c01 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
  let c11 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0);
  return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= res.x || global_id.y >= res.y) { return; }

  let uv = vec2<f32>(global_id.xy) / vec2<f32>(res);
  let aspect = u.config.z / u.config.w;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let resF = vec2<f32>(res);
  let maxC = vec2<i32>(res) - vec2<i32>(1);
  let pix = vec2<i32>(global_id.xy);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let baseSize = u.zoom_params.x * 0.45 + 0.06;
  let intensity = u.zoom_params.y * 3.0;
  let softness = u.zoom_params.z * 0.18 + 0.01;
  let echoMix = u.zoom_params.w;

  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let gray = dot(c0.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let dim = vec3<f32>(gray * 0.22, gray * 0.25, gray * 0.30);

  let dUV = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dUV);

  let audioPulse = 1.0 + bass * 0.6 + mids * 0.25;
  // Bass shoves the ring phase by a bounded amount instead of scaling absolute time (HEAD: time*speedBoost jittered).
  let bassShove = bass * 1.2;

  var ringAccum = 0.0;
  var ringFront = 0.0;
  var sparkle = 0.0;
  let f1 = 8.0;
  let f2 = 8.6;
  let f3 = 9.2;
  let detune = 0.015 * (1.0 + mids * 0.5);

  for (var i: u32 = 0u; i < 3u; i = i + 1u) {
    let fi = select(f1, select(f2, f3, i == 1u), i == 0u);
    let phase = dist * fi * TAU - (time * 2.5 + bassShove);
    let rw = 0.012 + softness * 0.06 + treble * 0.008;
    let r = smoothstep(rw, 0.0, abs(sin(phase) * 0.5 - 0.5 + detune * f32(i)));
    ringAccum = ringAccum + r;
    ringFront = ringFront + smoothstep(0.55, 1.0, r);
    sparkle = sparkle + smoothstep(0.85, 1.0, r) * treble * 2.0;
  }
  ringAccum = ringAccum * 0.45;

  // Click shocks: capped loop, age cutoff, radius from age only (no live-bass multiplier).
  let rippleCount = min(u32(u.config.y), 50u);
  var shockwaves = 0.0;
  var shockFront = 0.0;
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rpl = u.ripples[i];
    let elapsed = time - rpl.z;
    if (elapsed < 0.0 || elapsed > 3.0) { continue; }
    let rd = length((uv - rpl.xy) * vec2<f32>(aspect, 1.0));
    let radius = elapsed * 0.35;
    let fade = exp(-elapsed * 2.0);
    shockwaves = shockwaves + smoothstep(0.06, 0.0, abs(rd - radius)) * fade;
    shockFront = shockFront + smoothstep(0.018, 0.0, abs(rd - radius)) * fade;
  }
  shockwaves = clamp(shockwaves, 0.0, 1.0);
  shockFront = clamp(shockFront, 0.0, 1.0);

  let doppler = 1.0 + 0.08 * sin(dist * 40.0 - time * 6.0 - bassShove * 2.0);
  let reveal = 1.0 - smoothstep(baseSize, baseSize + softness + 0.02, dist / doppler);

  let warm = vec3<f32>(1.0, 0.65, 0.15);
  let cool = vec3<f32>(0.15, 0.55, 1.0);
  let temp = clamp(mids * 2.0 + bass, 0.0, 1.0);
  let rimColor = mix(warm, cool, temp);

  // ── Idea 1: PPI sweep arm + phosphor afterglow wedge ──────────────
  // Arm anchored at the pointer (aspect-correct). Afterglow is stateless:
  // fract of the wrapped angle difference = fraction of a revolution since
  // the arm crossed this pixel, so there is no atan2 seam.
  let px = 1.0 / resF.y;
  let armAngle = time * 1.4;
  let armDir = vec2<f32>(cos(armAngle), sin(armAngle));
  let theta = atan2(dUV.y, dUV.x);
  let behind = fract((armAngle - theta) / TAU);
  let hubFade = smoothstep(0.0, 0.03, dist);
  let rangeFade = 1.0 - smoothstep(0.55, 1.35, dist);
  let afterglow = exp(-behind * 5.5) * hubFade * rangeFade;
  let armPerp = abs(dUV.x * armDir.y - dUV.y * armDir.x);
  let armAlong = dot(dUV, armDir);
  let armLine = smoothstep(px * 1.6, 0.0, armPerp) * smoothstep(0.0, px * 2.0, armAlong) * rangeFade;
  let sweepMask = 1.0 - reveal;
  let hdrSweep = rimColor * (gray * 0.9 + 0.03) * afterglow * sweepMask * intensity * 0.35
               + mix(rimColor, vec3<f32>(1.0), 0.5) * armLine * sweepMask * intensity * 0.45;

  // ── Idea 2: contact blips — image edges flash as a ring/shock front passes ──
  let gx = luma_at(pix + vec2<i32>(1, 0), maxC) - luma_at(pix - vec2<i32>(1, 0), maxC);
  let gy = luma_at(pix + vec2<i32>(0, 1), maxC) - luma_at(pix - vec2<i32>(0, 1), maxC);
  let edgeMag = smoothstep(0.04, 0.35, length(vec2<f32>(gx, gy)));
  let frontGate = clamp(ringFront * 0.6 + shockFront, 0.0, 1.0);
  let blip = edgeMag * frontGate;
  let hdrBlip = mix(rimColor, vec3<f32>(1.0, 0.97, 0.9), 0.6) * blip * intensity * 0.9;

  let hdrRim = ringAccum * intensity * audioPulse * rimColor;
  let hdrSparkle = vec3<f32>(1.0, 0.92, 0.75) * sparkle * intensity;
  let hdrShock = shockwaves * intensity * rimColor * 0.6;

  let splitShadow = mix(vec3<f32>(0.08, 0.04, 0.12), vec3<f32>(0.04, 0.08, 0.14), temp);
  let shadowMask = (1.0 - reveal) * (1.0 - ringAccum);
  var rgb = mix(dim, c0.rgb, reveal) + hdrRim + hdrSparkle + hdrShock + hdrSweep + hdrBlip;
  rgb = rgb + splitShadow * shadowMask * 0.25;

  // ── Idea 3: outward-drifting echo return ──────────────────────────
  // C is resampled a few pixels toward the pointer, so each frame the
  // returns migrate outward. The convex mix is done in display space (C is
  // already tone-mapped), so the loop settles on the live frame, never blows out.
  let centre = vec2<f32>(global_id.xy) + vec2<f32>(0.5);
  let mousePx = mouse * resF;
  let toPix = centre - mousePx;
  let toLen = length(toPix);
  let driftDir = select(vec2<f32>(0.0), toPix / max(toLen, 1e-4), toLen > 1.0);
  let driftPx = resF.y * (0.0025 + bass * 0.002);
  let prevEcho = load_c_bilinear(centre - driftDir * driftPx, maxC);
  let echoW = clamp(exp(-depth * 3.0) * 0.75 * echoMix, 0.0, 0.75);

  rgb = aces_tonemap(rgb * 1.2);
  rgb = mix(rgb, clamp(prevEcho.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), echoW);

  let alpha = mix(0.45 + depth * 0.35, 0.85,
                  clamp(reveal + ringAccum * 0.5 + afterglow * sweepMask * 0.3 + blip * 0.3, 0.0, 1.0));

  textureStore(writeTexture, pix, vec4<f32>(rgb, alpha));
  textureStore(dataTextureA, pix, vec4<f32>(rgb, alpha));
  textureStore(writeDepthTexture, pix, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
