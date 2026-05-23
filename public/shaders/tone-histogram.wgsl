// ═══════════════════════════════════════════════════════════════════
//  Tone Histogram (Pass 1)
//  Category: post-processing
//  Features: multi-pass-1, histogram, auto-exposure
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
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<atomic<u32>>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(
  @builtin(global_invocation_id) gid: vec3<u32>,
  @builtin(local_invocation_index) lidx: u32,
  @builtin(workgroup_id) wid: vec3<u32>,
) {
  // Intentional single-workgroup reducer: binding(10) is shared with generic
  // float storage usage across the renderer, so this pass uses one cooperative
  // workgroup to avoid requiring a separate atomic histogram buffer binding.
  if (wid.x != 0u || wid.y != 0u) { return; }

  let res = vec2<u32>(u32(max(u.config.z, 1.0)), u32(max(u.config.w, 1.0)));
  let totalPixels = max(1u, res.x * res.y);
  let targetBias = (clamp(u.zoom_params.x, 0.0, 1.0) - 0.5) * 0.12;
  let contrastGamma = mix(0.85, 1.25, clamp(u.zoom_params.y, 0.0, 1.0));
  let saturationBias = mix(0.0, 0.12, clamp(u.zoom_params.z, 0.0, 1.0));
  let psychoMode = u.zoom_params.w > 0.5;

  if (lidx < 256u) {
    atomicStore(&extraBuffer[3u + lidx], 0u);
  }
  if (lidx == 0u) {
    atomicStore(&extraBuffer[0], bitcast<u32>(u.config.x));
    atomicStore(&extraBuffer[1], totalPixels);
    atomicStore(&extraBuffer[2], 0u);
  }
  workgroupBarrier();

  for (var idx = lidx; idx < totalPixels; idx = idx + 256u) {
    let x = idx % res.x;
    let y = idx / res.x;
    let uv = (vec2<f32>(vec2<u32>(x, y)) + 0.5) / vec2<f32>(res);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseLuma = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let sat = max(src.r, max(src.g, src.b)) - min(src.r, min(src.g, src.b));
    let tunedLuma = clamp(baseLuma + targetBias + sat * saturationBias, 0.0, 1.0);
    let psychLuma = max(src.r, max(src.g, src.b));
    let luma = pow(select(tunedLuma, psychLuma, psychoMode), contrastGamma);
    let bucket = min(255u, u32(luma * 255.0));

    atomicAdd(&extraBuffer[3u + bucket], 1u);

    let coord = vec2<i32>(i32(x), i32(y));
    textureStore(writeTexture, coord, src);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  }

  workgroupBarrier();

  if (lidx == 0u) {
    var peakBin = 0u;
    var peakCount = 0u;
    for (var b = 0u; b < 256u; b = b + 1u) {
      let count = atomicLoad(&extraBuffer[3u + b]);
      if (count > peakCount) {
        peakCount = count;
        peakBin = b;
      }
    }
    atomicStore(&extraBuffer[2], peakBin);
  }
}
