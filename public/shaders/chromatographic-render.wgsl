// ═══ CHROMATOGRAPHIC FLUID — RENDER ════════════════════════════════════════
//  False-color plate + solvent sparkle. Commits dye+temp to dataA.
//  Upgraded: 2026-10-17
//  Ideas: solvent-front band on the downwind edge of the dye
//  A packing: raw dye.rgb + temperature (display is ACES on writeTexture only)

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let st = textureLoad(dataTextureC, pixel, 0);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let dye = st.rgb;
  let temp = st.a;
  let lum = max(dye.r, max(dye.g, dye.b));
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let wind = vec2<f32>(
    sin(time * 0.37 + uv.y * 3.1) + (mouse.x - 0.5) * 0.8,
    cos(time * 0.29 + uv.x * 2.7) + (0.5 - mouse.y) * 0.8
  );
  let aheadPx = clamp(pixel + vec2<i32>(i32(sign(wind.x)), i32(sign(wind.y))), vec2<i32>(0), resI - vec2<i32>(1));
  let ahead = textureLoad(dataTextureC, aheadPx, 0).rgb;
  let here = length(dye);
  // Idea — pale solvent front where dye is here and the downwind neighbor is empty.
  let front = smoothstep(0.04, 0.35, here - length(ahead)) * smoothstep(0.08, 0.5, here);
  var col = pow(dye / (dye + vec3<f32>(1.0)), vec3<f32>(0.85));
  col += vec3<f32>(0.9, 0.97, 1.0) * front * (0.35 + plasmaBuffer[0].y * 0.15);
  col = mix(src.rgb * 0.15, col, 0.88);
  col += vec3<f32>(1.0, 0.7, 0.3) * temp * lum * 0.25;
  col += vec3<f32>(0.4, 0.8, 1.0) * plasmaBuffer[0].z * lum * 0.12;
  let alpha = clamp(src.a * 0.2 + (1.0 - exp(-lum)) * 0.8 + temp * 0.08, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(col), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(clamp(dye, vec3<f32>(0.0), vec3<f32>(4.0)), clamp(temp, 0.0, 1.0)));
}
