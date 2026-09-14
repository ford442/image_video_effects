// ═══════════════════════════════════════════════════════════════════
//  Langton's Ant
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: three-ant colony territories — each ant stains the cells it flips with its colony hue and contested borders glow as seams; oriented ant glyphs (head/thorax/abdomen + antennae) drawn along each turmite's heading, with the L/R turn rule now read from the cell the ant stands on
//  A packing: raw CA state (flip state, heat, colony id/4, 1.0) per pixel; ant trackers at (k*cellSize, 0) hold (x/128, y/128, dir/4, 1.0 moved | 0.75 idle); ACES display RGBA on writeTexture only
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
  zoom_params: vec4<f32>,  // x=Trail Intensity, y=Evolution Speed, z=Seed Pattern, w=Trail Decay
  ripples: array<vec4<f32>, 50>,
};

// Slider shaping applied in linear light (before ACES).
fn applyGenerativePrimaryControls(color: vec3<f32>) -> vec3<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  return pow(max(color * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn heatColor(h: f32) -> vec3<f32> {
  let t = clamp(h * 0.25, 0.0, 1.0);
  let cols = array<vec3<f32>, 5>(
    vec3<f32>(0.05, 0.15, 0.55), vec3<f32>(0.15, 0.65, 0.85),
    vec3<f32>(0.85, 0.75, 0.15), vec3<f32>(0.85, 0.25, 0.10),
    vec3<f32>(0.95, 0.95, 0.90)
  );
  let idx = t * 4.0;
  let i = i32(clamp(idx, 0.0, 3.0));
  return mix(cols[i], cols[i + 1], fract(idx));
}

fn dirVec(d: i32) -> vec2<i32> {
  let dirs = array<vec2<i32>, 4>(vec2<i32>(1, 0), vec2<i32>(0, 1), vec2<i32>(-1, 0), vec2<i32>(0, -1));
  return dirs[((d % 4) + 4) % 4];
}

fn colonyHue(id: i32) -> vec3<f32> {
  let hues = array<vec3<f32>, 4>(
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(1.0, 0.62, 0.18),   // colony 1: amber
    vec3<f32>(0.20, 0.95, 0.85),  // colony 2: cyan
    vec3<f32>(0.95, 0.30, 0.90)   // colony 3: magenta
  );
  return hues[clamp(id, 0, 3)];
}

fn loadC(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

// Pixel that stores CA cell (cx, cy): inverts the depth-scaled cell mapping.
// Row 0 is reserved for ant trackers, so the lookup never lands there.
fn cellPixel(cx: i32, cy: i32, cellSize: i32, resolution: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  let cs = f32(cellSize);
  let scaledUV = (vec2<f32>(f32(cx), f32(cy)) + vec2<f32>(0.5)) * cs / resolution;
  let guess = clamp(vec2<i32>(scaledUV * resolution), vec2<i32>(0), dims - vec2<i32>(1));
  let ds = mix(0.6, 1.4, textureLoad(readDepthTexture, guess, 0).r);
  let uv = (scaledUV - vec2<f32>(0.5)) / ds + vec2<f32>(0.5);
  return clamp(vec2<i32>(uv * resolution), vec2<i32>(0, 1), dims - vec2<i32>(1));
}

// Ant glyph: three body segments along the heading plus two antennae.
fn antGlyph(f: vec2<f32>, fwd: vec2<f32>, treble: f32) -> f32 {
  let side = vec2<f32>(-fwd.y, fwd.x);
  let q = vec2<f32>(dot(f, fwd), dot(f, side));
  let head = length(q - vec2<f32>(0.24, 0.0)) - 0.10;
  let thorax = length((q - vec2<f32>(0.02, 0.0)) * vec2<f32>(1.0, 1.4)) - 0.09;
  let abdomen = length((q + vec2<f32>(0.24, 0.0)) * vec2<f32>(0.85, 1.15)) - 0.15;
  var d = min(head, min(thorax, abdomen));
  let antLen = 0.16 + treble * 0.08;
  for (var s = 0; s < 2; s++) {
    let sg = select(-1.0, 1.0, s == 0);
    let a0 = vec2<f32>(0.30, 0.04 * sg);
    let a1 = a0 + vec2<f32>(0.7, 0.7 * sg) * antLen;
    let pa = q - a0;
    let ba = a1 - a0;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    d = min(d, length(pa - ba * h) - 0.02);
  }
  return smoothstep(0.03, -0.01, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = vec2<f32>(u.config.zw);
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let dims = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = vec2<f32>(pixel) / resolution;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let time = u.config.x;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let gridSize = 128;
  let cellSize = max(1, i32(resolution.x / f32(gridSize)));
  let gridH = clamp(dims.y / cellSize, 1, gridSize);
  let depthScale = mix(0.6, 1.4, depth);
  let scaledUV = (uv - 0.5) * depthScale + 0.5;
  let sCell = vec2<i32>(scaledUV * resolution) / cellSize;
  let cellF = fract(scaledUV * resolution / f32(cellSize)) - vec2<f32>(0.5);

  var state = prev.r;
  var heat = prev.g;
  var colony = i32(prev.b * 4.0 + 0.5);
  let flipBoost = (1.0 + bass * 2.0 + p1) * (1.0 + mids * 0.3);

  // Evolution Speed gates whether the ants step this frame (one decision shared by
  // every pixel). Default 0.2 → always steps (previous look); lower values slow the
  // colony; bass kicks stalled ants forward.
  let stepProb = clamp(0.5 + p2 * 2.5 + bass * 0.5, 0.0, 1.0);
  let stepGate = hashf(floor(time * 60.0) * 0.618 + 0.37) < stepProb;

  var isAntHere = 0.0;
  var glyph = 0.0;
  var glyphTint = vec3<f32>(0.0);
  // ═══ CHUNK: multi-pass state packing — ant position/direction lives in dataTextureA, not writeTexture ═══
  var antEncoded = vec4<f32>(0.0);
  var isAntPixel = false;

  for (var a = 0; a < 3; a++) {
    let apx = a * cellSize;
    let antState = textureLoad(dataTextureC, vec2<i32>(apx, 0), 0);
    var ax = i32(antState.r * f32(gridSize) + 0.5);
    var ay = i32(antState.g * f32(gridSize) + 0.5);
    var adir = i32(antState.b * 4.0 + 0.5) % 4;
    let moved = antState.a > 0.9;

    if antState.a < 0.5 {
      let seeds = array<vec2<i32>, 3>(vec2<i32>(64, 64), vec2<i32>(43, 43), vec2<i32>(85, 85));
      ax = seeds[a].x % gridSize; ay = seeds[a].y % gridH; adir = a;
    }
    if mouseDown && a == 0 {
      let mcell = vec2<i32>(mouse * resolution) / cellSize;
      ax = ((mcell.x % gridSize) + gridSize) % gridSize;
      ay = ((mcell.y % gridH) + gridH) % gridH;
    }
    ay = ay % gridH;

    let dvec = dirVec(adir);
    let fcx = (ax - dvec.x + gridSize) % gridSize;
    let fcy = (ay - dvec.y + gridH) % gridH;
    // Flip the cell the ant left last step (only if it actually moved).
    if moved && sCell.x == fcx && sCell.y == fcy {
      state = 1.0 - state;
      heat += flipBoost;
      colony = a + 1;
    }
    if sCell.x == ax && sCell.y == ay {
      isAntHere += 1.0;
      glyph = max(glyph, antGlyph(cellF, vec2<f32>(dvec), treble));
      glyphTint = colonyHue(a + 1);
    }

    if pixel.x == apx && pixel.y == 0 {
      isAntPixel = true;
      if stepGate {
        // Langton rule: turn by the colour of the cell under the ant, then advance.
        let under = loadC(cellPixel(ax, ay, cellSize, resolution, dims), dims).r;
        adir = (adir + select(3, 1, under > 0.5)) % 4;
        let nd = dirVec(adir);
        ax = (ax + nd.x + gridSize) % gridSize;
        ay = (ay + nd.y + gridH) % gridH;
      }
      antEncoded = vec4<f32>(f32(ax) / 128.0, f32(ay) / 128.0, f32(adir) / 4.0, select(0.75, 1.0, stepGate));
    }
  }

  if prev.a < 0.1 {
    state = step(0.55, hashf(f32(sCell.x) * 17.0 + f32(sCell.y) * 31.0 + p3 * 100.0));
    heat = state * 0.5;
    colony = 0;
  }

  // Click response: a tap drops a patch of black cells (idempotent while the ripple is young),
  // derailing any highway that passes through it.
  let aspect = resolution.x / resolution.y;
  var clickGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age < 0.0 || age > 1.5) { continue; }
    let cellCenter = (vec2<f32>(sCell) + vec2<f32>(0.5)) * f32(cellSize) / resolution;
    let dist = length((cellCenter - rp.xy) * vec2<f32>(aspect, 1.0));
    let patchR = 0.035;
    if (age < 0.25 && dist < patchR) {
      state = 1.0;
      heat = max(heat, 2.0);
    }
    let ring = abs(dist - age * 0.25);
    clickGlow += smoothstep(0.012, 0.0, ring) * exp(-age * 2.5);
  }

  heat = clamp(heat * (0.97 - p4 * 0.03), 0.0, 12.0);

  // Colony territory seams: compare colony ids with the neighbouring cells in C.
  var seam = 0.0;
  if (colony > 0) {
    let nx = i32(loadC(pixel + vec2<i32>(cellSize, 0), dims).b * 4.0 + 0.5);
    let ny = i32(loadC(pixel + vec2<i32>(0, cellSize), dims).b * 4.0 + 0.5);
    let edgeX = select(0.0, 1.0, nx > 0 && nx != colony);
    let edgeY = select(0.0, 1.0, ny > 0 && ny != colony);
    let nearEdgeX = smoothstep(0.30, 0.5, cellF.x);
    let nearEdgeY = smoothstep(0.30, 0.5, cellF.y);
    seam = max(edgeX * nearEdgeX, edgeY * nearEdgeY);
  }

  var color = heatColor(heat);
  let tint = colonyHue(colony);
  let territory = select(0.0, 0.25 + 0.35 * clamp(heat * 0.3, 0.0, 1.0), colony > 0);
  color = mix(color, color * tint * 1.6 + tint * 0.05, territory);
  color += tint * seam * (0.35 + mids * 0.6);
  color += vec3<f32>(0.9, 0.9, 0.85) * isAntHere * 0.25;
  color = mix(color, glyphTint * (1.6 + treble * 1.2), glyph);
  color += vec3<f32>(0.4, 0.8, 1.0) * clickGlow * (0.6 + bass * 0.4);

  let caStr = 0.003 * (1.0 + bass) * depthScale + abs(heat - 3.0) * 0.0015;
  color = vec3<f32>(color.r * (1.0 + caStr), color.g, color.b * (1.0 - caStr * 0.5));
  let display = acesToneMap(applyGenerativePrimaryControls(color * 1.2));

  let alpha = clamp(heat * 0.08 + isAntHere * 0.3 + glyph * 0.5 + territory * 0.3 + seam * 0.3 + clickGlow * 0.3, 0.0, 1.0)
    * mix(0.6, 1.0, depth);
  textureStore(writeTexture, pixel, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(heat * 0.08, 0.0, 0.0, 0.0));

  // ═══ Persistent state: cell flip-state(.r), heat(.g), colony id/4 (.b) everywhere;
  //     ant position/direction encoding overrides at the 3 tracker pixels (apx, 0) ═══
  let cellStateOut = vec4<f32>(state, heat, f32(colony) / 4.0, 1.0);
  textureStore(dataTextureA, pixel, select(cellStateOut, antEncoded, isAntPixel));
}
