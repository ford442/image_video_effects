// ═══════════════════════════════════════════════════════════════════
//  Liquid (Interactive) — Original  ·  FROZEN REFERENCE · DO NOT UPGRADE
//  Category: liquid-effects
//
//  This is the original default Slot 1 effect, kept exactly as it ran on
//  go.1ink.us/pixelocity: a faint ambient wobble on the background plus
//  expanding click ripples that displace the photo. Nothing else.
//
//  ⛔ DO NOT UPGRADE THIS SHADER. Do not add Idea Cards, ideas, sim state,
//     refraction, glint, ACES, spring cursors, or an `Upgraded:` line, and do
//     not include it in upgrade batches. scripts/upgrade-worker.mjs skips any
//     shader whose first 30 lines contain the words "DO NOT UPGRADE".
//  ✔  Use it as the BASE for variations: copy it to a NEW id
//     (e.g. liquid-original-<flavour>), then change the copy freely. This
//     file stays byte-stable so every variation can be compared against it.
//  ✔  It is the default Slot 1 effect at boot (src/hooks/useShaderBoot.ts).
//     Leave it that way.
//
//  The upgraded sibling is `liquid` (stateful capillary sim) — that one is
//  free to keep being upgraded. This one is not.
//
//  Port notes (infrastructure only, picture unchanged): the pasted 6-binding
//  header became `#include "_prelude.wgsl"`, workgroup 8x8 -> 16x16 per the
//  engine convention, and a bounds guard was added. The algorithm below is
//  the live shader verbatim, including its quirks (uv is not pixel-centred,
//  `attenuation` is computed but unused, zoom_params are unused).
//  A packing: none — dataTextureA is not written.
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let center_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // --- Ambient Displacement (Background Only) ---
  var ambientDisplacement = vec2<f32>(0.0, 0.0);
  let background_factor = 1.0 - smoothstep(0.0, 0.1, center_depth);

  if (background_factor > 0.0) {
    let time = currentTime * 0.5;
    let base_ambient_strength = 0.004;
    let ambient_freq = 15.0;
    let motion = vec2<f32>(sin(uv.y * ambient_freq + time * 1.2), cos(uv.x * ambient_freq + time));
    ambientDisplacement = motion * base_ambient_strength * background_factor;
  }

  // --- Mouse-driven Ripples ---
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = u.config.x - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        let rippleOriginDepthFactor = 1.0 - textureSampleLevel(readDepthTexture, non_filtering_sampler, rippleData.xy, 0.0).r;
        let ripple_speed = mix(1.0, 2.0, rippleOriginDepthFactor);
        let ripple_amplitude = mix(0.005, 0.015, rippleOriginDepthFactor);
        let wave = sin(dist * 25.0 - timeSinceClick * ripple_speed);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / (3.0 * mix(0.5, 1.0, rippleOriginDepthFactor)));
        let falloff = 1.0 / (dist * 20.0 + 1.0);
        mouseDisplacement += (direction_vec / dist) * wave * ripple_amplitude * falloff;
      }
    }
  }

  // --- Final Output ---
  let totalDisplacement = mouseDisplacement + ambientDisplacement;
  let colorDisplacedUV = uv + totalDisplacement;
  let color = textureSampleLevel(readTexture, u_sampler, colorDisplacedUV, 0.0);
  textureStore(writeTexture, global_id.xy, color);

  // Update depth texture for next frame
  let depthDisplacedUV = uv + mouseDisplacement;
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthDisplacedUV, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
