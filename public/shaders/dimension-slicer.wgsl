// ═══════════════════════════════════════════════════════════════════
//  Dimension Slicer
//  Category: image
//  Features: upgraded-rgba, audio-reactive, chromatic-aberration,
//            depth-aware, temporal-slice-rotation, chromatic-slice-dispersion,
//            audio-slice-width, multi-axis-slicing, sdf-panel-borders,
//            depth-aware-slice-intensity
//  Complexity: High
//  Upgraded: 2026-06-28
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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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
) -> vec4<f32> {
  let p = uv - vec2<f32>(0.5);
  let rotP = rot2D(angle) * p;
  let sliceDist = rotP.y;

  let sliceWidth = width * (1.0 + treble * 0.4);
  let inSlice = smoothstep(sliceWidth, sliceWidth * 0.5, abs(sliceDist));

  let slicePos = rotP.x / max(abs(rotP.y), 1e-4);
  let zoomedSlice = slicePos * zoomWarp * (1.0 + depth * depthModulation);

  let chromaShift = chromaAmount * 0.015 * (1.0 + treble * 0.3);
  var rUV = vec2<f32>(zoomedSlice + chromaShift, rotP.y);
  var gUV = vec2<f32>(zoomedSlice, rotP.y);
  var bUV = vec2<f32>(zoomedSlice - chromaShift, rotP.y);

  rUV = rot2D(-angle) * rUV + vec2<f32>(0.5);
  gUV = rot2D(-angle) * gUV + vec2<f32>(0.5);
  bUV = rot2D(-angle) * bUV + vec2<f32>(0.5);

  var color = vec3<f32>(0.0);
  color.r = textureSampleLevel(tex, samp, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  color.g = textureSampleLevel(tex, samp, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  color.b = textureSampleLevel(tex, samp, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // SDF panel border glow
  let borderDist = sdBox(rotP, vec2<f32>(0.48, sliceWidth * 0.5));
  let edgeGlow = smoothstep(0.02, 0.0, abs(borderDist)) * inSlice;

  return vec4<f32>(color, inSlice + edgeGlow * 0.6);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Clamp/normalize params
  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
  let baseAngle = zp.x * PI * 2.0;
  let zoomWarp = zp.y * 2.0;
  let chromaticAmount = zp.z;
  let depthModulation = zp.w * 2.0;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var color = baseColor.rgb;
  var sliceMask = 0.0;
  var edgeAccum = 0.0;

  // Multi-axis slicing: primary + two harmonics rotating at different speeds
  let widths = vec3<f32>(0.04 + bass * 0.015, 0.03 + mids * 0.012, 0.025 + treble * 0.01);
  let angles = vec3<f32>(
    baseAngle + time * 0.3,
    baseAngle * 0.7 + time * 0.5 + PI * 0.333,
    baseAngle * 1.3 + time * 0.2 + PI * 0.667,
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
    color = mix(color, result.rgb, result.a * 0.45);
    sliceMask = max(sliceMask, result.a);
    edgeAccum = edgeAccum + result.a;
  }

  // SDF panel border highlights around the strongest slice
  let panelGlow = smoothstep(1.8, 2.4, edgeAccum);
  let edgeColor = vec3<f32>(1.0, 0.75, 0.45) * (1.0 + bass * 0.5);
  color = mix(color, edgeColor, panelGlow * 0.35);

  // Depth-aware slice intensity: farther (deeper) pixels glow more
  let depthGlow = depth * depthModulation * 0.25;
  color = color + vec3<f32>(depthGlow * 0.3, depthGlow * 0.2, depthGlow * 0.5);

  let finalAlpha = mix(baseColor.a, 1.0, sliceMask * 0.5 + panelGlow * 0.3);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
