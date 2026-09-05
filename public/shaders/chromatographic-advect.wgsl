// ═══ CHROMATOGRAPHIC FLUID — ADVECT ════════════════════════════════════════
//  Semi-Lagrangian dye advection in a shared wind field (mouse vane + audio gusts).

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

fn loadDye(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let windAmp = mix(0.002, 0.028, u.zoom_params.y) * (1.0 + bass * 0.8 + mids * 0.25);

  let wind = vec2<f32>(
    sin(time * 0.37 + uv.y * 3.1) + (mouse.x - 0.5) * 0.8,
    cos(time * 0.29 + uv.x * 2.7) + (0.5 - mouse.y) * 0.8,
  );
  var vel = wind * windAmp;
  let dm = (uv - mouse) * vec2<f32>(res.x / res.y, 1.0);
  let md = length(dm) + 0.0001;
  if (held) {
    vel += vec2<f32>(-dm.y, dm.x) / md * 0.012 * smoothstep(0.35, 0.0, md);
  }

  let srcUv = clamp(uv - vel, vec2<f32>(0.001), vec2<f32>(0.999));
  let srcPx = vec2<i32>(srcUv * res);
  let st = loadDye(srcPx, resI);
  textureStore(dataTextureA, pixel, vec4<f32>(clamp(st.rgb, vec3<f32>(0.0), vec3<f32>(4.0)), clamp(st.a, 0.0, 1.0)));
}
