// ═══ MURMURATION — RENDER ═════════════════════════════════════════════════
//  Reads the stamped field (dataA → dataC barrier after the flock pass),
//  blurs and fades it into the next trail field (dataA), and composites it
//  over a dusk sky made from the source image:
//    · murmur silhouette   — a flock is dark against a sunset: crowded birds smoke the sky they fly over
//    · iridescent rim      — heading-tinted light on the flock's edges and fading wake (Trail Length)
//    · chromatic wake      — red / blue taps split along the radial direction
//  A/C packing: .rgb emission, .a energy
//  zoom_params: .w trail length

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn fieldAt(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
}

/// Smooth density of the painted field: 5×5 taps two texels apart. .rgb is the heading tint, .a the crowding.
fn density(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> {
  var sum = vec4<f32>(0.0);
  for (var dy = -2; dy <= 2; dy = dy + 1) {
    for (var dx = -2; dx <= 2; dx = dx + 1) {
      sum = sum + fieldAt(p + vec2<i32>(dx, dy) * 2, hi);
    }
  }
  return sum / 25.0;
}

fn sunset(uv: vec2<f32>, time: f32) -> vec3<f32> {
  let top = vec3<f32>(0.16, 0.12, 0.42);
  let mid = vec3<f32>(0.78, 0.34, 0.50);
  let low = vec3<f32>(1.00, 0.72, 0.36);
  let t = clamp(uv.y, 0.0, 1.0);
  var sky = mix(top, mid, smoothstep(0.0, 0.6, t));
  sky = mix(sky, low, smoothstep(0.55, 1.0, t));
  let band = 0.5 + 0.5 * sin(uv.x * 3.0 + sin(uv.y * 4.0 + time * 0.05) * 1.5 + time * 0.04);
  return sky * (0.85 + 0.3 * band);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let ri = vec2<i32>(u.config.zw);
  if (gid.x >= u32(ri.x) || gid.y >= u32(ri.y)) { return; }
  let hi = ri - vec2<i32>(1);
  let p = vec2<i32>(gid.xy);
  let res = vec2<f32>(ri);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // Soft diffusion of the stamped sparks, then the fade (this is the field the next frame reads).
  var sum = fieldAt(p, hi) * 0.28;
  sum = sum + (fieldAt(p + vec2<i32>(1, 0), hi) + fieldAt(p - vec2<i32>(1, 0), hi)
             + fieldAt(p + vec2<i32>(0, 1), hi) + fieldAt(p - vec2<i32>(0, 1), hi)) * 0.12;
  sum = sum + (fieldAt(p + vec2<i32>(1, 1), hi) + fieldAt(p - vec2<i32>(1, 1), hi)
             + fieldAt(p + vec2<i32>(1, -1), hi) + fieldAt(p + vec2<i32>(-1, 1), hi)) * 0.06;
  let keep = mix(0.84, 0.985, u.zoom_params.w);
  textureStore(dataTextureA, p, min(sum * keep, vec4<f32>(4.0)));

  // Density of the flock's body, and its gradient: the rim light lives on the boundary, never inside.
  let near = density(p, hi);
  let grad = vec2<f32>(
    density(p + vec2<i32>(7, 0), hi).a - density(p - vec2<i32>(7, 0), hi).a,
    density(p + vec2<i32>(0, 7), hi).a - density(p - vec2<i32>(0, 7), hi).a,
  );
  // A uniform scatter paints crowding near 0.25: a thin haze. Clumps run to 1, voids to 0.
  let e = clamp(near.a * 3.5, 0.0, 1.0);
  let edge = clamp(length(grad) * 3.0, 0.0, 1.0);

  // Heading tint at full brightness; its red / blue taps split along the radial direction (chromatic wake).
  let radial = uv - vec2<f32>(0.5);
  let dir = select(vec2<i32>(1, 0), vec2<i32>(round(normalize(radial + vec2<f32>(1e-6)) * (2.0 + bass * 4.0))), dot(radial, radial) > 1e-6);
  let tintR = density(p + dir, hi).r;
  let tintB = density(p - dir, hi).b;
  let tintRaw = vec3<f32>(tintR, near.g, tintB);
  let tint = tintRaw / max(max(tintRaw.r, max(tintRaw.g, tintRaw.b)), 1e-4);

  let src = textureLoad(readTexture, p, 0).rgb;
  let sky = sunset(uv, time);
  var col = mix(sky, sky * 0.5 + src * 0.6, 0.45) * 0.85;
  // The flock itself: ink tinted by heading, darkest where the birds are most crowded.
  let ink = tint * 0.10 + vec3<f32>(0.03, 0.015, 0.07);
  col = mix(col, ink, 0.96 * smoothstep(0.30, 0.75, e));
  // Iridescent rim light on the flock's edge, and a faint haze of its wake in the sky.
  col = col + tint * (edge * (1.1 + treble * 0.9) + 0.12 * clamp(near.a * 6.0, 0.0, 1.0) * (1.0 - e));

  textureStore(writeTexture, p, vec4<f32>(aces(col), 1.0));
}
