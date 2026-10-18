// ═══════════════════════════════════════════════════════════════════
//  spec-bicubic-crystal — Bicubic Catmull-Rom Crystalline Distortion
//  Category: distortion
//  Features: mouse-driven, audio-reactive, bicubic, catmull-rom,
//            crystalline, chromatic-separation, fresnel-edge, semantic-alpha, ACES
//  Ideas:    1. wedge facets — each cell is a tilted glass wedge, so magnification varies
//               across the facet (the smooth stretch bicubic is there to resolve)
//            2. Fresnel seams — a grazing-angle bright line on the true square cell
//               border, its width set by Facet Sharpness
//            3. facet-normal dispersion — R/B split along each facet's own tilt, widening
//               toward the seams (replaces the cosine-palette iridescence)
//  Complexity: High
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=CrystalScale, y=Distortion, z=FacetSharpness, w=ChromaticSep
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn catmullRom(t: f32) -> vec4<f32> {
  let t2 = t * t;
  let t3 = t2 * t;
  return vec4<f32>(
    -0.5 * t3 + t2 - 0.5 * t,
    1.5 * t3 - 2.5 * t2 + 1.0,
    -1.5 * t3 + 2.0 * t2 + 0.5 * t,
    0.5 * t3 - 0.5 * t2
  );
}

fn sampleBicubic(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, texSize: vec2<f32>) -> vec4<f32> {
  let pixel = uv * texSize - 0.5;
  let f = fract(pixel);
  let base = floor(pixel);

  let wx = catmullRom(f.x);
  let wy = catmullRom(f.y);

  var result = vec4<f32>(0.0);
  for (var j = -1; j <= 2; j = j + 1) {
    for (var i = -1; i <= 2; i = i + 1) {
      let coord = (base + vec2<f32>(f32(i), f32(j)) + 0.5) / texSize;
      let s = textureSampleLevel(tex, samp, clamp(coord, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
      let weight = wx[i + 1] * wy[j + 1];
      result += s * weight;
    }
  }
  return result;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Raw pointer: the old extraBuffer[133..138] spring raced (pixel (0,0) wrote
  // while every other pixel read) and the buffer is re-uploaded each frame.
  let mouse = rawMouse;

  // Exact parameter contracts
  let crystalScale = mix(3.0, 20.0, u.zoom_params.x) * (1.0 + bass * 0.15);
  let distortion = mix(0.01, 0.18, u.zoom_params.y) * (1.0 + mids * 0.25);
  let facetSharp = mix(0.5, 4.0, u.zoom_params.z);
  let chromaSep = mix(0.002, 0.04, u.zoom_params.w) * (1.0 + treble * 0.4);

  // Crystalline facet UV distortion
  // Square cells: the grid is aspect-corrected (HEAD stretched them with the frame).
  let cellCoord = uv * vec2<f32>(aspect, 1.0) * crystalScale;
  let cellId = floor(cellCoord);
  let cellLocal = fract(cellCoord) - 0.5;

  let facetHash = hash12(cellId + vec2<f32>(37.0, 17.0));
  let facetAngle = facetHash * 6.2831853 + time * 0.2;
  let facetOffset = vec2<f32>(cos(facetAngle), sin(facetAngle)) * distortion;

  let distFromCenter = length(cellLocal);
  let facetEdge = 1.0 - smoothstep(0.35, 0.5, distFromCenter);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleOffset = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleOffset += rDir * wave * 0.03;
    }
  }

  // Idea 1: wedge facets. Each facet is a tilted plane of glass whose thickness
  // grows along its tilt axis. Displacement grows linearly across the cell, so
  // the image is stretched on one side and compressed on the other (a prism
  // wedge), not just translated. The tilt axis turns slowly with the facet.
  let tiltHash = hash12(cellId + vec2<f32>(91.0, 53.0));
  let tiltAngle = tiltHash * 6.2831853 + time * 0.13;
  let tiltDir = vec2<f32>(cos(tiltAngle), sin(tiltAngle));
  let wedge = dot(cellLocal, tiltDir);
  let wedgeOffset = tiltDir * wedge * distortion * (0.8 + bass * 0.3) / crystalScale * 6.0;

  var distortedUV = uv + facetOffset * facetEdge + wedgeOffset * vec2<f32>(1.0 / aspect, 1.0) + rippleOffset;
  let toMouse = (mouse - uv) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(toMouse);
  let mouseInfluence = exp(-mouseDist * mouseDist * (20.0 - held * 10.0)) * (0.5 + held * 0.5);
  distortedUV += vec2<f32>(toMouse.x / aspect, toMouse.y) * mouseInfluence * distortion * 2.0;

  // Idea 2 (geometry): the true square seam of the cell. Facet Sharpness narrows
  // the line.
  let border = max(abs(cellLocal.x), abs(cellLocal.y));
  let seamW = mix(0.12, 0.025, u.zoom_params.z);
  let seam = smoothstep(0.5 - seamW, 0.5, border);

  // Idea 3: facet-normal dispersion. Colours split along each facet's own tilt,
  // and more strongly near the seams where the wedge is thickest, so fringes
  // turn facet by facet instead of all lying along x.
  let chromaDir = tiltDir * vec2<f32>(1.0 / aspect, 1.0) * chromaSep * (1.0 + seam * 1.5);

  // Bicubic Catmull-Rom sampling with chromatic separation
  let rSample = sampleBicubic(readTexture, u_sampler, distortedUV + chromaDir, res).r;
  let gSample = sampleBicubic(readTexture, u_sampler, distortedUV, res).g;
  let bSample = sampleBicubic(readTexture, u_sampler, distortedUV - chromaDir, res).b;
  var color = vec3<f32>(rSample, gSample, bSample);

  // Facet centre glow. The base is clamped: corners sit past 0.5, and a
  // negative base to a fractional power gave NaN speckles at HEAD.
  let edgeGlow = pow(max(1.0 - distFromCenter * 2.0, 0.0), facetSharp) * 0.35 * (1.0 + treble * 0.5);
  color += vec3<f32>(edgeGlow * 0.5, edgeGlow * 0.6, edgeGlow * 0.85);

  // Idea 2 (shading): Fresnel seams. The seam is a bevel seen at a grazing
  // angle. Schlick reflectance there is high, so it reads as a thin bright line
  // with a dark core where the crystals meet.
  let seamCos = mix(1.0, 0.15, seam);
  let seamF = 0.04 + 0.96 * pow(1.0 - seamCos, 5.0);
  let seamCore = smoothstep(0.5 - seamW * 0.25, 0.5, border);
  color = color * (1.0 - seamCore * 0.45) + vec3<f32>(0.9, 0.95, 1.0) * seamF * seam * (0.45 + treble * 0.4);

  // Exact dataTextureC persistence, blended in display space (C holds ACES output).
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  let finalRGB = mix(aces(color), prevC, 0.07);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(facetEdge * 0.7 + edgeGlow * 0.4 + seamF * seam * 0.3 + mouseInfluence * 0.15 + 0.25, 0.1, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
