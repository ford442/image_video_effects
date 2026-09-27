// ═══════════════════════════════════════════════════════════════════
//  Chrono Luma Slit Scan
//  Category: post-processing
//  Floor: history ring wraps at textureNumLayers (8, 4 or 1), not a
//         hardcoded 8 — see HISTORY RING DEPTH below
//  Requires: binding 13 (historyTexture — up to 8-layer ring buffer)
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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv   = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let held = step(0.5, u.zoom_config.w);
  let mouse = u.zoom_config.yz;

  let spreadBase = clamp(u.zoom_params.x * (1.0 + bass * 0.3), 0.0, 1.0);
  let spread = spreadBase * mix(1.0, 0.55, held * exp(-dot(uv - mouse, uv - mouse) * 8.0));
  let warpAmt    = u.zoom_params.y * 0.04 * (1.0 + mids * 0.5 + treble * 0.25);
  let lumaGamma  = 0.1 + u.zoom_params.z * 0.9;
  let origBlend  = u.zoom_params.w;

  let historyHead = u32(extraBuffer[4]);

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma    = dot(current.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

  let slitBandH = pow(max(0.0, sin(uv.y * 48.0 - time * (14.0 + bass * 6.0))), 14.0);
  let slitBandV = pow(max(0.0, sin(uv.x * 52.0 - time * (18.0 + treble * 8.0))), 12.0);
  let scanRunner = slitBandH * 0.5 + slitBandV * 0.5;

  let lumaMapped = pow(clamp(luma, 0.0, 1.0), lumaGamma);
  let lumaAdjusted = clamp(lumaMapped + scanRunner * 0.08, 0.0, 1.0);

  // ── HISTORY RING DEPTH (floor fix, 2026-09-21) ───────────────────
  // The ring is at most 8 layers; after the VRAM probe the runtime may
  // allocate 8, 4 or 1, and it wraps its write head at the ALLOCATED
  // count (renderer/webgpu/frame.ts). A hardcoded HISTORY_DEPTH=8 asked
  // for layers that do not exist on a 4- or 1-layer device and WGSL
  // clamped them to the last layer: scrambled frame order, silently.
  // reach = oldest age this ring can actually supply (0 on a 1-layer ring).
  let histDepth = max(textureNumLayers(historyTexture), 1u);
  let reach   = histDepth - 1u;
  let maxAge  = 1u + u32(spread * f32(max(reach, 1u) - 1u));
  let ageFlt  = 1.0 + (1.0 - lumaAdjusted) * f32(maxAge - 1u);
  let age     = clamp(u32(ageFlt), 1u, max(reach, 1u));
  let ageFrac = fract(ageFlt);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  var warpOffset = vec2<f32>(0.0);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple  = u.ripples[i];
    let rDist   = length(uv - ripple.xy);
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let wave   = sin(rDist * 30.0 - elapsed * 8.0) * exp(-rDist * 6.0 - elapsed * 1.5);
      warpOffset = warpOffset + normalize(uv - ripple.xy + vec2<f32>(0.0001)) * wave * warpAmt;
    }
  }
  warpOffset = warpOffset + (depth - 0.5) * vec2<f32>(sin(time * 0.3), cos(time * 0.2)) * warpAmt * 0.5;

  let sampleUV  = clamp(uv + warpOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let layerA = i32((historyHead + histDepth - min(age, reach))       % histDepth);
  let layerB = i32((historyHead + histDepth - min(age + 1u, reach))  % histDepth);

  let frameA = textureSampleLevel(historyTexture, u_sampler, sampleUV, layerA, 0.0);
  let frameB = textureSampleLevel(historyTexture, u_sampler, sampleUV, layerB, 0.0);

  let slitColor = mix(frameA, frameB, ageFrac);
  let output   = mix(slitColor, current, origBlend);
  let motionD  = length(slitColor.rgb - current.rgb);
  let alpha    = clamp(0.6 + motionD * 2.0 + bass * 0.2 + scanRunner * 0.1, 0.0, 1.0);
  let finalOut = vec4<f32>(output.rgb, alpha);

  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
