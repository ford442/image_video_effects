// ═══════════════════════════════════════════════════════════════════
//  Kimi Ripple Touch
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Very High
//  Scientific: Dispersive de Broglie-style wave packets use gravity-capillary group and phase velocities to spread interactive ripples with spectral interference.
//  Upgraded: 2026-11-10
//  Ideas: caustic focusing from surface curvature; low-sun specular glint; crest foam memory in A.b
//  A packing: raw sim state — r=h*0.5+0.5, g=v*0.5+0.5 (v = dh*8), b=crest foam, a=phase
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

fn clamp_uv(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn clamp_coord(c: vec2<i32>, max_coord: vec2<i32>) -> vec2<i32> {
  return clamp(c, vec2<i32>(0, 0), max_coord);
}

fn load_signed(coord: vec2<i32>, max_coord: vec2<i32>) -> vec4<f32> {
  let s = textureLoad(dataTextureC, clamp_coord(coord, max_coord), 0);
  // A zero-cleared history means "flat water", not h = v = -1 (HEAD decoded
  // the cleared texture as a full trough: a dark-blue wash for seconds).
  if (all(s == vec4<f32>(0.0))) {
    return vec4<f32>(0.0);
  }
  return vec4<f32>(s.r * 2.0 - 1.0, s.g * 2.0 - 1.0, s.b, s.a);
}

fn packet_source(pos: vec2<f32>, src: vec2<f32>, age: f32, k0: f32, amp: f32, sigma: f32, gravity: f32, capillary: f32) -> f32 {
  if (age < 0.0) {
    return 0.0;
  }
  let r = length(pos - src);
  let omega0 = sqrt(max(gravity * k0 + capillary * k0 * k0 * k0, 1e-4));
  let width = sigma + age * (0.03 + 0.04 * capillary * k0);
  let envelope = exp(-(r * r) / max(width * width, 1e-4));
  return amp * envelope * cos(k0 * r - omega0 * age) * exp(-age * 0.45);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= size.x || global_id.y >= size.y) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let maxCoord = vec2<i32>(i32(size.x) - 1, i32(size.y) - 1);
  let resolution = vec2<f32>(f32(size.x), f32(size.y));
  let uv = (vec2<f32>(f32(global_id.x), f32(global_id.y)) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let pos = vec2<f32>(uv.x * aspect, uv.y);
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);

  let state = load_signed(coord, maxCoord);
  let left = load_signed(coord + vec2<i32>(-1, 0), maxCoord).r;
  let right = load_signed(coord + vec2<i32>(1, 0), maxCoord).r;
  let up = load_signed(coord + vec2<i32>(0, -1), maxCoord).r;
  let down = load_signed(coord + vec2<i32>(0, 1), maxCoord).r;

  let h = state.r;
  let v = state.g;
  let foamPrev = state.b;
  let lap = left + right + up + down - 4.0 * h;
  let grad = vec2<f32>(right - left, down - up) * 0.5;
  let kLocal = clamp(6.0 + abs(lap) * 40.0 + treble * 28.0 + u.zoom_params.x * 12.0, 0.6, 72.0);
  let gravity = 0.24 + bass * 1.6;
  let capillary = 0.012 + treble * 0.11;
  let omega = sqrt(max(gravity * kLocal + capillary * kLocal * kLocal * kLocal, 1e-4));
  let vp = omega / max(kLocal, 1e-4);
  let vg = (gravity + 3.0 * capillary * kLocal * kLocal) / max(2.0 * omega, 1e-4);

  var sourceTerm = 0.0;
  let k0 = mix(8.0, 34.0, u.zoom_params.y) + treble * 18.0;
  let sigma0 = mix(0.02, 0.09, u.zoom_params.z);
  let amp0 = mix(0.04, 0.16, u.zoom_params.w);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let src = vec2<f32>(ripple.x * aspect, ripple.y);
    let age = u.config.x - ripple.z;
    sourceTerm = sourceTerm + packet_source(pos, src, age, k0, amp0, sigma0, gravity, capillary);
  }

  sourceTerm = sourceTerm + packet_source(pos, mouse, 0.0, k0 * 1.1, amp0 * 1.4 * mouseDown, sigma0 * 0.7, gravity, capillary);
  // HEAD aged this packet by time*0.15 forever, so it died after ~a minute;
  // re-launch it every 8 s instead.
  let bassWave = packet_source(pos, vec2<f32>(0.5 * aspect, 0.5), fract(u.config.x * 0.125) * 1.2, 4.0 + bass * 5.0, 0.06 * bass, 0.18, gravity, capillary * 0.3);
  let trebleWave = packet_source(pos, mouse, 0.0, 22.0 + treble * 24.0, 0.04 * mouseDown + 0.03 * treble, 0.03, gravity * 0.6, capillary * 1.6);
  sourceTerm = sourceTerm + bassWave + trebleWave;

  // Rescue: HEAD scaled the whole update by 1/3600 (dt^2 with c ~0.2), so
  // waves never left the pixel and h settled near 0.004 — a passthrough.
  // Keep the dispersive local speed, but as a CFL-bounded c^2 per frame.
  let prevHeight = h - v * (1.0 / 8.0);
  let c2 = clamp(0.25 * vg + 0.12 * vp, 0.02, 0.45);
  let accel = lap * c2 + sourceTerm * 0.12 - h * 0.002;
  var hNext = 2.0 * h - prevHeight + accel;
  hNext = clamp(hNext * 0.99, -1.0, 1.0);
  let vNext = clamp((hNext - h) * 8.0, -1.0, 1.0);

  let kR = kLocal * 0.78;
  let kG = kLocal;
  let kB = kLocal * 1.22;
  let omegaR = sqrt(max(gravity * kR + capillary * kR * kR * kR, 1e-4));
  let omegaG = sqrt(max(gravity * kG + capillary * kG * kG * kG, 1e-4));
  let omegaB = sqrt(max(gravity * kB + capillary * kB * kB * kB, 1e-4));
  let vgR = (gravity + 3.0 * capillary * kR * kR) / max(2.0 * omegaR, 1e-4);
  let vgG = (gravity + 3.0 * capillary * kG * kG) / max(2.0 * omegaG, 1e-4);
  let vgB = (gravity + 3.0 * capillary * kB * kB) / max(2.0 * omegaB, 1e-4);

  let disp = grad * vec2<f32>(1.0 / aspect, 1.0) * 0.18;
  let uvR = clamp_uv(uv + disp * vgR * 0.3);
  let uvG = clamp_uv(uv + disp * vgG * 0.3);
  let uvB = clamp_uv(uv + disp * vgB * 0.3);
  let base = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv), 0.0);
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );

  // Idea 1: caustic focusing — a convex crest (lap < 0) acts as a lens and
  // concentrates sunlight on the photo below; troughs spread it thin.
  let caustic = clamp(-lap * 30.0, -0.45, 1.4);
  color = color * (1.0 + caustic) + vec3<f32>(0.9, 0.95, 1.0) * max(caustic - 0.6, 0.0) * 0.35;

  // Idea 2: low-sun specular glint off the surface normal (grad of h);
  // treble tightens the lobe into sparkles.
  let nrm = normalize(vec3<f32>(-grad * 30.0, 1.0));
  let halfV = normalize(normalize(vec3<f32>(-0.6, -0.8, 0.6)) + vec3<f32>(0.0, 0.0, 1.0));
  let glint = pow(max(dot(nrm, halfV), 0.0), 36.0 + treble * 200.0) * (1.4 + treble);

  let phase = atan2(vNext, hNext + 1e-4);
  let slope = clamp(length(grad) * 18.0, 0.0, 1.0);
  let peak = smoothstep(0.01, 0.09, hNext);
  let trough = smoothstep(0.01, 0.09, -hNext);
  var phaseColor = mix(vec3<f32>(0.02, 0.07, 0.22), vec3<f32>(0.15, 0.78, 0.95), slope);
  phaseColor = mix(phaseColor, vec3<f32>(1.0, 0.97, 0.92), peak);
  phaseColor = mix(phaseColor, vec3<f32>(0.02, 0.05, 0.3), trough);
  phaseColor = phaseColor + vec3<f32>(1.0, 0.55, 0.15) * slope * (0.5 + 0.5 * sin(phase + 1.2));
  color = mix(color, phaseColor, clamp(abs(hNext) * 4.0 + slope * 0.35, 0.0, 0.75));
  color = mix(color, base.rgb, 0.18);
  color = color + vec3<f32>(1.0, 0.95, 0.85) * glint;

  // Idea 3: crest foam memory — steep crests break into white foam that
  // stays where the wave broke and fades over ~1 s (A.b, unread at HEAD).
  let crest = smoothstep(0.05, 0.14, hNext) * smoothstep(0.1, 0.45, slope);
  let foam = clamp(max(foamPrev * 0.965, crest), 0.0, 1.0);
  color = mix(color, vec3<f32>(0.95, 0.98, 1.0), foam * 0.75);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  color = color * mix(0.75, 1.0, depth);
  let alpha = clamp(base.a * (0.86 + 0.14 * dot(color, vec3<f32>(0.299, 0.587, 0.114))) + abs(hNext) * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
  textureStore(dataTextureA, coord, vec4<f32>(
    clamp(hNext * 0.5 + 0.5, 0.0, 1.0),
    clamp(vNext * 0.5 + 0.5, 0.0, 1.0),
    foam,
    clamp((phase / PI) * 0.5 + 0.5, 0.0, 1.0)
  ));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * 0.85 + abs(hNext) * 0.35 + slope * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
