// ═══════════════════════════════════════════════════════════════════
//  Scanline Cyberpunk — Batch 66
//  Category: image
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-21
//  Ideas: sync-edge line hook (§12.2B sync-pulse timing);
//         dropout bursts (§12.2B)
//  A packing: display RGBA (== writeTexture); B = bass, mid, treble, glitchOffset
//  fp128 glitch offset integration, racing head-roll + phosphor runner,
//  capped click fronts, held amplifies roll, scene depth preserved,
//  ACES + semantic alpha.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 {
  return Fp128(x, 0.0);
}

fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  let f = e - (t - s);
  return Fp128(t, f);
}

fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  let f = e - (t - p);
  return Fp128(t, f);
}

fn fp128_val(x: Fp128) -> f32 {
  return x.base + x.mant;
}

fn hash(x: f32) -> f32 {
    return fract(sin(x * 127.1) * 43758.5453);
}

// Integer PCG lattice hash — copied verbatim from public/shaders/_std/_std_hash.wgsl
// (pcg2d, u32ToUnit, hashCell21). The sin-fract hash above loses all entropy once
// the bar / window labels grow with time; these stay bit-exact for hours.
fn pcg2d(v_in: vec2<u32>) -> vec2<u32> {
  var v = v_in * 1664525u + 1013904223u;
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  return v;
}

fn u32ToUnit(x: u32) -> f32 {
  return f32(x >> 8u) * (1.0 / 16777216.0);
}

fn hashCell21(c: vec2<i32>) -> f32 {
  return u32ToUnit(pcg2d(bitcast<vec2<u32>>(c)).x);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn colorGrade(col: vec3<f32>, strength: f32) -> vec3<f32> {
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let shadowTint   = vec3<f32>(0.05, 0.12, 0.15);
    let highlightTint = vec3<f32>(0.15, 0.08, 0.02);
    let shadowBlend    = (1.0 - luma) * (1.0 - luma);
    let highlightBlend = luma * luma;
    return col
        + shadowTint    * shadowBlend    * strength
        - highlightTint * highlightBlend * strength * 0.5
        + highlightTint * highlightBlend * strength;
}

fn phosphor_runner(uv: vec2<f32>, dims: vec2<f32>, time: f32) -> f32 {
  let phase = fp128_sum(fp128_mul(fp128(uv.x * dims.x * 0.55 + uv.y * 21.0), fp128(1.0)), fp128(-time * 18.0));
  return pow(max(0.0, sin(fp128_val(phase))), 14.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    // Rescue: sample at the texel CENTRE. HEAD used gid/dims (the texel corner), which made the
    // bilinear sampler return a 2x2 box average of the photo shifted half a pixel up-left.
    let uv    = (vec2<f32>(gid.xy) + 0.5) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;
    let held = u.zoom_config.w > 0.5;

    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mid    = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let scanlineStr  = mix(0.0, 0.7,  u.zoom_params.x);
    let phosphorStr  = mix(0.0, 0.5,  u.zoom_params.y);
    let glitchAmt    = mix(0.0, 0.04, u.zoom_params.z) * (1.0 + bass * 2.0) * select(1.0, 1.35, held);
    let gradeStr     = mix(0.0, 1.0,  u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let aspect = dims.x / dims.y;
    let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let mouseField = (1.0 - smoothstep(0.04, 0.34, mouseDist)) * select(0.25, 1.0, held);

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.7) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            clickFront += smoothstep(0.022, 0.0, abs(length(delta) - age * 0.5)) * exp(-age * 1.6);
        }
    }

    let glitchBand = floor(uv.y * 20.0);
    let bandSeed = hash(glitchBand);
    let bandCarrier = sin(time * (8.0 + bass * 5.0) + bandSeed * 6.28318);
    let headRoll = pow(max(0.0, sin(uv.y * 68.0 - time * 15.0)), 15.0);


    // ── Idea 1: sync-edge line hook (§12.2B sync-pulse timing) ─────────
    // The head-roll bar is a sync fault. A real line-start PLL does not just
    // draw a bar: it yanks the lines right behind the fault sideways and
    // relaxes exponentially over the next several lines (the "flag" at the
    // bottom of a VHS picture). The roll bar's own phase gives the distance
    // behind the bar; its floor() labels the bar so each one hooks its own way.
    let rollPhase = (uv.y * 68.0 - time * 15.0) / 6.28318;
    let behindBar = fract(rollPhase - 0.25);                       // 0 at the bar peak, ->1 above the next bar
    let barHash   = hashCell21(vec2<i32>(i32(floor(rollPhase - 0.25)), 7));
    let syncHook  = (barHash - 0.5) * 2.0 * exp(-behindBar * 4.5); // signed, per-bar amplitude

    let offsetPhase = fp128_sum(
      fp128_sum(
        fp128_mul(fp128(bandCarrier * glitchAmt), fp128(0.25 + bass + mouseField * 0.8 + clickFront)),
        fp128(headRoll * glitchAmt * 1.5)
      ),
      fp128(syncHook * glitchAmt * 0.9)
    );
    let glitchOffset = fp128_val(offsetPhase);
    var sampleUV = clamp(vec2<f32>(uv.x + glitchOffset, uv.y), vec2<f32>(0.0), vec2<f32>(1.0));

    let prev = textureLoad(dataTextureC, coord, 0);
    let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    var col = mix(src.rgb, prev.rgb * 0.9, headRoll * 0.15);

    // ── Idea 2: dropout bursts (§12.2B) ────────────────────────────────
    // Tape / broadcast signal loss that rides along with head-switching: on a
    // few scanline pairs the RF envelope drops at a random x and recovers
    // exponentially to the right, as a white flare or a black-out. It is
    // applied to the SIGNAL, before the scanline/triad masks, so the CRT
    // still modulates it. Rate rides the existing glitch slider (+pointer,
    // click fronts); windows are ~110 ms and staggered per line (not a
    // per-frame strobe).
    let lineId  = i32(gid.y >> 1u);                                   // one id per bright+dark row pair
    let dropWin = i32(floor(time * 9.0 + hashCell21(vec2<i32>(lineId, 31)) * 9.0));
    let dropP   = glitchAmt * (1.1 + mouseField * 1.2 + clickFront * 1.5);
    let dropRow = hashCell21(vec2<i32>(lineId, dropWin));
    let dropX   = hashCell21(vec2<i32>(lineId + 7919, dropWin));
    let dropPol = step(0.5, hashCell21(vec2<i32>(lineId + 104729, dropWin)));
    let dropDx  = uv.x - dropX;
    let dropTail = step(1.0 - dropP, dropRow) * step(0.0, dropDx) * exp(-max(dropDx, 0.0) * 22.0);
    col = mix(col, vec3<f32>(0.92, 0.96, 1.0), dropTail * dropPol * 0.85);
    col *= 1.0 - dropTail * (1.0 - dropPol) * 0.88;

    let scanlineRow  = gid.y % 2u;
    let scanlineMask = select(1.0 - scanlineStr, 1.0, scanlineRow == 0u);
    col *= scanlineMask;

    let triadCol = gid.x % 3u;
    var phosphor = vec3<f32>(1.0);
    if (phosphorStr > 0.0) {
        let pDim = 1.0 - phosphorStr * 0.5;
        if      (triadCol == 0u) { phosphor = vec3<f32>(1.0,   pDim, pDim); }
        else if (triadCol == 1u) { phosphor = vec3<f32>(pDim,  1.0,  pDim); }
        else                     { phosphor = vec3<f32>(pDim,  pDim, 1.0 ); }
    }
    col *= phosphor;

    let phosphorRunner = phosphor_runner(uv, dims, time);
    col += phosphor * phosphorRunner * phosphorStr * (0.08 + treble * 0.12);

    let flicker = 1.0 + treble * 0.08 * sin(time * 60.0);
    col *= flicker;

    let lumaOrig    = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let neonOverlay = vec3<f32>(0.0, 0.9, 0.8) * lumaOrig * (0.08 + clickFront * 0.25) * (1.0 + mid);
    col += neonOverlay;

    col = colorGrade(col, gradeStr);
    col = acesToneMap(col);

    let alpha = clamp(src.a + clickFront * 0.08 + phosphorRunner * 0.05 + dropTail * 0.05, 0.06, 0.98);
    let sceneDepth = textureLoad(readDepthTexture, coord, 0).r;

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(sceneDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(dataTextureB, coord, vec4<f32>(bass, mid, treble, glitchOffset));
}
