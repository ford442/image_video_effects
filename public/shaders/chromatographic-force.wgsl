// ═══ CHROMATOGRAPHIC FLUID — FORCE / INJECT ════════════════════════════════
//  Shared velocity (wind + mouse) + RGB dyes with distinct viscosity.
//  A/C packing: dye.rgb + temperature. B: vel.xy, vorticity, vapor (same-frame).
//  zoom_params: .x viscosity split, .y wind, .z temperature, .w dye inject

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
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let inject = mix(0.15, 1.2, u.zoom_params.w);
  let tempSlider = u.zoom_params.z;

  var st = textureLoad(dataTextureC, pixel, 0);
  if (time < 0.05) {
    st = vec4<f32>(0.02, 0.015, 0.03, tempSlider);
  }

  var dye = max(st.rgb, vec3<f32>(0.0));
  var temp = clamp(st.a * 0.92 + tempSlider * 0.08 + mids * 0.04, 0.0, 1.0);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  dye += src.rgb * 0.004 * inject;

  let dm = uv - mouse;
  let md = length(dm);
  if (held && md < 0.12) {
    let w = smoothstep(0.12, 0.0, md) * inject;
    let hue = 0.5 + 0.5 * sin(time * 1.7 + mouse.x * 8.0);
    dye += vec3<f32>(0.95 + hue * 0.1, 0.25 + treble * 0.4, 0.55 + bass * 0.3) * w * 0.35;
    temp += w * 0.08;
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age > 0.0 && age < 0.45) {
      let d = length(uv - rp.xy);
      let splash = smoothstep(0.08, 0.0, d) * (1.0 - age / 0.45) * inject;
      dye += vec3<f32>(0.2, 0.85, 1.0) * splash * 0.55;
    }
  }

  dye = clamp(dye, vec3<f32>(0.0), vec3<f32>(4.0));
  textureStore(dataTextureA, pixel, vec4<f32>(dye, clamp(temp, 0.0, 1.0)));
}
