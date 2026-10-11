// ═══════════════════════════════════════════════════════════════════
//  Pixelate Blast
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-06
//  Ideas: bevelled fragments tilting away from the blast; block/fragment size cascade (finer core)
//  A packing: linear pre-ACES RGB + semantic alpha
//  Motion: Voronoi cellular explosion + domain-warped blast shockwaves
//  History: hygiene/motion pass 2026-09-06
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=CellDensity, y=BlastRadius, z=EdgeGlowAmount, w=ChromaticAmount

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = hash12(p);
  return vec2<f32>(n, hash12(p + vec2<f32>(1.0, 0.0)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct VoroHit {
  f1: f32,
  f2: f32,
  site: vec2<f32>,  // animated site position in lattice space
  cell: vec2<f32>,  // static site position (HEAD's v.z = cell.x + cell.y)
};

fn voronoi(p: vec2<f32>, time: f32) -> VoroHit {
  let n = floor(p);
  let f = fract(p);
  var md = 8.0;
  var md2 = 8.0;
  var closest = vec2<f32>(0.0);
  var site = vec2<f32>(0.0);
  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let g = vec2<f32>(f32(i), f32(j));
      let o = hash22(n + g) * 0.5 + 0.25;
      let anim = vec2<f32>(sin(time + hash12(n + g) * 6.28), cos(time + hash12(n + g + 1.0) * 6.28)) * 0.15;
      let r = g + o + anim - f;
      let d = dot(r, r);
      if (d < md) {
        md2 = md;
        md = d;
        closest = n + g + o;
        site = n + g + o + anim;
      } else if (d < md2) {
        md2 = min(md2, d);
      }
    }
  }
  return VoroHit(sqrt(md), sqrt(md2), site, closest);
}

fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
  let q = vec2<f32>(sin(p.y * 2.0 + time), cos(p.x * 2.0 + time * 0.8));
  return p + q * 0.25;
}

// Idea 2: fragment size cascade — lattice scale is >1 (smaller pixel blocks and Voronoi fragments)
// inside the blast core and 1 outside, applied about the epicentre so the lattice stays continuous.
fn cascadeScale(x: vec2<f32>, epi: vec2<f32>, aspectVec: vec2<f32>, blastRadius: f32, bass: f32) -> f32 {
  let d = length((x - epi) * aspectVec);
  return 1.0 + 0.8 * smoothstep(blastRadius, 0.0, d) * (1.0 + bass * 0.3);
}

fn latticeAt(x: vec2<f32>, epi: vec2<f32>, density: f32, aspectVec: vec2<f32>, blastRadius: f32, bass: f32) -> vec2<f32> {
  return epi * density + (x - epi) * density * cascadeScale(x, epi, aspectVec, blastRadius, bass);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // FIX: the extraBuffer[133..138] spring never persisted (re-uploaded every frame) — it always
  // collapsed to the raw pointer, so use the pointer directly.
  let spring = mouse;

  // Four saved controls preserved
  let cellDensity = mix(8.0, 52.0, u.zoom_params.x) * (1.0 + bass * 0.2);
  let blastRadius = mix(0.12, 0.75, u.zoom_params.y) * select(1.0, 1.4, held);
  let edgeGlowAmt = mix(0.1, 1.8, u.zoom_params.z);
  let chromaAmt = mix(0.002, 0.045, u.zoom_params.w) * (1.0 + treble * 0.7);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFade = mix(0.7, 1.35, depth);

  // Epicenter distance
  let toSpringUv = uv - spring;
  let toSpring = toSpringUv * aspectVec;
  let dist = length(toSpring);
  let blastFade = smoothstep(blastRadius, 0.0, dist);

  // Capped click ripple blast waves
  var blastEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let rd = length((uv - r.xy) * aspectVec);
      blastEnergy += exp(-abs(rd - age * 0.5) * 24.0) * exp(-age * 1.4);
    }
  }

  // Audio acoustic wave
  let bassWave = sin(dist * 18.0 - time * (5.0 + bass * 3.0)) * 0.5 + 0.5;
  blastEnergy += blastFade * (1.2 + held_boost(held)) + bassWave * bass * 0.4;

  // Domain warped Voronoi cells (Idea 2: on the cascaded lattice)
  let warpTime = time * (0.4 + mids * 0.3);
  let blastPush = toSpringUv * blastEnergy * 0.4;
  let lattice = latticeAt(uv, spring, cellDensity, aspectVec, blastRadius, bass);
  let warpedUV = domainWarp(lattice, warpTime);
  let p = warpedUV + blastPush;
  let v = voronoi(p, time * 0.5);

  // HEAD's square pixel blocks (the "Pixelate" mosaic) are kept as the colour source; Idea 2 maps
  // the block centre back through the cascade, so blocks shrink with the fragments in the core.
  // Outside the blast (scale 1) this is exactly HEAD's cellCenter / cellDensity.
  let cellCenter = floor(warpedUV) + 0.5;
  let blockUV = spring + (cellCenter / cellDensity - spring)
              / cascadeScale(uv, spring, aspectVec, blastRadius, bass);
  let cellUV = clamp(blockUV, vec2<f32>(0.0), vec2<f32>(1.0));

  // Cauchy chromatic sampling across blast direction
  let blastDir = select(vec2<f32>(1.0, 0.0), toSpring / max(dist, 1e-4), dist > 0.001);
  let ca = blastDir * chromaAmt * (1.0 + blastEnergy);

  let rCol = textureSampleLevel(readTexture, u_sampler, clamp(cellUV + ca, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gCol = textureSampleLevel(readTexture, u_sampler, cellUV, 0.0).g;
  let bCol = textureSampleLevel(readTexture, u_sampler, clamp(cellUV - ca, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let baseColor = vec3<f32>(rCol, gCol, bCol);

  // Voronoi cell facet edges & glow
  let edgeDist = v.f2 - v.f1;
  let edgeMask = smoothstep(0.08, 0.01, edgeDist);
  let edgePalette = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + (v.cell.x + v.cell.y) * 1.5 + time * 1.5);
  let glowCol = edgePalette * edgeMask * edgeGlowAmt * (1.0 + blastEnergy * 0.8 + treble * 0.5);

  // Idea 1: bevelled fragment tiles that tilt away from the epicentre as they are blasted.
  let rel = p - v.site;
  let rimDir = rel / max(length(rel), 1e-4);
  let bevel = smoothstep(0.14, 0.0, edgeDist);
  let tumble = (hash22(floor(v.cell * 7.0)) - 0.5) * 0.6;
  let tilt = (blastDir * 0.7 + tumble) * blastEnergy * 0.6;
  let slope = rimDir * bevel * 0.9 + tilt;
  let fragN = normalize(vec3<f32>(-slope, 1.0));
  let keyL = normalize(vec3<f32>(-0.5, -0.6, 0.8));
  let facetShade = clamp(dot(fragN, keyL) / keyL.z, 0.35, 1.6);
  let glint = pow(max(dot(reflect(-keyL, fragN), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 24.0) * bevel * 0.4;

  let internalGrad = 1.0 - v.f1 * 1.8;
  var hdr = baseColor * (0.65 + internalGrad * 0.35) * facetShade + vec3<f32>(glint) + glowCol;

  // Radial blast wave highlight
  hdr += vec3<f32>(1.0, 0.85, 0.6) * blastEnergy * edgeMask * 0.5;

  // Exact previous frame history load from dataTextureC for temporal persistence
  let hist = textureLoad(dataTextureC, coord, 0);
  // FIX: guard NaN / garbage left in C by a previous shader.
  let histRGB = clamp(select(vec3<f32>(0.0), hist.rgb, hist.rgb == hist.rgb), vec3<f32>(0.0), vec3<f32>(16.0));
  let feedbackWeight = mix(0.06, 0.28, clamp(blastEnergy * 0.4, 0.0, 1.0));
  hdr = mix(hdr, histRGB, feedbackWeight);

  let finalRGB = acesToneMap(max(hdr, vec3<f32>(0.0)));
  let semanticAlpha = clamp((blastEnergy * 0.3 + blastFade * 0.4 + edgeMask * 0.3) * depthFade + 0.35, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, vec4<f32>(hdr, semanticAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.3 + blastEnergy * 0.5, 0.3), 0.0, 1.0), 0.0, 0.0, 0.0));
}

fn held_boost(h: bool) -> f32 {
  return select(0.0, 0.6, h);
}
