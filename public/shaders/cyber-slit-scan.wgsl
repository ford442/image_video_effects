// ═══════════════════════════════════════════════════════════════════
//  Cyber Slit Scan
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-01
//  Ideas: second lagged scan head; treble artifact bursts; crush contour; field interlace (§12.2B)
//  A packing: linear display RGBA (ACES on writeTexture only; C is the scroll)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
  let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1.0e-10;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = u.config.zw;
  let width = u32(dims.x);
  let height = u32(dims.y);
  if (gid.x >= width || gid.y >= height) { return; }

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  let bitCrush = u.zoom_params.y;
  let hueShift = u.zoom_params.z;
  let artifactAmt = u.zoom_params.w;

  // Idea 2: treble artifact bursts — briefly crush bits harder on treble
  // transients, layered on top of the static Bit Crush slider.
  let bitCrushEffective = clamp(bitCrush + treble * treble * 0.5, 0.0, 1.0);

  var slitX = u32(mouse.x * dims.x);
  if (mouse.x < 0.0) { slitX = width / 2u; }
  slitX = clamp(slitX, 0u, width - 1u);

  let scanHead = 0.5 + 0.5 * sin(time * (1.0 + u.zoom_params.x * 5.0) + f32(gid.y) * 0.025);
  let speed = 1u + u32(clamp(u.zoom_params.x + scanHead * 0.12 + bass * 0.1, 0.0, 1.0) * 5.0);

  // Idea 1: second lagged scan head — a phase-offset head sweeps horizontally
  // and injects its own fresh, independently bit-crushed/hue-shifted column,
  // so the "traveling scan heads" the header already claims are genuinely
  // plural instead of a single head at the right edge.
  let scanHead2 = 0.5 + 0.5 * sin(time * (1.3 + u.zoom_params.x * 5.0) - f32(gid.y) * 0.031 + 2.4);
  var slitX2 = u32(fract(mouse.x + 0.5) * dims.x);
  slitX2 = clamp(slitX2, 0u, width - 1u);
  let head2CenterF = (0.5 + 0.5 * sin(time * 0.37)) * dims.x;
  let head2Width = 2.0 + scanHead2 * 3.0;

  var outputColor: vec4<f32>;
  let inHead2 = abs(f32(gid.x) - head2CenterF) < head2Width && gid.x < width - speed;
  if (gid.x >= width - speed) {
    // ── Idea 2: field interlace (§12.2B) ─────────────────────────
    // Odd rows of the write head read one column further along the slit.
    // Artifact Amount widens that field offset.
    let fieldShift = i32(gid.y & 1u) * i32(1.0 + artifactAmt * 4.0);
    let slitField = u32(clamp(i32(slitX) + fieldShift, 0, i32(width) - 1));
    let uvSource = vec2<f32>(f32(slitField) / dims.x, f32(gid.y) / dims.y);
    let rawCol = textureSampleLevel(readTexture, u_sampler, uvSource, 0.0);

    let bits = max(mix(255.0, 2.0, bitCrushEffective), 1.0);
    let crushed = floor(rawCol * bits) / bits;
    // ── Idea 1: crush contour ────────────────────────────────────
    // The residual the bit crush throws away peaks on the bin edge.
    let qStep = 1.0 / bits;
    let residual = length(rawCol.rgb - crushed.rgb);
    let binEdge = exp(-abs(residual - qStep * 0.5) / max(qStep * 0.22, 1e-4));
    var color = vec4<f32>(crushed.rgb + vec3<f32>(0.75, 0.92, 1.0) * binEdge * (0.12 + artifactAmt * 0.55), crushed.a);

    if (fract(time * 10.0 + f32(gid.y) * 0.01) > 0.98) {
      color *= 1.5;
    }

    let scanBand = smoothstep(0.04, 0.0, abs(fract(f32(gid.y) * 0.018 - time * (2.4 + bass * 1.5)) - 0.5));
    let auroraPhase = f32(gid.y) * 0.012 + time * (3.2 + mids);
    let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(auroraPhase * 0.07) + vec3<f32>(0.0, 0.33, 0.67)));
    color = vec4<f32>(color.rgb + oilSlick * scanBand * (0.25 + artifactAmt * 0.35) * (1.0 + treble * 0.3), color.a);

    var hsv = rgb2hsv(color.rgb);
    hsv.y = min(hsv.y * 1.2, 1.0);
    hsv.z = min(hsv.z * 1.1, 1.0);
    hsv.x = fract(hsv.x + hueShift + mouse.y * 0.5 + mids * 0.12 + held * 0.08);
    outputColor = vec4<f32>(hsv2rgb(hsv), color.a);
  } else if (inHead2) {
    let uvSource2 = vec2<f32>(f32(slitX2) / dims.x, f32(gid.y) / dims.y);
    var color2 = textureSampleLevel(readTexture, u_sampler, uvSource2, 0.0);
    let bits2 = mix(255.0, 2.0, bitCrushEffective);
    color2 = floor(color2 * bits2) / bits2;
    var hsv2 = rgb2hsv(color2.rgb);
    hsv2.x = fract(hsv2.x + hueShift * 0.7 + mouse.y * 0.3 + treble * 0.1);
    outputColor = vec4<f32>(hsv2rgb(hsv2), color2.a);
  } else {
    let diagonal = sin((f32(gid.x + gid.y) * 0.035) - time * 5.0) * artifactAmt * (2.0 + treble * 8.0);
    let heldBend = select(0.0, (mouse.x - f32(gid.x) / dims.x) * 18.0 * artifactAmt, u.zoom_config.w > 0.5);
    var clickKick = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
      let event = u.ripples[i];
      let age = max(time - event.z, 0.0);
      let d = length(vec2<f32>(gid.xy) / dims - event.xy);
      clickKick += exp(-age * 2.0) * exp(-abs(d - age * 0.4) * 55.0) * 12.0;
    }
    let sourceY = clamp(i32(gid.y) + i32(diagonal + heldBend + clickKick), 0, i32(height) - 1);
    let sourceX = min(gid.x + speed, width - 1u);
    outputColor = textureLoad(dataTextureC, vec2<i32>(i32(sourceX), sourceY), 0);

    let conveyor = smoothstep(0.06, 0.0, abs(fract(f32(gid.x) * 0.04 + time * (1.8 + bass)) - 0.5));
    outputColor = vec4<f32>(outputColor.rgb * (1.0 - conveyor * artifactAmt * 0.12), outputColor.a);
  }

  var clickFront = 0.0;
  let rippleCount2 = min(u32(u.config.y), 50u);
  for (var j = 0u; j < rippleCount2; j = j + 1u) {
    let rp = u.ripples[j];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.4) {
      let d = length(vec2<f32>(gid.xy) / dims - rp.xy);
      clickFront = max(clickFront, exp(-d * 120.0) * (1.0 - age / 1.4));
    }
  }
  outputColor = vec4<f32>(outputColor.rgb + vec3<f32>(0.2, 0.85, 1.0) * clickFront * (0.5 + bass), outputColor.a);

  let headWrite = f32(gid.x + speed >= width);
  let alpha = clamp(outputColor.a * 0.55 + headWrite * 0.3 + scanHead * 0.2, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(outputColor.rgb, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(aces(max(outputColor.rgb, vec3<f32>(0.0))), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
