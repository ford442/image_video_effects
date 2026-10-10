// ═══════════════════════════════════════════════════════════════════
//  Dimension Slicer
//  Category: image
//  Features: upgraded-rgba, audio-reactive, chromatic-aberration, temporal,
//            depth-aware, temporal-slice-rotation, chromatic-slice-dispersion,
//            audio-slice-width, multi-axis-slicing, sdf-panel-borders,
//            depth-aware-slice-intensity
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: 1) lit cut edges (sdBox border emitted as an R/G/B-split rim line) 2) slice drag memory (C read rotated back by each band's spin → sliding afterimage) 3) corridor parallax (x/|y| projection at three fogged receding planes)
//  A packing: ACES display RGBA (alpha = slice/rim coverage over source alpha)
//
//  Multiple rotating slice axes cut through the image, each with
//  chromatic inside-slice dispersion and SDF panel-border highlights.
//  Slice intensity is modulated by depth and audio, with independent
//  rotation speeds for each axis.
//
//  zoom_params layout:
//    x = primary slice angle / axis count blend
//    y = zoom warp strength
//    z = chromatic dispersion amount
//    w = depth modulation strength
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn rot2D(a: f32) -> mat2x2<f32> {
  let c = cos(a);
  let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

struct SliceOut {
  color: vec3<f32>,
  mask: f32,      // inSlice + edgeGlow * 0.6 (HEAD's mixing weight)
  rim: vec3<f32>, // chromatically split lit cut edge
  inSlice: f32,
};

fn sampleSplit(
  tex: texture_2d<f32>, samp: sampler, along: f32, across: f32, angle: f32, chromaShift: f32
) -> vec3<f32> {
  let rUV = rot2D(-angle) * vec2<f32>(along + chromaShift, across) + vec2<f32>(0.5);
  let gUV = rot2D(-angle) * vec2<f32>(along, across) + vec2<f32>(0.5);
  let bUV = rot2D(-angle) * vec2<f32>(along - chromaShift, across) + vec2<f32>(0.5);
  return vec3<f32>(
    textureSampleLevel(tex, samp, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(tex, samp, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g,
    textureSampleLevel(tex, samp, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );
}

// ── Single-axis slice contribution ───────────────────────────────
fn sliceAxis(
  uv: vec2<f32>,
  angle: f32,
  width: f32,
  zoomWarp: f32,
  depthModulation: f32,
  depth: f32,
  tex: texture_2d<f32>,
  samp: sampler,
  chromaAmount: f32,
  treble: f32
) -> SliceOut {
  let p = uv - vec2<f32>(0.5);
  let rotP = rot2D(angle) * p;
  let sliceDist = rotP.y;

  let sliceWidth = width * (1.0 + treble * 0.4);
  let inSlice = smoothstep(sliceWidth, sliceWidth * 0.5, abs(sliceDist));

  // Floor |y| at a tenth of the band so x/|y| cannot blow up on the band's centre line.
  let slicePos = rotP.x / max(abs(rotP.y), sliceWidth * 0.1);
  let zoomedSlice = slicePos * zoomWarp * (1.0 + depth * depthModulation);

  let chromaShift = chromaAmount * 0.015 * (1.0 + treble * 0.3);

  // Idea 3: corridor parallax — the same x/|y| projection read at three receding planes
  // (each deeper plane compressed toward the vanishing line), fogged with distance, so the
  // rift reads as a slab running away from the viewer instead of one flat smear.
  let nearC = sampleSplit(tex, samp, zoomedSlice, rotP.y, angle, chromaShift);
  let midC = sampleSplit(tex, samp, zoomedSlice * 0.35, rotP.y * 0.6, angle, chromaShift * 0.6);
  let farC = sampleSplit(tex, samp, zoomedSlice * 0.12, rotP.y * 0.3, angle, chromaShift * 0.3);
  let fog = vec3<f32>(0.10, 0.12, 0.18);
  let color = nearC * 0.55 + mix(midC, fog, 0.3) * 0.28 + mix(farC, fog, 0.6) * 0.17;

  // SDF panel border glow
  let halfW = sliceWidth * 0.5;
  let borderDist = sdBox(rotP, vec2<f32>(0.48, halfW));
  let edgeGlow = smoothstep(0.02, 0.0, abs(borderDist)) * inSlice;

  // Idea 1: lit cut edges — emit the border as a thin rim line, split R/G/B across the cut
  // by the chromatic amount (each channel's edge sits at a slightly different depth).
  let rimShift = chromaShift * 0.5 + 0.0015;
  let rimW = 0.0035;
  let eR = smoothstep(rimW, 0.0, abs(sdBox(rotP + vec2<f32>(0.0, rimShift), vec2<f32>(0.48, halfW))));
  let eG = smoothstep(rimW, 0.0, abs(borderDist));
  let eB = smoothstep(rimW, 0.0, abs(sdBox(rotP - vec2<f32>(0.0, rimShift), vec2<f32>(0.48, halfW))));
  let rim = vec3<f32>(eR, eG, eB) * smoothstep(0.0, 0.3, inSlice + edgeGlow);

  return SliceOut(color, inSlice + edgeGlow * 0.6, rim, inSlice);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Clamp/normalize params
  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let baseAngle = zp.x * PI * 2.0;
  let zoomWarp = zp.y * 2.0;
  let chromaticAmount = zp.z;
  let depthModulation = zp.w * 2.0;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var color = baseColor.rgb;
  var sliceMask = 0.0;
  var edgeAccum = 0.0;
  var rimAccum = vec3<f32>(0.0);
  var dragUV = uv;
  var dragW = 0.0;

  // Multi-axis slicing: primary + two harmonics rotating at different speeds
  let widths = vec3<f32>(0.04 + bass * 0.015, 0.03 + mids * 0.012, 0.025 + treble * 0.01);
  let spins = vec3<f32>(0.3, 0.5, 0.2);   // angular velocity of each band (rad/s)
  let angles = vec3<f32>(
    baseAngle + time * spins.x,
    baseAngle * 0.7 + time * spins.y + PI * 0.333,
    baseAngle * 1.3 + time * spins.z + PI * 0.667,
  );

  for (var i = 0; i < 3; i = i + 1) {
    let result = sliceAxis(
      uv,
      angles[i],
      widths[i],
      zoomWarp,
      depthModulation,
      depth,
      readTexture,
      u_sampler,
      chromaticAmount,
      treble
    );
    color = mix(color, result.color, result.mask * 0.45);
    sliceMask = max(sliceMask, result.mask);
    edgeAccum = edgeAccum + result.mask;
    rimAccum = rimAccum + result.rim;

    // Idea 2: slice drag memory — inside a band, look up last frame at this pixel rotated
    // back by the band's own angular velocity (~0.12 s of spin), so the rift drags a
    // sliding afterimage of where the cut just was.
    if (result.inSlice > dragW) {
      let lag = -spins[i] * 0.12;
      let rp = rot2D(lag) * (uv - vec2<f32>(0.5)) + vec2<f32>(0.5);
      dragUV = rp;
      dragW = result.inSlice;
    }
  }

  // SDF panel border highlights around the strongest slice
  let panelGlow = smoothstep(1.8, 2.4, edgeAccum);
  let edgeColor = vec3<f32>(1.0, 0.75, 0.45) * (1.0 + bass * 0.5);
  color = mix(color, edgeColor, panelGlow * 0.35);

  // Idea 1: lit cut edges, warm-white light split into its R/G/B rims.
  color = color + clamp(rimAccum, vec3<f32>(0.0), vec3<f32>(1.0)) * vec3<f32>(1.0, 0.92, 0.85) * (0.6 + bass * 0.3);

  // Depth-aware slice intensity: farther (deeper) pixels glow more
  let depthGlow = depth * depthModulation * 0.25;
  color = color + vec3<f32>(depthGlow * 0.3, depthGlow * 0.2, depthGlow * 0.5);

  // ACES on display RGB (negatives clamped inside aces()).
  var display = aces(color * 1.1);

  // Idea 2 (cont.): C already holds ACES display, so the afterimage is mixed post-ACES.
  let dims = vec2<i32>(resolution);
  let dragCoord = clamp(vec2<i32>(dragUV * resolution), vec2<i32>(0), dims - vec2<i32>(1));
  let prevC = textureLoad(dataTextureC, dragCoord, 0);
  display = mix(display, prevC.rgb, dragW * 0.35);

  let rimLum = max(rimAccum.r, max(rimAccum.g, rimAccum.b));
  let finalAlpha = clamp(mix(baseColor.a, 1.0, sliceMask * 0.5 + panelGlow * 0.3 + rimLum * 0.3), 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(display, finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(display, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
