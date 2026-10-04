// ═══════════════════════════════════════════════════════════════════
//  Dynamic Halftone
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-04
//  Ideas: Euclidean round→diamond→round spot; 3×3 neighbour dots pool where they overlap; ragged paper-tooth rims
//  A packing: ACES display RGBA (premultiplied by dot-coverage alpha)
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
  zoom_params: vec4<f32>,  // x=Density, y=InfluenceRadius, z=Contrast, w=EdgeSharpness
  ripples: array<vec4<f32>, 50>,
};

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.50, 0.49, 0.47) +
         vec3<f32>(0.48, 0.43, 0.38) *
         cos(6.28318 * (vec3<f32>(1.0, 0.76, 0.48) * t + vec3<f32>(0.03, 0.28, 0.56)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coords = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  var mouse = u.zoom_config.yz;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));

  let density = max(20.0 + zp.x * 100.0, 0.001);
  let influenceRadius = zp.y * (1.0 + bass * 0.2);
  let contrast = max(0.5 + zp.z * 2.0, 0.001);
  let edgeSharpnessFactor = max(mix(2.0, 0.1, zp.w), 0.001);

  let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
  let scale = vec2<f32>(density, density);
  let gridUV = aspectUV * scale;
  let cellIndex = floor(gridUV);
  let tooth = ign(vec2<f32>(global_id.xy) * 0.71) - 0.5;

  // Idea 2: every pixel evaluates its own dot and the eight neighbouring dots,
  // so swollen dots under the cursor spill across the cell edge and pool.
  var dotCov = 0.0;
  var covSum = 0.0;
  var colSum = vec3<f32>(0.0);
  var inkRim = 0.0;
  var luma = 0.0;
  var influence = 0.0;
  var ownColor = vec3<f32>(0.0);
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let cid = cellIndex + vec2<f32>(f32(dx), f32(dy));
      let cellCenterUV = (cid + vec2<f32>(0.5)) / scale;
      let sampleUV = clamp(vec2<f32>(cellCenterUV.x / aspect, cellCenterUV.y), vec2<f32>(0.0), vec2<f32>(1.0));
      let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      let l = dot(col, vec3<f32>(0.299, 0.587, 0.114));
      let infl = smoothstep(influenceRadius, 0.0, length((sampleUV - mouse) * vec2<f32>(aspect, 1.0)));
      let radius = clamp(l * 0.5 * (1.0 + infl * 0.8), 0.0, 0.6);
      let edgeWidth = 0.05 * (1.0 + infl) * edgeSharpnessFactor;
      let plateAngle = sin(time * 0.17 + cid.x * 0.07) * 0.22 + infl * 0.45;
      let rot = mat2x2<f32>(cos(plateAngle), -sin(plateAngle), sin(plateAngle), cos(plateAngle));
      let q = rot * (gridUV - cid - vec2<f32>(0.5)) * vec2<f32>(1.0 + infl * 0.55, 1.0 - infl * 0.22);

      // Idea 1: Euclidean spot — round in highlights, an area-matched diamond
      // around the 50% tone (diamonds chain into a checkerboard), round again
      // past it where overlapping neighbours leave pinched holes.
      let chain = smoothstep(0.26, 0.40, radius) * (1.0 - smoothstep(0.40, 0.56, radius));
      let d = mix(length(q), (abs(q.x) + abs(q.y)) / 1.2533, chain);

      // Idea 3: ragged rim — the dot edge wanders with a per-dot angular
      // signature plus the paper tooth under this pixel.
      let h = ign(cid * 1.7 + vec2<f32>(3.1, 7.3));
      let th = atan2(q.y, q.x);
      let rag = sin(th * 5.0 + h * 6.2832) * 0.6 + sin(th * 11.0 - h * 19.0) * 0.4;
      let rr = radius * (1.0 + rag * 0.045 + tooth * 0.05);

      let a = (1.0 - smoothstep(rr - edgeWidth, rr + edgeWidth, d)) * step(0.001, radius);
      let rim = smoothstep(rr + edgeWidth * 2.2, rr - edgeWidth * 0.25, abs(d - rr)) * step(0.001, radius);
      dotCov = max(dotCov, a);
      covSum = covSum + a;
      colSum = colSum + col * a;
      inkRim = max(inkRim, rim);
      if (dx == 0 && dy == 0) {
        luma = l;
        influence = infl;
        ownColor = col;
      }
    }
  }
  let dotColor = select(ownColor, colSum / max(covSum, 0.0001), covSum > 0.0001);
  // Where two dots overlap the ink lies doubled: deeper, more saturated pool.
  let pool = clamp(covSum - 1.0, 0.0, 1.0);

  let paper = 0.88 + (ign(vec2<f32>(global_id.xy) * 0.37 + time) - 0.5) * 0.08;
  var hdr = mix(vec3<f32>(0.022, 0.020, 0.018) * paper, dotColor * paper, dotCov);
  hdr = mix(hdr, hdr * hdr * 1.35, pool * 0.55);
  hdr = pow(max(hdr, vec3<f32>(0.0)), vec3<f32>(contrast));
  let spectralInk = palette(luma + time * 0.03 + mids * 0.18 + ign(cellIndex));
  hdr = hdr + spectralInk * inkRim * (0.30 + treble * 0.75) * (0.35 + luma) * (1.0 - pool * 0.6);
  hdr = hdr + vec3<f32>(1.0, 0.82, 0.45) * pow(influence, 2.6) * dotCov * (0.22 + bass * 0.45);
  let radial = length(uv - vec2<f32>(0.5)) * 1.414;
  hdr = hdr * mix(1.08, 0.68, smoothstep(0.45, 1.0, radial));

  let dither = (ign(vec2<f32>(global_id.xy) + time * 11.0) - 0.5) / 255.0;
  let finalColor = clamp(aces(hdr * 1.22) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));
  // Alpha encodes dot coverage: filled (and pooled) dots weigh more, empty cells are transparent.
  let hdrLuma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  let alpha = clamp(0.12 + dotCov * (0.42 + luma * 0.32) + pool * 0.08 + pow(max(0.0, hdrLuma - 0.55), 2.0) * 2.4, 0.0, 1.0);
  textureStore(writeTexture, coords, vec4<f32>(finalColor * alpha, alpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coords, vec4<f32>(finalColor * alpha, alpha));
}
