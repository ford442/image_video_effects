// ═══════════════════════════════════════════════════════════════════
//  Fabric Zipper - Image Effect with Textile and Metal Materials
//  Category: interactive-mouse
//  Features: mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: lit 2/1 twill weave (diagonal ribs + warp crowns, frequency = Weave Frequency, slides with each flap); rolled tape lips (opening edges curl back: roll highlight then dark underside, soft contact shadow cast onto the revealed image)
//  A packing: display RGBA (post-ACES colour + HEAD fabric/metal transmission alpha); C not read
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// Material Properties
const FABRIC_ALPHA: f32 = 0.82;           // Woven fabric base transparency
const SEAM_ALPHA: f32 = 0.95;             // Seams are more opaque
const METAL_ALPHA: f32 = 0.98;            // Metal teeth are nearly opaque
const FABRIC_DENSITY: f32 = 2.5;          // Thread density
const PI: f32 = 3.14159265;
const TOOTH_HALF: f32 = 0.015;            // HEAD tooth band half-width (edge_dist units)
// Key light from the upper-left, toward the viewer (screen y points down).
const LIGHT_DIR: vec3<f32> = vec3<f32>(-0.4523, -0.5528, 0.7035);

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// IDEA 1 — Twill weave height field.
// 2/1 twill: each warp thread floats over two picks and under one, stepping one thread per
// pick, so the floats line up into diagonal ribs with a 3-thread repeat. p is in thread units.
// Returns (height 0..1, dh/dp.x, dh/dp.y). ribFade/threadFade band-limit sub-pixel detail.
fn twillRib(p: vec2<f32>, ribFade: f32, threadFade: f32) -> vec3<f32> {
    let t = fract((p.x + p.y) / 3.0);
    let q = 2.0 * t - 1.0;
    // flat-topped rib (the 2-pick float) with a narrow groove (the 1-pick sink)
    let hRib = 1.0 - q * q * q * q;
    let dRib = -8.0 * q * q * q / 3.0;             // d(hRib)/dp.x == d(hRib)/dp.y
    // rounded warp-thread crowns across the rib
    let fx = fract(p.x);
    let hThr = sin(PI * fx);
    let dThr = PI * cos(PI * fx);
    let h = mix(0.5, hRib, ribFade) * 0.8 + 0.2 * mix(0.5, hThr, threadFade);
    let gx = dRib * ribFade * 0.8 + 0.2 * dThr * threadFade;
    let gy = dRib * ribFade * 0.8;
    return vec3<f32>(h, gx, gy);
}

// Calculate fabric alpha with weave pattern (weavePattern now comes from the twill height)
fn calculateFabricAlpha(weavePattern: f32, isSeam: bool, isTeeth: bool) -> f32 {
    if (isTeeth) {
        return METAL_ALPHA;
    }

    if (isSeam) {
        // Seams have tighter weave = more opaque
        return SEAM_ALPHA;
    }

    // Fabric weave creates varying opacity (ribs opaque, grooves let a little image through)
    let weaveAlpha = mix(FABRIC_ALPHA * 0.9, FABRIC_ALPHA, weavePattern);

    // Thread density affects opacity
    let densityAlpha = exp(-FABRIC_DENSITY * 0.2);
    let finalAlpha = mix(weaveAlpha, weaveAlpha * 0.9, densityAlpha * 0.3);

    return clamp(finalAlpha, 0.65, 0.92);
}

// Fabric SSS for textile areas
fn fabricSSS(baseColor: vec3<f32>, noiseVal: f32) -> vec3<f32> {
    // Fabric has soft diffusion from thread gaps
    let threadTint = vec3<f32>(0.95, 0.95, 0.98);
    let scattered = mix(baseColor, baseColor * threadTint, noiseVal * 0.15);
    return scattered;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Parameters
  let teeth_size = mix(20.0, 100.0, u.zoom_params.x);
  let opening_width = mix(0.1, 1.0, u.zoom_params.y);
  let weave_freq = mix(40.0, 320.0, u.zoom_params.z);   // threads per unit canvas height

  // Mouse
  let mouse = u.zoom_config.yz;
  let aspect = u.config.z / u.config.w;

  // Zipper Logic
  let dx = (uv.x - mouse.x) * aspect;
  let dy = uv.y - mouse.y;

  var width = 0.0;
  if (dy < 0.0) {
      width = -dy * opening_width;
  }
  // HEAD fix: how far the zipper has actually parted here. 0 below the slider, so the
  // closed chain no longer leaks a jagged strip (or a seam-wide sliver) of image.
  let openF = smoothstep(0.0, 0.02, width);

  let tooth_amp = mix(0.0, 0.1, u.zoom_params.w);
  let jagged_width = width + tooth_amp * openF * sin(uv.y * teeth_size * 6.28);

  // Mask
  let edge_dist = abs(dx) - jagged_width;
  let mask = (1.0 - smoothstep(0.0, 0.01, edge_dist)) * openF;

  // Zipper Slider (The Metal Piece)
  let slider_dist = distance(vec2<f32>((uv.x - mouse.x) * aspect, uv.y), vec2<f32>(0.0, mouse.y));
  let slider_mask = 1.0 - smoothstep(0.03, 0.035, slider_dist);

  // Fabric Texture with noise
  let noise_val = noise(uv * 50.0);
  var fabric_col = vec3<f32>(0.1, 0.1, 0.15) + vec3<f32>(noise_val * 0.05);

  // Apply fabric SSS
  fabric_col = fabricSSS(fabric_col, noise_val);

  // ── IDEA 1: lit twill weave ─────────────────────────────────────
  // Flap-local coords: each flap is pulled sideways by the opening, so its weave slides with it.
  let flapX = dx - sign(dx) * width;
  let tp = vec2<f32>(flapX, uv.y) * weave_freq;
  let cellPx = f32(dims.y) / weave_freq;
  let ribFade = smoothstep(1.5, 4.0, cellPx * 2.12);    // rib period = 3 threads / sqrt(2)
  let threadFade = smoothstep(2.5, 6.0, cellPx);
  let tw = twillRib(tp, ribFade, threadFade);
  let twN = normalize(vec3<f32>(-tw.y * 0.45, -tw.z * 0.45, 1.0));
  let twDiff = max(dot(twN, LIGHT_DIR), 0.0) / LIGHT_DIR.z;   // 1.0 on flat cloth
  let twAO = mix(0.6, 1.0, tw.x);                              // grooves sit in shadow
  let twHalf = normalize(LIGHT_DIR + vec3<f32>(0.0, 0.0, 1.0));
  let twSheen = pow(max(dot(twN, twHalf), 0.0), 24.0) * 0.06 * tw.x;
  fabric_col = fabric_col * (0.35 + 0.75 * twDiff) * twAO + vec3<f32>(0.85, 0.88, 1.0) * twSheen;

  // Add a seam line
  let seam = 1.0 - smoothstep(0.0, 0.005, abs(dx));
  let isSeam = seam * step(0.0, dy) > 0.5;
  var fabric_final = mix(fabric_col, vec3<f32>(0.05), seam * step(0.0, dy));

  // ── IDEA 2a: rolled tape lips ───────────────────────────────────
  // Just outside the tooth band the cut edge curls back on itself: a half-cylinder whose
  // normal swings from facing the viewer (joins flat cloth) through a lit roll crown to the
  // dark underside at the lip. Band width grows with the opening.
  let lipW = min(0.008 + 0.1 * width, 0.03);
  let edgeN = normalize(vec2<f32>(sign(dx), opening_width)); // grad(edge_dist): into the flap
  let lipT = clamp((edge_dist - TOOTH_HALF * 0.8) / lipW, 0.0, 1.0);
  let lipTheta = (1.0 - lipT) * 2.2;                                    // 0 = flat, >pi/2 = underside
  let lipNrm = vec3<f32>(-edgeN * sin(lipTheta), cos(lipTheta));
  let lipDiff = max(dot(lipNrm, LIGHT_DIR), 0.0) / LIGHT_DIR.z;
  let lipCrown = pow(max(dot(lipNrm, twHalf), 0.0), 16.0) * 0.22 * (1.0 - lipT);
  let lipUnder = 1.0 - 0.7 * smoothstep(1.3, 2.1, lipTheta);
  let lipShaded = fabric_final * (0.3 + 0.7 * lipDiff) * lipUnder + vec3<f32>(0.9, 0.9, 1.0) * lipCrown;
  fabric_final = mix(fabric_final, lipShaded, openF * step(0.0, edge_dist));

  // Image Texture
  var img_col = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // ── IDEA 2b: contact shadow of the rolled lip on the revealed image ──
  // The key light comes from the left, so the left flap throws a wider shadow across the gap.
  let shadowW = (0.006 + 0.06 * width) * (1.0 - 0.6 * sign(dx));
  let lipShadow = exp(-max(-edge_dist, 0.0) / max(shadowW, 1e-4)) * 0.6 * openF;
  img_col = img_col * (1.0 - lipShadow);

  // Metal Color
  let metal_col = vec3<f32>(0.7, 0.7, 0.8) + vec3<f32>(noise_val * 0.1);

  // Teeth Color (Gold/Silver)
  let tooth_col = vec3<f32>(0.6, 0.5, 0.2);

  // Final Mix
  var final_col = mix(fabric_final, img_col, mask);

  // Draw Teeth (The edge)
  let tooth_vis = step(0.4, fract(uv.y * teeth_size));
  let isTeeth = abs(edge_dist) < TOOTH_HALF && tooth_vis > 0.5;

  if (isTeeth) {
      final_col = tooth_col;
  }

  // Draw Slider
  let isSlider = slider_mask > 0.5;
  final_col = mix(final_col, metal_col, slider_mask);

  // Calculate material alpha
  let materialAlpha = calculateFabricAlpha(tw.x, isSeam, isTeeth || isSlider);

  // Blend alpha: fabric allows some image through, metal is opaque
  let finalAlpha = mix(materialAlpha, 1.0, mask * 0.7);

  let outCol = vec4<f32>(aces(final_col), finalAlpha);
  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
