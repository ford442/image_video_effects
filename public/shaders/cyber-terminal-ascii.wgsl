// ═══════════════════════════════════════════════════════════════════
//  Cyber Terminal ASCII
//  Category: retro-glitch
//  Features: audio-reactive, upgraded-rgba, mouse-driven, click-reactive, held-drag
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: hex-dump decode (lens cells show the two hex nibbles of their luma byte from a 4x6 bitmap font); typewriter row entry (the row entering at the bottom types in left-to-right behind a block cursor, bass-driven rate); bit-error flicker (treble flips random glyphs to a neighbour index for a frame, leaving a brief green after-image via C)
//  A packing: pre-ACES linear display RGB + glyph coverage alpha; C read back as colour (after-image persistence)
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
  config: vec4<f32>,       // x=time, y=clickCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=zoomTime, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=Grid Density, y=Color Mode, z=Glow, w=Decoder Radius
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 { return length(p) - r; }

fn getCharacter(id: i32, uv: vec2<f32>) -> f32 {
  let p = uv - 0.5;
  var d = 1.0;
  if (id == 0) { return 0.0; }
  else if (id == 1) { d = sdCircle(p, 0.05); }
  else if (id == 2) { d = min(sdCircle(p - vec2<f32>(0.0, -0.15), 0.05), sdCircle(p - vec2<f32>(0.0, 0.15), 0.05)); }
  else if (id == 3) { d = sdBox(p, vec2<f32>(0.25, 0.05)); }
  else if (id == 4) { d = min(abs(p.x), abs(p.y)) - 0.05; }
  else if (id == 5) {
    let rot45 = mat2x2<f32>(0.707, -0.707, 0.707, 0.707);
    let pr = rot45 * p;
    d = min(min(abs(p.x), abs(p.y)) - 0.05, min(abs(pr.x), abs(pr.y)) - 0.05);
  }
  else if (id == 6) { d = min(sdBox(p - vec2<f32>(0.0, -0.1), vec2<f32>(0.25, 0.04)), sdBox(p - vec2<f32>(0.0, 0.1), vec2<f32>(0.25, 0.04))); }
  else if (id == 7) {
    d = min(min(sdBox(p - vec2<f32>(-0.1, 0.0), vec2<f32>(0.04, 0.3)), sdBox(p - vec2<f32>(0.1, 0.0), vec2<f32>(0.04, 0.3))),
          min(sdBox(p - vec2<f32>(0.0, -0.1), vec2<f32>(0.3, 0.04)), sdBox(p - vec2<f32>(0.0, 0.1), vec2<f32>(0.3, 0.04))));
  }
  else { d = min(abs(sdCircle(p, 0.25)) - 0.04, sdCircle(p - vec2<f32>(0.0, 0.05), 0.08)); }
  return 1.0 - smoothstep(0.0, 0.05, d);
}

// IDEA 1 — 4x6 bitmap font for 0-9 A-F, one u32 per glyph: 6 rows of 4 bits, top row in the
// high nibble, MSB = leftmost column.
fn hexGlyph(nibble: i32, p: vec2<f32>) -> f32 {
  let font = array<u32, 16>(
    0x699996u, 0x262227u, 0x69124fu, 0xe16196u, 0x99f111u, 0xf8e196u, 0x68e996u, 0xf12444u,
    0x696996u, 0x697116u, 0x699f99u, 0xe9e99eu, 0x698896u, 0xe9999eu, 0xf8e88fu, 0xf8e888u);
  if (p.x < 0.0 || p.x >= 1.0 || p.y < 0.0 || p.y >= 1.0) { return 0.0; }
  let col = u32(clamp(p.x * 4.0, 0.0, 3.999));
  let row = u32(clamp(p.y * 6.0, 0.0, 5.999));
  let bits = font[clamp(nibble, 0, 15)];
  let bit = (bits >> ((5u - row) * 4u + (3u - col))) & 1u;
  return f32(bit);
}

// Two-nibble hex dump of a luma byte inside one cell: high nibble on the left half, low on the
// right, each glyph inset so neighbouring cells keep a gutter.
fn hexDumpCell(luma: f32, cellUV: vec2<f32>) -> f32 {
  let byte = i32(clamp(luma, 0.0, 1.0) * 255.0 + 0.5);
  let hi = byte >> 4;
  let lo = byte & 15;
  let half = select(0, 1, cellUV.x >= 0.5);
  let hx = (cellUV.x - f32(half) * 0.5) * 2.0;          // 0..1 within the half
  let p = vec2<f32>((hx - 0.08) / 0.84, (cellUV.y - 0.15) / 0.7);
  return hexGlyph(select(hi, lo, half == 1), p);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;   // direct pointer (the old extraBuffer spring only ever read zeroed state)

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let density = mix(10.0, 200.0, u.zoom_params.x);
  let colorMode = u.zoom_params.y;
  let glowStrength = u.zoom_params.z;
  // Decoder Radius is saved already ranged (0.05..0.4). HEAD re-mapped it through mix(0.05, 0.4, p),
  // so the default 0.3 gave an effective 0.155. Single linear mapping that reproduces that default.
  let decoderRadius = clamp(u.zoom_params.w, 0.05, 0.4) * (0.155 / 0.3);

  let gridDims = vec2<f32>(density * aspect, density);
  let scroll = fract(time * (0.08 + bass * 0.12 + mids * 0.05));
  let cellUV = fract(uv * gridDims + vec2<f32>(0.0, scroll));
  let cellId = floor(uv * gridDims + vec2<f32>(0.0, scroll));
  // Scroll is in CELL units here (HEAD subtracted it in whole-screen UV units, so the picture
  // and the lens drifted a full screen per cycle).
  let cellCenter = (cellId + 0.5 - vec2<f32>(0.0, scroll)) / gridDims;

  let inputColor = textureSampleLevel(readTexture, u_sampler, clamp(cellCenter, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let luma = dot(inputColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let toMouse = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
  let distMouse = length(toMouse);
  let decodeRadius = decoderRadius * select(1.0, 1.35, held);
  let isDecoder = step(distMouse, decodeRadius);

  // IDEA 3 — bit-error flicker: treble flips a few random cells to the neighbouring glyph index
  // for a single frame. The after-image below (C persistence) lets the wrong glyph linger green.
  let frame = floor(time * 60.0);
  let bitErr = hash12(cellId * 0.731 + vec2<f32>(frame * 0.013, 2.0));
  let flipChance = treble * treble * 0.12 + 0.002;
  var glyphIdx = clamp(i32(pow(max(luma, 0.0), 1.2) * 8.0 + 0.5), 0, 8);
  var flipped = 0.0;
  if (bitErr < flipChance) {
    let dir = select(-1, 1, hash12(cellId + vec2<f32>(frame, 9.0)) > 0.5);
    glyphIdx = clamp(glyphIdx + dir, 0, 8);
    flipped = 1.0;
  }

  var charMask = 0.0;
  let seed = dot(cellId, vec2<f32>(12.9898, 78.233)) + time * (5.0 + treble * 3.0);
  let rand = hash12(vec2<f32>(seed, cellId.y));
  var hexMask = 0.0;
  if (isDecoder > 0.5) {
    // IDEA 1 — hex-dump decode: the lens reads each cell as its luma byte, two hex nibbles.
    hexMask = hexDumpCell(luma, cellUV);
    charMask = hexMask;
    if (rand > 0.95 - treble * 0.05) { charMask = 0.0; }   // packet loss blink (HEAD)
  } else {
    charMask = getCharacter(glyphIdx, cellUV);
  }

  // IDEA 2 — typewriter row entry. The row whose cell is sliding in at the bottom edge types in
  // left-to-right as it enters; bass drives the type rate so the line lands early on a beat.
  // A block cursor sits at the typing position and blinks.
  let bottomRow = floor((resolution.y - 0.5) / resolution.y * gridDims.y + scroll);
  let entering = f32(cellId.y >= bottomRow);
  let typeProgress = clamp(scroll * (1.3 + bass * 2.0), 0.0, 1.0);
  let typedCols = typeProgress * gridDims.x;
  let typed = step(cellId.x + 1.0, typedCols);            // fully typed columns
  let atCursor = f32(cellId.x >= typedCols - 1.0 && cellId.x < typedCols && typeProgress < 1.0);
  let blockBlink = step(0.5, fract(time * 3.0));
  let blockCursor = entering * atCursor * blockBlink;
  charMask = mix(charMask, max(charMask * typed, blockCursor), entering);

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      let radius = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst = max(clickBurst, exp(-age * 3.0) * (1.0 - smoothstep(0.0, 0.1, radius)));
    }
  }

  let phosphor = vec3<f32>(0.0, 1.0, 0.2) * luma * 2.0;
  var outputColor = mix(phosphor, inputColor.rgb, colorMode) * charMask * glowStrength;
  // Flipped glyphs flash hotter so the after-image is visible.
  outputColor *= 1.0 + flipped * 1.5;
  outputColor = mix(outputColor, vec3<f32>(0.8, 1.0, 1.0), isDecoder * 0.8) * (1.0 + clickBurst * 0.5);
  // Block cursor draws in phosphor green even inside the lens/colour mode.
  outputColor = mix(outputColor, vec3<f32>(0.2, 1.0, 0.35) * glowStrength * 1.5, blockCursor * entering);

  // C persistence (A holds last frame's pre-ACES RGB): HEAD's soft blend inside the glyph plus a
  // fast phosphor after-image everywhere, so a flipped or scrolled glyph lingers a few frames.
  let prev = clamp(textureLoad(dataTextureC, coord, 0).rgb, vec3<f32>(0.0), vec3<f32>(8.0));
  outputColor = mix(outputColor, prev, 0.08 * charMask);
  outputColor = max(outputColor, prev * vec3<f32>(0.35, 0.5, 0.38));

  let cursorBlink = step(0.5, fract(time * 2.0 + cellId.x * 0.1));
  if (abs(cellId.y - floor(scroll * gridDims.y)) < 1.0 && cellId.x < 3.0) {
    outputColor += vec3<f32>(0.0, 1.0, 0.3) * cursorBlink * 0.15;
  }

  outputColor *= smoothstep(0.8, 0.2, length(uv - 0.5));
  outputColor *= sin(f32(coord.y) * 0.5) * 0.1 + 0.9;
  outputColor = clamp(outputColor, vec3<f32>(0.0), vec3<f32>(8.0));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let coverage = max(charMask, blockCursor * entering);
  let alpha = clamp(coverage * mix(0.7, 1.0, luma) * inputColor.a + clickBurst * 0.2 + isDecoder * 0.1, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(outputColor, alpha));
  let display = acesToneMap(outputColor * (0.95 + bass * 0.05));
  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
