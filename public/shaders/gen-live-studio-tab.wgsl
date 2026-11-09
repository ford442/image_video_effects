// ═══════════════════════════════════════════════════════════════════
//  Live Studio Tab
//  Category: generative
//  Features: broadcast-overlay, audio-visualizer, video-preview,
//            scanlines, waveform-scopes, upgraded-rgba, chromatic
//  Complexity: Medium
//  Created: 2026-06-28
//  Upgraded: 2026-11-09
//  Ideas: Running Timecode Readout, Lower-Third Slide-In, Tape Dropout Tears
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash12(seed: f32) -> f32 {
  var p3 = fract(vec3<f32>(seed, seed, seed) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn rect(uv: vec2<f32>, p: vec2<f32>, s: vec2<f32>) -> f32 {
  let d = abs(uv - p) - s * 0.5;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

fn drawTextLine(uv: vec2<f32>, t: f32, offset: vec2<f32>) -> f32 {
  let pos = uv - offset;
  let w = 0.003;
  let l = abs(pos.x) - w;
  return 1.0 - smoothstep(0.0, w, abs(l));
}

// 7-segment display helper (simplified for "LIVE" text)
fn drawLiveText(uv: vec2<f32>, pos: vec2<f32>, scale: f32) -> f32 {
  let p = (uv - pos) / scale;
  var d = 100.0;
  // L
  d = min(d, rect(p, vec2<f32>(-0.15, 0.0), vec2<f32>(0.04, 0.3)));
  d = min(d, rect(p, vec2<f32>(-0.08, -0.12), vec2<f32>(0.18, 0.04)));
  // I
  d = min(d, rect(p, vec2<f32>(0.02, 0.0), vec2<f32>(0.04, 0.3)));
  // V
  d = min(d, rect(p, vec2<f32>(0.1, 0.05), vec2<f32>(0.04, 0.2)));
  d = min(d, rect(p, vec2<f32>(0.16, 0.05), vec2<f32>(0.04, 0.2)));
  d = min(d, rect(p, vec2<f32>(0.13, -0.12), vec2<f32>(0.1, 0.04)));
  // E
  d = min(d, rect(p, vec2<f32>(0.24, 0.0), vec2<f32>(0.04, 0.3)));
  d = min(d, rect(p, vec2<f32>(0.28, 0.12), vec2<f32>(0.12, 0.04)));
  d = min(d, rect(p, vec2<f32>(0.28, 0.0), vec2<f32>(0.08, 0.04)));
  d = min(d, rect(p, vec2<f32>(0.28, -0.12), vec2<f32>(0.12, 0.04)));
  return 1.0 - smoothstep(0.0, 0.005, d);
}

// 7-segment digit (0-9) as coverage. p is in digit-local space, cell ~[-0.5,0.5]x[-1,1].
fn segDigit(p: vec2<f32>, n: i32) -> f32 {
  // segment bitmask a..g
  var m = array<i32, 10>(0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F);
  let bits = m[clamp(n, 0, 9)];
  var d = 100.0;
  if ((bits & 0x01) != 0) { d = min(d, rect(p, vec2<f32>(0.0, 0.9), vec2<f32>(0.7, 0.16))); }
  if ((bits & 0x02) != 0) { d = min(d, rect(p, vec2<f32>(0.4, 0.45), vec2<f32>(0.16, 0.8))); }
  if ((bits & 0x04) != 0) { d = min(d, rect(p, vec2<f32>(0.4, -0.45), vec2<f32>(0.16, 0.8))); }
  if ((bits & 0x08) != 0) { d = min(d, rect(p, vec2<f32>(0.0, -0.9), vec2<f32>(0.7, 0.16))); }
  if ((bits & 0x10) != 0) { d = min(d, rect(p, vec2<f32>(-0.4, -0.45), vec2<f32>(0.16, 0.8))); }
  if ((bits & 0x20) != 0) { d = min(d, rect(p, vec2<f32>(-0.4, 0.45), vec2<f32>(0.16, 0.8))); }
  if ((bits & 0x40) != 0) { d = min(d, rect(p, vec2<f32>(0.0, 0.0), vec2<f32>(0.7, 0.16))); }
  return 1.0 - smoothstep(0.0, 0.06, d);
}

// Idea 1: Running Timecode Readout — HH:MM:SS:FF (30 fps) inside the timecode box.
fn drawTimecode(uv: vec2<f32>, center: vec2<f32>, h: f32, t: f32) -> f32 {
  let p = (uv - center) / h;            // digit height ~2 units
  let cellW = 1.3;
  let x = p.x + cellW * 5.5;            // 8 digits + 3 colons ≈ 11 cells
  if (abs(p.y) > 1.2 || x < 0.0 || x >= cellW * 11.0) { return 0.0; }
  let cell = i32(floor(x / cellW));
  let lp = vec2<f32>(x - (f32(cell) + 0.5) * cellW, p.y);
  if (cell == 2 || cell == 5 || cell == 8) {
    let dd = min(length(lp - vec2<f32>(0.0, 0.45)), length(lp + vec2<f32>(0.0, 0.45))) - 0.12;
    return 1.0 - smoothstep(0.0, 0.06, dd);
  }
  let total = max(t, 0.0);
  let ff = i32(floor(fract(total) * 30.0));
  let ss = i32(floor(total)) % 60;
  let mm = i32(floor(total / 60.0)) % 60;
  let hh = i32(floor(total / 3600.0)) % 24;
  var v = 0;
  var tens = false;
  if (cell < 2) { v = hh; tens = cell == 0; }
  else if (cell < 5) { v = mm; tens = cell == 3; }
  else if (cell < 8) { v = ss; tens = cell == 6; }
  else { v = ff; tens = cell == 9; }
  let digit = select(v % 10, v / 10, tens);
  return segDigit(lp, digit);
}

// Draw VU meter bars
fn drawVUMeter(uv: vec2<f32>, pos: vec2<f32>, width: f32, height: f32, level: f32) -> vec3<f32> {
  let p = uv - pos;
  let barCount = 12.0;
  let barH = height / barCount;
  let barW = width * 0.7;
  var col = vec3<f32>(0.0);
  for (var i: i32 = 0; i < 12; i++) {
    let barIdx = f32(i);
    let barPos = vec2<f32>(0.0, -height * 0.5 + barIdx * barH + barH * 0.5);
    let barRect = rect(p, barPos, vec2<f32>(barW, barH * 0.7));
    let barActive = barIdx / barCount < level;
    let greenZone = barIdx < 8;
    let yellowZone = barIdx >= 8 && barIdx < 10;
    var barCol = vec3<f32>(0.0);
    if (barActive && greenZone) { barCol = vec3<f32>(0.2, 0.9, 0.3); }
    else if (barActive && yellowZone) { barCol = vec3<f32>(0.9, 0.9, 0.2); }
    else if (barActive) { barCol = vec3<f32>(0.9, 0.2, 0.2); }
    else { barCol = vec3<f32>(0.08, 0.08, 0.08); }
    col = mix(col, barCol, 1.0 - smoothstep(0.0, 0.002, barRect));
  }
  return col;
}

// Draw waveform scope
fn drawWaveform(uv: vec2<f32>, pos: vec2<f32>, width: f32, height: f32, audio: f32, time: f32) -> vec3<f32> {
  let p = uv - pos;
  let inScope = abs(p.x) < width * 0.5 && abs(p.y) < height * 0.5;
  if (!inScope) { return vec3<f32>(0.0); }
  let xNorm = p.x / (width * 0.5);
  let wave = sin(xNorm * 10.0 + time * 3.0) * 0.3 * audio
           + sin(xNorm * 23.0 - time * 2.0) * 0.15 * audio
           + sin(xNorm * 47.0 + time * 5.0) * 0.08 * audio;
  let d = abs(p.y - wave * height * 0.5);
  let glow = 1.0 - smoothstep(0.0, 0.008, d);
  let line = 1.0 - smoothstep(0.0, 0.002, d);
  return vec3<f32>(0.1, 0.8, 0.9) * glow * 0.5 + vec3<f32>(0.5, 1.0, 1.0) * line;
}

// Draw circular vector scope
fn drawVectorScope(uv: vec2<f32>, pos: vec2<f32>, radius: f32, audio: f32, time: f32) -> vec3<f32> {
  let p = uv - pos;
  let d = length(p) - radius;
  let inCircle = d < 0.0;
  if (!inCircle) { return vec3<f32>(0.0); }
  let angle = atan2(p.y, p.x);
  let r = length(p) / radius;
  let audioDot = sin(angle * 3.0 + time) * cos(angle * 2.0 - time * 0.5) * audio;
  let dotDist = abs(r - abs(audioDot) * 0.8 - 0.15);
  let glow = 1.0 - smoothstep(0.0, 0.05, dotDist);
  var col = vec3<f32>(0.2, 0.9, 0.4) * glow;
  let ring = 1.0 - smoothstep(0.0, 0.003, abs(d));
  col = mix(col, vec3<f32>(0.3, 0.3, 0.3), ring * 0.5);
  return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.z, u.config.w);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
  let scanlineIntensity = mix(0.0, 0.3, zp.x);
  let overlayOpacity = mix(0.3, 1.0, zp.y);
  let scopeScale = mix(0.5, 1.5, zp.z);
  let glitchAmount = mix(0.0, 0.5, zp.w);

  // Mouse - screen top = UP, flip Y
  let mouseUV = u.zoom_config.yz;
  let mouseY = mouseUV.y;
  // HEAD bug: layout was authored y-up but gid.y = 0 is the top row, so LIVE/timecode
  // rendered upside down. Overlay layout now uses ov (y-up); the video still samples uv.
  let mousePos = vec2<f32>(mouseUV.x, 1.0 - mouseY);
  let ov = vec2<f32>(uv.x, 1.0 - uv.y);

  // Idea 3: Tape Dropout Tears — on bass hits, a few horizontal bands tear sideways
  // and flash white like oxide dropout; band rows reshuffle every 1/15 s.
  let tearSlot = floor(time * 15.0);
  let tearRow = floor(uv.y * 48.0);
  let tearRnd = hash21(vec2<f32>(tearRow, tearSlot));
  let tearOn = step(1.0 - glitchAmount * (0.04 + bass * 0.25), tearRnd);
  let tearShift = (hash12(tearRow + tearSlot * 7.0) - 0.5) * 0.12 * tearOn;
  let vuv = vec2<f32>(fract(uv.x + tearShift), uv.y);

  // Base video
  var col = textureSampleLevel(readTexture, u_sampler, vuv, 0.0).rgb;

  // Aspect ratio
  let aspect = res.x / res.y;
  let uvAspect = vec2<f32>(ov.x * aspect, ov.y);
  let mouseAspect = vec2<f32>(mousePos.x * aspect, mousePos.y);

  // ─── Video Preview Window (main feed) ───
  let previewRect = rect(uvAspect, vec2<f32>(aspect * 0.5, 0.55), vec2<f32>(aspect * 0.9, 0.75));
  let previewBorder = 1.0 - smoothstep(0.0, 0.003, abs(previewRect));
  let previewMask = 1.0 - smoothstep(0.0, 0.002, previewRect);

  // Preview inside: just the video, slightly graded
  let previewCol = col * vec3<f32>(1.1, 1.05, 1.0);
  col = mix(col, previewCol, previewMask * 0.3);

  // ─── Scanlines ───
  let scanline = sin(uv.y * res.y * 0.7) * 0.5 + 0.5;
  col = col * (1.0 - scanlineIntensity * scanline * 0.3);

  // ─── Chroma Separation (glitch effect) ───
  let glitch = sin(time * 12.0) * sin(time * 7.3) * glitchAmount * bass;
  let rShift = textureSampleLevel(readTexture, u_sampler, vuv + vec2<f32>(glitch * 0.01, 0.0), 0.0).r;
  let bShift = textureSampleLevel(readTexture, u_sampler, vuv - vec2<f32>(glitch * 0.01, 0.0), 0.0).b;
  col = vec3<f32>(rShift, col.g, bShift);
  // dropout streak: thin bright line with noise along the torn band
  let streak = tearOn * step(0.82, hash21(vec2<f32>(floor(uv.x * 90.0), tearRow + tearSlot)));
  col = mix(col, vec3<f32>(0.92), streak * 0.7);

  // ─── LIVE indicator (top-left) ───
  let livePos = vec2<f32>(0.08 * aspect, 0.92);
  let liveText = drawLiveText(uvAspect, livePos, 0.06);
  let liveBlink = 0.7 + 0.3 * sin(time * 6.0);
  let liveCol = vec3<f32>(0.9, 0.1, 0.1) * liveText * liveBlink;
  // Red dot
  let dotDist = length(uvAspect - vec2<f32>(0.03 * aspect, 0.92)) - 0.008;
  let liveDot = 1.0 - smoothstep(0.0, 0.003, dotDist);
  let dotCol = vec3<f32>(1.0, 0.0, 0.0) * liveDot * liveBlink;
  col = max(col, liveCol);
  col = max(col, dotCol);

  // ─── Timecode display (bottom center) ───
  let tcY = 0.06;
  let tcBox = rect(uvAspect, vec2<f32>(aspect * 0.5, tcY), vec2<f32>(0.25 * aspect, 0.04));
  let tcBg = 1.0 - smoothstep(0.0, 0.002, tcBox);
  col = mix(col, vec3<f32>(0.08, 0.08, 0.08), tcBg * 0.8);
  let tcBorder = 1.0 - smoothstep(0.0, 0.003, abs(tcBox));
  col = mix(col, vec3<f32>(0.3, 0.3, 0.3), tcBorder * 0.5);
  let tcDigits = drawTimecode(uvAspect, vec2<f32>(aspect * 0.5, tcY), 0.012, time);
  col = mix(col, vec3<f32>(1.0, 0.75, 0.2), tcDigits * tcBg);

  // Idea 2: Lower-Third Slide-In — a name strap wipes in from the left every 8 s,
  // holds, then wipes out; its accent bar pulses with mid.
  let ltPhase = fract(time / 8.0);
  let ltIn = smoothstep(0.0, 0.08, ltPhase) * (1.0 - smoothstep(0.75, 0.83, ltPhase));
  let ltRight = mix(0.0, 0.62 * aspect, ltIn);
  let ltY = 0.30;
  let inLt = step(0.06 * aspect, uvAspect.x) * step(uvAspect.x, ltRight) * step(abs(ov.y - ltY), 0.035);
  let ltAccent = step(0.06 * aspect, uvAspect.x) * step(uvAspect.x, 0.075 * aspect) * step(abs(ov.y - ltY), 0.035) * step(0.07 * aspect, ltRight);
  col = mix(col, vec3<f32>(0.05, 0.08, 0.2), inLt * 0.82 * overlayOpacity);
  col = mix(col, vec3<f32>(0.9, 0.15 + mid * 0.6, 0.1), ltAccent * overlayOpacity);
  // two "text" rows: blocky glyph runs that reveal with the wipe
  let glyphX = floor(uvAspect.x * 80.0);
  let glyphOn = step(0.35, hash21(vec2<f32>(glyphX, 3.0)));
  let row1 = step(abs(ov.y - (ltY + 0.012)), 0.007);
  let row2 = step(abs(ov.y - (ltY - 0.016)), 0.004) * step(uvAspect.x, ltRight * 0.7);
  let glyphCell = fract(uvAspect.x * 80.0);
  let glyphGap = step(0.15, glyphCell) * step(glyphCell, 0.85);
  let txt = inLt * step(0.09 * aspect, uvAspect.x) * glyphGap * (row1 * glyphOn + row2 * 0.6);
  col = mix(col, vec3<f32>(0.95), txt * overlayOpacity);

  // ─── VU Meters (right side) ───
  let vuPos = vec2<f32>(aspect * 0.94, 0.55);
  let vuBass = drawVUMeter(uvAspect, vuPos, 0.025 * aspect, 0.35, bass * scopeScale);
  let vuMid = drawVUMeter(uvAspect, vuPos + vec2<f32>(0.035 * aspect, 0.0), 0.025 * aspect, 0.35, mid * scopeScale);
  let vuTreble = drawVUMeter(uvAspect, vuPos + vec2<f32>(0.07 * aspect, 0.0), 0.025 * aspect, 0.35, treble * scopeScale);
  col = max(col, vuBass * overlayOpacity);
  col = max(col, vuMid * overlayOpacity);
  col = max(col, vuTreble * overlayOpacity);

  // ─── Waveform Scope (bottom-left) ───
  let wavePos = vec2<f32>(aspect * 0.15, 0.18);
  let waveCol = drawWaveform(uvAspect, wavePos, 0.22 * aspect, 0.15, bass * 2.0, time);
  col = max(col, waveCol * overlayOpacity);

  // ─── Vector Scope (bottom-right) ───
  let vecPos = vec2<f32>(aspect * 0.78, 0.18);
  let vecCol = drawVectorScope(uvAspect, vecPos, 0.12 * aspect, mid, time);
  col = max(col, vecCol * overlayOpacity);

  // ─── Safe Area Lines (overlay) ───
  let safeOuter = rect(uvAspect, vec2<f32>(aspect * 0.5, 0.5), vec2<f32>(aspect * 0.95, 0.92));
  let safeInner = rect(uvAspect, vec2<f32>(aspect * 0.5, 0.5), vec2<f32>(aspect * 0.85, 0.82));
  // HEAD bug: 1 - a - b went to -1 off the lines, so mix() pushed colour negative (meanL < 0).
  let safeLine = max(1.0 - smoothstep(0.0, 0.002, abs(safeOuter)), 1.0 - smoothstep(0.0, 0.002, abs(safeInner)));
  col = mix(col, vec3<f32>(0.6, 0.6, 0.0), safeLine * 0.15 * overlayOpacity);

  // ─── Crosshair at mouse ───
  let mouseDist = length(uvAspect - mouseAspect);
  let crossH = 1.0 - smoothstep(0.0, 0.002, abs(uvAspect.y - mouseAspect.y));
  let crossV = 1.0 - smoothstep(0.0, 0.002, abs(uvAspect.x - mouseAspect.x));
  let cross = max(crossH, crossV) * (1.0 - smoothstep(0.0, 0.06, mouseDist));
  col = mix(col, vec3<f32>(0.0, 0.9, 0.3), cross * 0.4);

  // ─── FPS / Status bar (bottom strip) ───
  // HEAD bug: the old difference of smoothsteps was negative everywhere (darkening via mix weight < 0).
  let statusBar = 1.0 - smoothstep(0.012, 0.02, ov.y);
  col = mix(col, vec3<f32>(0.1, 0.1, 0.12), statusBar * 0.8);

  // ─── Audio-reactive border glow ───
  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let borderGlow = exp(-edgeDist * 20.0) * bass * 0.3;
  col = col + vec3<f32>(0.3, 0.1, 0.5) * borderGlow;

  // ─── Temporal feedback (ghost trails) ───
  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  col = mix(col, prev * 0.95, 0.05);

  // ─── Chromatic aberration at edges ───
  let vignette = max(1.0 - length((uv - 0.5) * 1.5), 0.0);
  col = max(col * (0.7 + 0.3 * vignette), vec3<f32>(0.0));

  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = sat(luma * 0.8 + 0.2);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(col * 0.95, 0.95));

  let depthUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
