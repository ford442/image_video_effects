// ═══════════════════════════════════════════════════════════════════
//  Plasma Mandala
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-10-25
//  Ideas: diocotron ring; dihedral click pulses; petal-midline current filaments; Debye sheath gap; X-point reconnection; density cavity
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Symmetry, y=Spin Speed, z=Zoom, w=Glow Scale

// 2D hash
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Smooth noise
fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// FBM for plasma texture
fn fbm2(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var amp = 0.5;
  var pp = p;
  for (var i = 0u; i < 5u; i++) {
    v += amp * noise2(pp);
    pp *= 2.0;
    amp *= 0.5;
  }
  return v;
}

// Plasma function — sum of trig waves
fn plasma(p: vec2<f32>, t: f32, mids: f32) -> f32 {
  let s1 = sin(p.x * 3.0 + t * 1.1);
  let s2 = sin(p.y * 3.0 + t * 0.9);
  let s3 = sin((p.x + p.y) * 2.0 + t * 1.3);
  let r = length(p);
  let s4 = sin(r * 5.0 - t * 2.0 + mids * 1.5);
  return 0.25 * (s1 + s2 + s3 + s4);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

  let t = u.config.x;
  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // Parameters
  let symmetry   = mix(3.0,  12.0, u.zoom_params.x); // petal count
  let spin_speed = mix(0.1,   1.0, u.zoom_params.y) * (1.0 + bass * 0.4);
  let zoom_amt   = mix(0.5,   3.0, u.zoom_params.z);
  let glow_scale = mix(0.5,   3.0, u.zoom_params.w) * (1.0 + mids * 0.3);

  // Mouse influence — pull center toward cursor
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouse_pull = mouse * 0.3 * u.zoom_config.w;

  // Center-relative coords, aspect-corrected
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p = p - mouse_pull;

  // Radial mandala: fold into one petal via angular repeat
  let angle = atan2(p.y, p.x);
  let r = length(p) * zoom_amt;

  // Quantise angle to symmetry sectors and mirror within each sector
  let sector_angle = 3.14159265 / symmetry;
  let folded_angle = abs(fract(angle / (2.0 * sector_angle) + 0.5) * 2.0 * sector_angle - sector_angle);
  let seam = exp(-folded_angle * 22.0);

  let spin = t * spin_speed;
  let px = r * cos(folded_angle + spin);
  let py = r * sin(folded_angle + spin);
  let mp = vec2<f32>(px, py);

  let plasma_val = plasma(mp, t - r * 1.15, mids);

  // FBM detail layer
  let detail = fbm2(mp * 3.0 + vec2<f32>(t * 0.2, t * 0.15));

  // Combine for richness
  let field = plasma_val * 0.6 + detail * 0.4;

  // Hue cycling — audio-driven shift
  let hue_base = fract(field * 0.5 + t * 0.07 + bass * 0.2);
  let hue2 = fract(hue_base + 0.33);
  let hue3 = fract(hue_base + 0.67);

  var col = vec3<f32>(
    0.5 + 0.5 * cos(6.2832 * hue_base),
    0.5 + 0.5 * cos(6.2832 * hue2),
    0.5 + 0.5 * cos(6.2832 * hue3)
  );

  // Radial vignette and glow ring
  let vignette = 1.0 - smoothstep(0.6, 1.4, r);

  // Idea 1 — diocotron instability: the glow ring is a hollow plasma column whose
  // edge develops azimuthal modes. The mode is locked to the petal group (one
  // full wavelength per mirrored sector => l = symmetry), rotates with the E x B
  // drift (spin), and its amplitude grows with bass like an unstable eigenmode.
  let sector_phase = folded_angle / sector_angle;               // 0..1 across a half-petal, mirror-continuous
  let dioco_amp = 0.035 * (0.35 + bass * 0.9);
  let dioco = dioco_amp * cos(sector_phase * 3.14159265 * 2.0 + spin * 1.7 - t * 0.6)
            + dioco_amp * 0.35 * cos(sector_phase * 3.14159265 * 4.0 - t * 1.1);  // first harmonic roll-up
  let ring_r = 0.5 + dioco;
  let ring_glow = exp(-abs(r - ring_r) * 6.0) * glow_scale;
  let vortex_core = exp(-abs(r - ring_r) * 28.0) * smoothstep(0.2, 1.0, cos(sector_phase * 3.14159265 * 2.0 + spin * 1.7 - t * 0.6) * 0.5 + 0.5);

  // Idea 2 — dihedral click pulses: each ripple origin is folded into the same
  // D_n fundamental domain as the pixel, so one click echoes in every petal.
  var pulse = 0.0;
  let q_local = vec2<f32>(r * cos(folded_angle), r * sin(folded_angle));
  let ripple_count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let rip = u.ripples[i];
    let age = t - rip.z;
    if (age >= 0.0 && age < 2.5) {
      let rp = (rip.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0) - mouse_pull;
      let rr = length(rp) * zoom_amt;
      let ra = atan2(rp.y, rp.x);
      let rfa = abs(fract(ra / (2.0 * sector_angle) + 0.5) * 2.0 * sector_angle - sector_angle);
      let rq = vec2<f32>(rr * cos(rfa), rr * sin(rfa));
      let d = length(q_local - rq);
      let front = age * 0.9;
      pulse += exp(-abs(d - front) * 18.0) * exp(-age * 1.6);
    }
  }
  pulse = min(pulse, 2.0);

  col = col * vignette + vec3<f32>(ring_glow * 0.3 * (1.0 + treble * 0.5));
  // Idea: current filaments down the petal midline (the seam is the mirror edge, folded_angle ≈ 0).
  let filament = exp(-abs(folded_angle - sector_angle) * 36.0) * smoothstep(0.12, 0.4, r) * exp(-r * 0.35);
  col += vec3<f32>(0.65, 0.86, 1.0) * filament * (0.18 + treble * 0.35) * glow_scale * 0.22;
  // Idea: Debye sheath — a dark gap just inside the glow ring.
  let sheath = exp(-abs(r - (ring_r - 0.055)) * 42.0);
  col *= 1.0 - sheath * 0.42 * (0.6 + bass * 0.4);
  // ── Idea: X-point reconnection ──
  // The filament and the diocotron ring already exist. Their crossing flashes.
  let xpoint = filament * exp(-abs(r - ring_r) * 24.0);
  col += vec3<f32>(1.0, 0.95, 0.82) * xpoint * (0.4 + mids * 0.45) * glow_scale;
  // ── Idea: density cavity ──
  // Plasma expelled just outside the column. The sheath stays the inner gap.
  let cavity = exp(-abs(r - (ring_r + 0.08)) * 28.0) * (1.0 - seam);
  col *= 1.0 - cavity * 0.32;
  col += vec3<f32>(1.0, 0.92, 0.85) * seam * 0.28 * (0.6 + treble * 0.4);
  col += vec3<f32>(0.55, 0.85, 1.0) * vortex_core * 0.22 * (0.5 + bass * 0.8) * glow_scale;
  col += (vec3<f32>(1.0) - col * 0.5) * pulse * 0.45 * (0.8 + treble * 0.4);

  let spark = hash21(uv + vec2<f32>(t * 0.01)) * treble * 0.15;
  col += spark;

  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let mouse_influence = length(mouse_pull) * 0.3;
  let alpha = clamp(luma * 0.7 + ring_glow * 0.2 + mouse_influence * 0.1 + seam * 0.15 + pulse * 0.25 + vortex_core * 0.1, 0.0, 1.0);
  let depth = clamp(1.0 - r * 0.5, 0.0, 1.0);

  let mapped = acesToneMap(col * glow_scale * 1.05);
  let final_color = vec4<f32>(mapped, alpha);
  textureStore(writeTexture,      coord, final_color);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, final_color);
}
