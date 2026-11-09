// ═══ SPH FLUID — RENDER (pixels) ═════════════════════════════════════════
//  Screen-space metaball render of the particle stamps (dataA → dataC barrier after the force pass)
//  over the source image. One 5 × 5 gather (taps about h / 2.5 apart) gives the coverage field T and,
//  with derivative-of-Gaussian weights, its gradient: the thickness and the surface normal of the
//  liquid at once (25 taps, not 125).
//    · lens refraction   — the image bends through each droplet along the thickness normal
//    · chrome rim        — a Fresnel edge and a specular highlight from a fixed light: liquid mercury
//    · swirl iridescence — the vorticity the force pass stamped shifts the tint, thin-film style
//    · foam front        — fast-moving surface particles whiten into spray
//  Then the stamp field fades into dataA (the next frame's force pass stamps on top: a short wake).
//  A/C packing (written by sph-fluid-force): .r speed / VMAX, .g vorticity tint, .b rho / rho0, .a coverage

#include "_prelude.wgsl"

struct SimParams {
  stateCount: u32,
  indexCount: u32,
  frame: u32,
  truncated: u32,
};

@group(1) @binding(2) var<uniform> simParams: SimParams;

const FADE: f32 = 0.55;   // stamp persistence per frame (the wake)

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv(h: f32, s: f32, v: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
  return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let ri = vec2<i32>(u.config.zw);
  if (gid.x >= u32(ri.x) || gid.y >= u32(ri.y)) { return; }
  let p = vec2<i32>(gid.xy);
  let res = vec2<f32>(ri);
  let uv = (vec2<f32>(p) + 0.5) / res;
  let time = u.config.x;
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let fresh = simParams.frame > 0u;   // frame 0: ignore whatever field the previous shader left

  // Kernel radius as in the solver: 0.98 of the smaller hash cell side (128 x 128 grid).
  let h = 0.98 * min(res.x, res.y) / 128.0;
  let spacing = max(1, i32(round(h / 2.5)));
  let hi = ri - vec2<i32>(1);

  var t = 0.0;
  var grad = vec2<f32>(0.0);
  var wsum = 0.0;
  var attr = vec3<f32>(0.0);
  for (var oy = -2; oy <= 2; oy = oy + 1) {
    for (var ox = -2; ox <= 2; ox = ox + 1) {
      let o = vec2<f32>(f32(ox), f32(oy));
      let w = exp(-dot(o, o) / 4.5);            // sigma = 1.5 taps
      var s = vec4<f32>(0.0);
      if (fresh) {
        s = textureLoad(dataTextureC, clamp(p + vec2<i32>(ox, oy) * spacing, vec2<i32>(0), hi), 0);
      }
      t = t + w * s.a;
      grad = grad + o * (w * s.a);             // derivative of Gaussian (up to -1 / sigma^2)
      wsum = wsum + w;
      attr = attr + w * s.a * s.rgb;
    }
  }
  t = t / wsum;
  grad = grad / (wsum * 2.25 * f32(spacing));   // per pixel (sigma^2 = 2.25 taps^2)
  attr = attr / max(t * wsum, 1e-4);
  let speed = attr.r;
  let swirl = attr.g - 0.5;

  // The liquid: coverage above ~0.4 of the kernel, with a soft meniscus.
  let body = smoothstep(0.32, 0.55, t);
  let n = normalize(vec3<f32>(-grad * h * 2.2, 1.0));   // height-field normal of the thickness bump

  // Lens refraction of the image through the droplet.
  let bend = n.xy * (0.012 + 0.02 * t);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let refr = textureSampleLevel(readTexture, u_sampler, clamp(uv + bend, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

  // Swirl iridescence + depth tint (thicker reads deeper).
  let tint = mix(vec3<f32>(0.55, 0.86, 1.0), hsv(fract(0.52 + swirl * 0.6 + time * 0.01), 0.65, 1.0),
                 clamp(abs(swirl) * 3.0, 0.0, 1.0));
  let depthT = clamp(t, 0.0, 1.5);
  let absorb = exp(-vec3<f32>(1.5, 0.6, 0.28) * depthT);
  var liquid = refr * tint * absorb + vec3<f32>(0.01, 0.06, 0.10) * depthT;

  // Chrome rim + specular.
  let l = normalize(vec3<f32>(-0.45, -0.6, 0.66));
  let rv = reflect(vec3<f32>(0.0, 0.0, -1.0), n);
  let spec = pow(max(dot(rv, l), 0.0), 48.0) * (1.2 + treble);
  let fres = pow(1.0 - n.z, 3.0);
  liquid = liquid + vec3<f32>(spec) + fres * mix(vec3<f32>(0.6, 0.78, 1.0), tint, 0.4) * 2.0;

  // Foam front: fast particles near the surface.
  let edge = 1.0 - smoothstep(0.55, 0.9, t);
  liquid = mix(liquid, vec3<f32>(0.95, 0.98, 1.0), clamp(speed * speed * 1.6 * edge * body, 0.0, 0.85));

  let bg = src * 0.82;
  let col = mix(bg, liquid, body);
  textureStore(writeTexture, p, vec4<f32>(aces(col * 1.05), 1.0));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, p, vec4<f32>(depth, 0.0, 0.0, 0.0));

  var keep = vec4<f32>(0.0);
  if (fresh) {
    keep = textureLoad(dataTextureC, p, 0);
    keep = vec4<f32>(keep.rgb, keep.a * FADE);
  }
  textureStore(dataTextureA, p, keep);
}
