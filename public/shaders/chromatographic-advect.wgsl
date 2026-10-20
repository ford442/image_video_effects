// ═══ CHROMATOGRAPHIC FLUID — ADVECT ════════════════════════════════════════
//  Semi-Lagrangian dye advection in a shared wind field (mouse vane + audio gusts).
//  Upgraded: 2026-10-17
//  Ideas: differential migration — red lags, blue leads along the same wind
//  A packing: raw dye.rgb + temperature

#include "_prelude.wgsl"

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

  // Solvent (temperature) rides the full wind. Dyes retain differently:
  // Viscosity Split makes red sticky and blue runny.
  let split = u.zoom_params.x;
  let lag = vec3<f32>(
    mix(0.85, 0.35, split),
    mix(0.90, 1.00, split),
    mix(1.00, 1.75, split)
  );
  let solventUv = clamp(uv - vel, vec2<f32>(0.001), vec2<f32>(0.999));
  let solvent = loadDye(vec2<i32>(solventUv * res), resI);
  let rUv = clamp(uv - vel * lag.x, vec2<f32>(0.001), vec2<f32>(0.999));
  let gUv = clamp(uv - vel * lag.y, vec2<f32>(0.001), vec2<f32>(0.999));
  let bUv = clamp(uv - vel * lag.z, vec2<f32>(0.001), vec2<f32>(0.999));
  let dR = loadDye(vec2<i32>(rUv * res), resI).r;
  let dG = loadDye(vec2<i32>(gUv * res), resI).g;
  let dB = loadDye(vec2<i32>(bUv * res), resI).b;
  textureStore(dataTextureA, pixel, vec4<f32>(
    clamp(vec3<f32>(dR, dG, dB), vec3<f32>(0.0), vec3<f32>(4.0)),
    clamp(solvent.a, 0.0, 1.0)
  ));
}
