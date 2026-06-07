// ═══════════════════════════════════════════════════════════════════
//  Holographic Membrane
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Description: Thin-film interference membrane that undulates in space.
//    Alpha encodes membrane depth — peaks are opaque, troughs transparent.
//    Audio drives vibration and iridescence; mouse controls viewing angle
//    for rainbow interference patterns. Temporal feedback smooths motion.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Thickness, y=Frequency, z=Amplitude, w=Iridescence
  ripples: array<vec4<f32>, 50>,
};

// ── Value noise ───────────────────────────────────────────────────
fn hash3(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash3(i + vec2<f32>(0.0, 0.0)), hash3(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash3(i + vec2<f32>(0.0, 1.0)), hash3(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm_mem(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 4; i++) {
    v += a * vnoise2(pp);
    pp = pp * 2.1 + vec2<f32>(3.1, 1.7);
    a *= 0.5;
  }
  return v;
}

fn fbm_mem_detail(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 3; i++) {
    v += a * vnoise2(pp);
    pp = pp * 2.5 + vec2<f32>(5.3, 2.9);
    a *= 0.5;
  }
  return v;
}

// ── Thin-film interference ────────────────────────────────────────
fn thinFilmIridescence(cosTheta: f32, thickness: f32, filmIOR: f32) -> vec3<f32> {
  // Phase shift for constructive/destructive interference
  let opticalPath = 2.0 * filmIOR * thickness * sqrt(1.0 - (1.0 - cosTheta * cosTheta) / (filmIOR * filmIOR));
  let phase = opticalPath * 6.28318;

  // Different wavelengths construct at different phases
  let r = 0.5 + 0.5 * cos(phase);
  let g = 0.5 + 0.5 * cos(phase * 0.97 + 1.0);
  let b = 0.5 + 0.5 * cos(phase * 0.94 + 2.0);
  return vec3<f32>(r, g, b);
}

fn thinFilmIridescence2(cosTheta: f32, thickness: f32, filmIOR: f32, shift: f32) -> vec3<f32> {
  let opticalPath = 2.0 * filmIOR * thickness * sqrt(max(1.0 - (1.0 - cosTheta * cosTheta) / (filmIOR * filmIOR), 0.0));
  let phase = opticalPath * 6.28318 + shift;
  let r = 0.5 + 0.5 * cos(phase * 1.02);
  let g = 0.5 + 0.5 * cos(phase * 0.98 + 0.5);
  let b = 0.5 + 0.5 * cos(phase * 0.95 + 1.5);
  return vec3<f32>(r, g, b);
}

// ── Audio smoothing ───────────────────────────────────────────────
fn env_smooth(prev: f32, val: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, val > prev);
  return mix(prev, val, k);
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let uv = vec2<f32>(gid.xy) / res;
  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rms = plasmaBuffer[0].w;

  // Mouse controls viewing angle
  let mouse = u.zoom_config.yz;
  let mPos = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDown = u.zoom_config.w > 0.5;

  // Parameters
  let thicknessBase = u.zoom_params.x * 800.0 + 200.0;   // nm
  let freq = u.zoom_params.y * 3.0 + 1.0;
  let amplitude = u.zoom_params.z * 0.3 + 0.05;
  let iridescence = u.zoom_params.w;

  // Audio-reactive modulation
  let midsSmooth = env_smooth(0.5, mids, 0.12, 0.06);
  let trebleSmooth = env_smooth(0.3, treble, 0.15, 0.08);
  let bassSmooth = env_smooth(0.4, bass, 0.1, 0.05);

  // ── Temporal feedback for membrane persistence ──────────────────
  let prevFrame = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  let prevDepth = prevFrame.r;
  let prevNormal = vec2<f32>(prevFrame.g, prevFrame.b);

  // ── Procedural membrane mesh ────────────────────────────────────
  // Base undulation from sine waves
  let wave1 = sin(p.x * freq * 6.28318 + time * 1.5 * (1.0 + midsSmooth * 2.0));
  let wave2 = sin(p.y * freq * 4.0 + time * 1.2 + 1.0);
  let wave3 = sin((p.x + p.y) * freq * 3.0 - time * 0.8);
  let wave4 = cos(p.x * freq * 2.0 - p.y * freq * 2.5 + time * 0.6);

  // FBM detail for organic surface
  let detail = fbm_mem(p * 3.0 + time * 0.2) * 2.0 - 1.0;
  let fineDetail = fbm_mem_detail(p * 7.0 - time * 0.15) * 2.0 - 1.0;

  // Membrane height field
  var membraneZ = (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2) * amplitude;
  membraneZ += wave4 * amplitude * 0.15;
  membraneZ += detail * amplitude * 0.3;
  membraneZ += fineDetail * amplitude * 0.1;

  // Audio vibration
  membraneZ += sin(time * 10.0 * (1.0 + midsSmooth)) * amplitude * midsSmooth * 0.5;
  membraneZ += sin(time * 15.0 + length(p) * 5.0) * amplitude * trebleSmooth * 0.2;

  // Mouse interaction: depression / bulge
  let mouseDist = length(p - mPos);
  let mouseInfluence = exp(-mouseDist * 3.0) * 0.2;
  let mouseDisplacement = select(-mouseInfluence, mouseInfluence, mouseDown);
  membraneZ += mouseDisplacement;

  // Mouse-driven ripple on membrane
  let mouseRipple = sin(mouseDist * 20.0 - time * 4.0) * exp(-mouseDist * 2.0) * 0.03;
  membraneZ += mouseRipple;

  // Temporal smoothing
  membraneZ = mix(membraneZ, prevDepth * 2.0 - 1.0, 0.15);

  // ── Viewing angle for interference ──────────────────────────────
  // Mouse position shifts the apparent light source / view angle
  let viewShift = mPos * 0.5;
  let viewDir = normalize(vec3<f32>(viewShift.x, viewShift.y, 1.0));

  // Surface normal from height field gradient
  let eps = 0.01;
  let dx = sin((p.x + eps) * freq * 6.28318 + time * 1.5) - sin((p.x - eps) * freq * 6.28318 + time * 1.5);
  let dy = sin((p.y + eps) * freq * 4.0 + time * 1.2) - sin((p.y - eps) * freq * 4.0 + time * 1.2);
  var normal = normalize(vec3<f32>(-dx * amplitude * 5.0, -dy * amplitude * 5.0, 1.0));

  // Blend with temporal normal for smoother shading
  normal = normalize(vec3<f32>(
    mix(normal.x, prevNormal.x, 0.1),
    mix(normal.y, prevNormal.y, 0.1),
    normal.z
  ));

  let cosTheta = abs(dot(normal, viewDir));

  // ── Thin-film interference coloring ─────────────────────────────
  let filmThickness = thicknessBase * (1.0 + membraneZ * 2.0) * (1.0 + rms * 0.3);
  let filmIOR = 1.33 + midsSmooth * 0.1;
  var interferenceCol = thinFilmIridescence(cosTheta, filmThickness, filmIOR);

  // Iridescence speed driven by treble
  let iridTime = time * (1.0 + trebleSmooth * 3.0) * iridescence;
  interferenceCol = interferenceCol * 0.5 + 0.5 * thinFilmIridescence(
    cosTheta + sin(iridTime) * 0.1,
    filmThickness * (1.0 + sin(iridTime * 0.7) * 0.2),
    filmIOR
  );

  // Secondary interference layer for richer color
  let interferenceCol2 = thinFilmIridescence2(
    cosTheta + bassSmooth * 0.05,
    filmThickness * 0.7 * (1.0 + cos(iridTime * 0.5) * 0.15),
    filmIOR * 0.95,
    iridTime * 0.3
  );
  interferenceCol = mix(interferenceCol, interferenceCol2, 0.3);

  // Rainbow holographic sheen
  let sheen = pow(1.0 - cosTheta, 3.0);
  let sheenHue = fract(length(p) * 0.5 - iridTime * 0.1 + membraneZ);
  let sheenCol = 0.5 + 0.5 * cos(vec3<f32>(sheenHue * 6.28318) + vec3<f32>(0.0, 2.094, 4.189));
  interferenceCol += sheenCol * sheen * 0.4;

  // Specular highlight
  let halfDir = normalize(viewDir + vec3<f32>(0.0, 0.0, 1.0));
  let spec = pow(max(dot(normal, halfDir), 0.0), 64.0);
  let spec2 = pow(max(dot(normal, halfDir), 0.0), 16.0) * 0.3;
  interferenceCol += vec3<f32>(spec * 0.6 + spec2 * 0.2);

  // Background bleed-through where membrane is thin
  let bgColor = vec3<f32>(0.02, 0.03, 0.05);
  var col = mix(bgColor, clamp(interferenceCol, vec3<f32>(0.0), vec3<f32>(1.0)), 0.85);

  // Vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.3;
  col *= vignette;

  col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.4545));

  // ── Alpha encoding ──────────────────────────────────────────────
  // Alpha = membrane depth: peaks (high Z) = opaque, troughs (low Z) = transparent
  let depthNorm = clamp(membraneZ / amplitude * 0.5 + 0.5, 0.0, 1.0);
  let peakAlpha = smoothstep(0.3, 0.7, depthNorm);
  let troughAlpha = smoothstep(0.7, 0.3, depthNorm) * 0.15;
  var alpha = peakAlpha * 0.92 + troughAlpha + sheen * 0.3;

  // Thin areas become more translucent
  let thinness = abs(membraneZ) / (amplitude + 0.01);
  alpha = mix(alpha * 0.5, alpha, smoothstep(0.0, 0.5, thinness));

  // Audio-reactive transparency in troughs
  alpha = mix(alpha, alpha * (1.0 - bassSmooth * 0.3), smoothstep(0.5, 0.0, depthNorm));

  alpha = clamp(alpha, 0.05, 0.95);

  let outCol = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture, gid.xy, outCol);
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(depthNorm, normal.x, normal.y, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthNorm, 0.0, 0.0, 0.0));
}
