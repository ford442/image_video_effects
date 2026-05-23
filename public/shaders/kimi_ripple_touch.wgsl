// ═══════════════════════════════════════════════════════════════════
//  Kimi Ripple Touch
//  Category: interactive-mouse
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: Very High
//  Scientific: Dispersive de Broglie-style wave packets use gravity-capillary group and phase velocities to spread interactive ripples with spectral interference.
//  Upgraded: 2026-05-23
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn clamp_uv(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn clamp_coord(c: vec2<i32>, max_coord: vec2<i32>) -> vec2<i32> {
  return clamp(c, vec2<i32>(0, 0), max_coord);
}

fn load_signed(coord: vec2<i32>, max_coord: vec2<i32>) -> vec4<f32> {
  let s = textureLoad(dataTextureC, clamp_coord(coord, max_coord), 0);
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

  for (var i: u32 = 0u; i < 50u; i = i + 1u) {
    let ripple = u.ripples[i];
    let src = vec2<f32>(ripple.x * aspect, ripple.y);
    let age = u.config.x - ripple.z;
    sourceTerm = sourceTerm + packet_source(pos, src, age, k0, amp0, sigma0, gravity, capillary);
  }

  sourceTerm = sourceTerm + packet_source(pos, mouse, 0.0, k0 * 1.1, amp0 * 1.4 * mouseDown, sigma0 * 0.7, gravity, capillary);
  let bassWave = packet_source(pos, vec2<f32>(0.5 * aspect, 0.5), max(u.config.x * 0.15, 0.0), 4.0 + bass * 5.0, 0.06 * bass, 0.18, gravity, capillary * 0.3);
  let trebleWave = packet_source(pos, mouse, 0.0, 22.0 + treble * 24.0, 0.04 * mouseDown + 0.03 * treble, 0.03, gravity * 0.6, capillary * 1.6);
  sourceTerm = sourceTerm + bassWave + trebleWave;

  let prevHeight = h - v * (1.0 / 60.0);
  let accel = lap * (0.25 * vg + 0.12 * vp) + sourceTerm - h * 0.018;
  var hNext = 2.0 * h - prevHeight + accel * (1.0 / 3600.0);
  hNext = hNext * 0.995;
  let vNext = clamp((hNext - h) * 60.0, -1.0, 1.0);

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

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  color = color * mix(0.75, 1.0, depth);
  let alpha = clamp(base.a * (0.86 + 0.14 * dot(color, vec3<f32>(0.299, 0.587, 0.114))) + abs(hNext) * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
  textureStore(dataTextureA, coord, vec4<f32>(
    clamp(hNext * 0.5 + 0.5, 0.0, 1.0),
    clamp(vNext * 0.5 + 0.5, 0.0, 1.0),
    clamp(vg / 2.5, 0.0, 1.0),
    clamp((phase / PI) * 0.5 + 0.5, 0.0, 1.0)
  ));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * 0.85 + abs(hNext) * 0.35 + slope * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
