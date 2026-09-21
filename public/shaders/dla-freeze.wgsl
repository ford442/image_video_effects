// ═══ DLA CRYSTALS — FREEZE MASK (graph node 1 of 3) ═════════════════════════
//  Carries the frozen mask forward (dataC → dataA), plants seeds, decays dust.
//  Mask packing (dataA / dataC):
//    frozen pixel : .r = 1, .g = seconds since it froze, .b = hue, .a = branch tint
//    free pixel   : .r = 0, .g = 0, .b = 0, .a = walker dust (decays each frame)
//  Walkers (graph node 2) live in the group-1 sim ring, not in this texture.
//  zoom_params: .x walker speed, .y attraction, .z stickiness, .w branch angle

#include "_prelude.wgsl"

const DUST_DECAY: f32 = 0.86;
const FRAME_DT: f32 = 0.016;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let resI = vec2<i32>(res);
  let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let time = u.config.x;
  let px = vec2<f32>(pixel) + 0.5;
  let attract = u.zoom_params.y;

  var st = textureLoad(dataTextureC, pixel, 0);

  // Fresh start: clear everything and plant one seed at the centre.
  if (time < 0.05) {
    st = vec4<f32>(0.0);
    if (length(px - res * 0.5) < 2.5) {
      st = vec4<f32>(1.0, 0.0, 0.55, 0.0);
    }
  }

  if (st.r > 0.5) {
    // Age frozen pixels (relative age, so rgba16float working textures stay exact).
    st.g = min(st.g + FRAME_DT, 60.0);
  } else {
    st = vec4<f32>(0.0, 0.0, 0.0, st.a * DUST_DECAY);

    // Click seeds: each fresh ripple plants a small crystal nucleus with its own hue.
    let nRipple = min(u32(u.config.y), 50u);
    for (var i = 0u; i < nRipple; i = i + 1u) {
      let rp = u.ripples[i];
      let ageR = time - rp.z;
      if (ageR > 0.0 && ageR < 0.25 && length(px - rp.xy * res) < 3.0) {
        st = vec4<f32>(1.0, 0.0, hash21(rp.xy * 97.0) * 0.8 + 0.1, f32(i % 7u) / 7.0);
      }
    }

    // Held mouse paints a seed line; attraction widens the brush.
    if (u.zoom_config.w > 0.5 && length(px - u.zoom_config.yz * res) < 2.0 + attract * 4.0) {
      st = vec4<f32>(1.0, 0.0, 0.55, 0.0);
    }
  }

  textureStore(dataTextureA, pixel, st);
}
