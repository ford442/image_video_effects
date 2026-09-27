// ═══ CHROMATOGRAPHIC FLUID — FORCE / INJECT ════════════════════════════════
//  Shared velocity (wind + mouse) + RGB dyes with distinct viscosity.
//  A/C packing: dye.rgb + temperature. A is authoritative at every graph node.
//  zoom_params: .x viscosity split, .y wind, .z temperature, .w dye inject

#include "_prelude.wgsl"

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
  let aspect = res.x / res.y;
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

  let dm = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let md = length(dm);
  let hover = smoothstep(0.15, 0.0, md);
  dye += vec3<f32>(0.15, 0.35, 0.7) * hover * 0.002;
  if (held && md < 0.15) {
    let w = smoothstep(0.15, 0.0, md) * inject;
    let hue = 0.5 + 0.5 * sin(time * 1.7 + mouse.x * 8.0);
    dye += vec3<f32>(0.95 + hue * 0.1, 0.25 + treble * 0.4, 0.55 + bass * 0.3) * w * 0.35;
    temp += w * 0.08;
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 0.75) {
      let d = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let splash = smoothstep(0.1, 0.0, d) * (1.0 - age / 0.75) * inject;
      dye += vec3<f32>(0.2, 0.85, 1.0) * splash * 0.55;
    }
  }

  dye = clamp(dye, vec3<f32>(0.0), vec3<f32>(4.0));
  textureStore(dataTextureA, pixel, vec4<f32>(dye, clamp(temp, 0.0, 1.0)));
}
