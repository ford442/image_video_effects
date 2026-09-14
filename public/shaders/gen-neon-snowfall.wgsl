// ═══════════════════════════════════════════════════════════════════
//  Neon Snowfall
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Nakaya crystal habit per snow column (hexagonal plates <-> stellar dendrites with 60-degree side branches, mids = supersaturation pushes toward dendrites); habit-dependent fall dynamics (plates sink fast and flutter-tilt with a specular basal-face glint as they swing level, dendrites drift slowly), click = radial wind gust, mouse-held = eddy
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // x=time, y=rippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Flake Density, y=Fall Speed, z=Chroma, w=Streak
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(31.2, 13.6)));
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * noise2(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdSeg2(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
  return length(pa - ba * h);
}

// Snow crystal habit (Nakaya): ice grows with hexagonal symmetry. Low
// supersaturation -> compact hexagonal plates; high -> stellar dendrites whose
// six arms sprout side branches at 60 degrees, longest near the centre.
// q is in aspect-corrected cell units, R the crystal radius, pix one pixel.
fn snowCrystal(q: vec2<f32>, R: f32, habit: f32, pix: f32) -> f32 {
  let r = length(q);
  let a = atan2(q.y, q.x);
  let seg = PI / 3.0;
  let fa = abs(fract(a / seg + 0.5) - 0.5) * seg;
  let f = vec2<f32>(cos(fa), sin(fa)) * r;   // folded: arm lies along +x

  // Hexagonal plate (vertices on the arm axes) with faint ridge lines
  let dHex = dot(f, vec2<f32>(0.8660254, 0.5)) - R * 0.62;
  let plateBody = smoothstep(pix, -pix, dHex);
  let plateRim = exp(-abs(dHex) / (pix * 1.5));
  let ribs = exp(-abs(f.y) / (pix * 1.2)) * plateBody;
  let plate = plateBody * 0.55 + plateRim * 0.45 + ribs * 0.35;

  // Stellar dendrite: main arm + 60-degree side branches tapering to the tip
  let w = R * 0.05 + pix * 0.7;
  let dArm = sdSeg2(f, vec2<f32>(0.0), vec2<f32>(R, 0.0));
  let bp = R * 0.24;
  let k = floor(f.x / bp);
  var dBr = 1e3;
  for (var j: i32 = 0; j < 2; j = j + 1) {
    let ox = (k + f32(j)) * bp;
    if (ox > 0.0 && ox < R * 0.85) {
      let bl = (R - ox) * 0.5;
      let o = vec2<f32>(ox, 0.0);
      let pf = vec2<f32>(f.x, abs(f.y));
      dBr = min(dBr, sdSeg2(pf, o, o + vec2<f32>(0.5, 0.8660254) * bl));
    }
  }
  let dDen = min(dArm, dBr) - w;
  let dendrite = smoothstep(pix, -pix, dDen) + exp(-max(dDen, 0.0) / (pix * 2.0)) * 0.35
               + smoothstep(R * 0.14, 0.0, r) * 0.6;

  return sat(mix(plate, dendrite, habit));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);

  // Clamp/normalize parameter vector
  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));

  // ═══ CHUNK: bass_env smoothing (state relocated to safe slot 133) ═══
  var smoothBass = bass;
  if (arrayLength(&extraBuffer) > 138u) {
    let prevBass = extraBuffer[133];
    smoothBass = clamp(bass_env(prevBass, bass, 0.8, 0.15), 0.0, 1.0);
    if (gid.x == 0u && gid.y == 0u) {
      extraBuffer[133] = smoothBass;
    }
  }

  let flakeDensity = mix(20.0, 180.0, zp.x);
  let fallSpeed = mix(0.08, 2.0, zp.y);
  let chroma = mix(0.2, 2.0, zp.z);
  let blurAmt = mix(0.0, 1.0, zp.w);

  // ═══ Wind: click ripples are radial gusts, mouse-held stirs an eddy ═══
  var gust = vec2<f32>(0.0);
  var gustGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.5) {
      let dv = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
      let dl = max(length(dv), 1e-4);
      let front = dl - age * 0.55;
      let env = exp(-front * front * 30.0) * exp(-age * 1.4);
      gust += (dv / dl) * env * 0.035;
      gustGlow += env;
    }
  }
  let held = u.zoom_config.w;
  if (held > 0.5) {
    let mv = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0);
    let md = length(mv);
    let swirl = exp(-md * md * 10.0) * 0.08;
    gust += vec2<f32>(-mv.y, mv.x) * swirl * (1.0 + bass * 0.4);
  }

  var color = vec3<f32>(0.01, 0.02, 0.05);
  var totalFlake = 0.0;
  var totalTrail = 0.0;
  var totalGlint = 0.0;
  var nearCover = 0.0;

  // ═══ Depth parallax: three layers of falling flakes ═══
  for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
    let depth = f32(layer) * 0.5;
    let scale = 1.0 + depth * 1.5;
    let density = flakeDensity * scale;
    let parallax = mouse * 0.12 * depth;
    let layerSeed = f32(layer) * 13.0;
    let wind = gust * (1.3 - depth * 0.6);

    // Habit is fixed per falling column so each flake keeps its crystal type.
    let colX = uv.x + parallax.x - wind.x;
    let colId = floor(colX * density);
    let habitRnd = hash21(vec2<f32>(colId, layerSeed + 71.0));
    let habit = sat(habitRnd + (mids - 0.35) * 0.6);
    // Terminal velocity: dense plates sink faster than open, draggy dendrites.
    let terminal = mix(1.3, 0.72, habit);
    let speed = fallSpeed * (0.5 + depth * 0.8) * terminal;

    let gridUV = vec2<f32>(colX, uv.y + time * speed + parallax.y - wind.y) * density;
    let cell = floor(gridUV);
    let local = fract(gridUV) - 0.5;
    let rnd = hash22(cell + layerSeed);
    let flakePos = rnd - 0.5 + vec2<f32>(mouse.x * 0.35 * (1.0 - depth), 0.0);

    // Flutter: side-to-side oscillation; plates swing wider and faster.
    let flutterW = mix(3.4, 1.6, habit) * (0.8 + rnd.y * 0.4);
    let flutterPh = time * flutterW + rnd.y * TAU;
    let flutterA = mix(0.1, 0.04, habit);
    let flutterX = sin(flutterPh) * flutterA;
    let latVel = cos(flutterPh) * flutterA * flutterW;
    let offset = local - flakePos * 0.9 - vec2<f32>(flutterX, 0.0);
    let d = length(offset);

    let core = exp(-d * d * (40.0 + smoothBass * 30.0));

    // Crystal silhouette once a cell is big enough on screen to resolve it.
    let cellPx = f32(dims.x) / density;
    let pix = 1.0 / max(cellPx, 1.0);
    let q0 = vec2<f32>(offset.x, offset.y / aspect);
    let tiltAng = rnd.x * TAU + time * 0.2 * (rnd.y - 0.5) + latVel * 0.5;
    let ct = cos(tiltAng); let st = sin(tiltAng);
    let q = vec2<f32>(ct * q0.x - st * q0.y, st * q0.x + ct * q0.y);
    let R = 0.17 * (0.8 + 0.4 * rnd.y) * (1.0 + smoothBass * 0.25);
    let detail = smoothstep(4.0, 12.0, R * cellPx);
    var flake = core;
    if (detail > 0.0) {
      let crystal = snowCrystal(q, R, habit, pix);
      flake = mix(core, max(crystal, core * 0.35), detail);
    }

    // Basal-face glint: plates fall face-level, and flash as the flutter swings
    // them through horizontal (tilt ~ lateral velocity crossing zero).
    let tilt = latVel / max(flutterA * flutterW, 1e-4);
    let glint = exp(-tilt * tilt * 18.0) * (1.0 - habit) * core * (0.7 + treble * 0.6);

    // ═══ Per-flake motion blur trail ═══
    let vel = vec2<f32>((rnd.x - 0.5) * 0.06 + latVel * 0.04, -0.08 - depth * 0.05) * blurAmt;
    let steps = 6;
    var trail = 0.0;
    for (var s: i32 = 0; s < steps; s = s + 1) {
      let t = f32(s) / f32(steps - 1);
      let blurPos = offset - vel * t;
      trail = trail + exp(-dot(blurPos, blurPos) * 35.0) * (1.0 - t);
    }
    trail = trail / f32(steps);

    let twinkle = 0.5 + 0.5 * sin(time * (8.0 + treble * 26.0) + rnd.x * 20.0);
    let hue = rnd.x + time * 0.03 + mids * 0.15 + depth * 0.2;
    let flakeCol = palette(hue,
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(1.0, 1.0, 1.0),
      vec3<f32>(0.0, 0.33, 0.67)
    );

    let depthFade = 1.0 - depth * 0.35;
    color = color + flakeCol * flake * chroma * (0.4 + twinkle * 0.6) * depthFade;
    color = color + flakeCol * trail * chroma * 0.5 * depthFade;
    color = color + mix(flakeCol, vec3<f32>(1.0), 0.7) * glint * 1.6 * depthFade;
    totalFlake = totalFlake + flake;
    totalTrail = totalTrail + trail;
    totalGlint = totalGlint + glint;
    nearCover = nearCover + flake * (1.0 - depth);
  }

  // Gust front: faint cold shimmer where the wind wave passes
  color = color + vec3<f32>(0.25, 0.5, 1.0) * min(gustGlow, 1.0) * 0.06 * chroma;

  // Temporal snowfall persistence: streaks accumulate (exact load from C)
  let cc = clamp(coord, vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
  let prev = textureLoad(dataTextureC, cc, 0);
  color = mix(color, prev.rgb * 0.92, totalTrail * 0.08 + smoothBass * 0.01);

  let display = acesToneMap(max(color, vec3<f32>(0.0)) * 1.1);

  // Alpha: snow coverage (crystals + streaks + glints) with a luminance floor
  let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(totalFlake * 0.85 + totalTrail * 0.5 + totalGlint * 0.4 + luma * 0.2, 0.0, 1.0);
  // Depth: nearer layers weigh more
  let depthOut = clamp(nearCover / max(totalFlake, 1e-3) * min(totalFlake * 2.0, 1.0), 0.0, 1.0);

  let finalColor = vec4<f32>(display, alpha);
  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalColor);
}
