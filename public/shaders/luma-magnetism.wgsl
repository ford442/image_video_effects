// ═══════════════════════════════════════════════════════════════════
//  Luma Magnetism
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: bidirectional RK2 streamlines; filings clump with field strength + bare pole caps; held magnet becomes a luma-signed pole
//  A packing: ACES display RGBA (same as writeTexture; C is not read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=FieldStrength, y=Radius, z=FilamentDensity, w=DepthLayer

const PI: f32 = 3.141592653589793;

// Per-invocation field setup shared by every streamline step
var<private> gAspect: f32 = 1.0;
var<private> gPole: f32 = 0.0;      // 0 = curl swirl, ±1 = radial source / sink

// ═══ CHUNK: aces_tonemap (standard) ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// ═══ CHUNK: sample_luma_polarity ═══
fn sampleLuma(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  return dot(c, vec3(0.299, 0.587, 0.114));
}

// ═══ CHUNK: magnetic_field_rk2 ═══
fn magneticField(pos: vec2<f32>, mouse: vec2<f32>, strength: f32, bass: f32) -> vec2<f32> {
  let ps = vec2(0.003, 0.003);
  let lumL = sampleLuma(pos + vec2(-ps.x, 0.0));
  let lumR = sampleLuma(pos + vec2( ps.x, 0.0));
  let lumUp = sampleLuma(pos + vec2(0.0, -ps.y));
  let lumDn = sampleLuma(pos + vec2(0.0,  ps.y));
  let grad = vec2(lumR - lumL, lumDn - lumUp) * 10.0;

  // Aspect-correct cursor term (computed in square space, returned in uv)
  let mouseDelta = vec2(pos.x - mouse.x, pos.y - mouse.y) * vec2(gAspect, 1.0);
  let mouseDist = length(mouseDelta);
  let swirl = vec2(-mouseDelta.y, mouseDelta.x);
  // Idea 3: a held magnet stops swirling and becomes a pole — radial source
  // over bright pixels (N), sink over dark ones (S).
  let dirField = mix(swirl, mouseDelta * gPole, abs(gPole));
  let mouseFieldSq = dirField * strength * (1.0 + bass) / max(mouseDist * mouseDist, 0.0001);
  return grad + vec2(mouseFieldSq.x / gAspect, mouseFieldSq.y);
}

fn rk2Step(pos: vec2<f32>, mouse: vec2<f32>, strength: f32, bass: f32, dt: f32) -> vec2<f32> {
  let k1 = magneticField(pos, mouse, strength, bass);
  let k2 = magneticField(pos + k1 * dt * 0.5, mouse, strength, bass);
  let stepV = k2 * dt;
  // Cap one step at 0.025 uv so the integrator does not jump across the core
  let stepLen = length(stepV);
  return pos + stepV * min(1.0, 0.025 / max(stepLen, 1e-6));
}

// ═══ CHUNK: field_line_density ═══
// Idea 1: bidirectional RK2 streamlines — trace the same field line forward and
// backward from the pixel, so every filament band is centred on the pixel's
// own field line instead of smeared downstream only.
fn fieldLineDensity(uv: vec2<f32>, mouse: vec2<f32>, strength: f32, bass: f32, halfSteps: i32) -> f32 {
  var density = 0.0;
  var posF = uv;
  var posB = uv;
  var aliveF = 1.0;
  var aliveB = 1.0;
  for (var i: i32 = 0; i < halfSteps; i = i + 1) {
    if (aliveF > 0.5) {
      posF = rk2Step(posF, mouse, strength, bass, 0.003);
      density = density + sampleLuma(posF) * 0.1;
      if (length(posF - uv) > 0.3) { aliveF = 0.0; }
    }
    if (aliveB > 0.5) {
      posB = rk2Step(posB, mouse, strength, bass, -0.003);
      density = density + sampleLuma(posB) * 0.1;
      if (length(posB - uv) > 0.3) { aliveB = 0.0; }
    }
  }
  return density;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let fieldStrength = u.zoom_params.x * 2.0 * (1.0 + bass * 0.5);
  let radius = max(u.zoom_params.y, 0.01);
  let filamentDensity = u.zoom_params.z * 5.0 + 1.0;
  let depthLayer = u.zoom_params.w;

  let aspect = resolution.x / resolution.y;
  gAspect = aspect;
  let diff = uv - mouse;
  let dist = length(vec2(diff.x * aspect, diff.y));

  // Idea 3: pole sign from the luma under the cursor (bright = N source, dark = S sink)
  let mouseLuma = sampleLuma(clamp(mouse, vec2(0.0), vec2(1.0)));
  let poleSign = select(-1.0, 1.0, mouseLuma >= 0.5);
  gPole = select(0.0, poleSign, u.zoom_config.w > 0.5);

  let luma = sampleLuma(uv);
  let polarity = (luma - 0.5) * 2.0;

  let field = magneticField(uv, mouse, fieldStrength, bass);
  let fieldMag = length(field);
  let fieldDir = field / max(fieldMag, 1e-5);   // NaN-safe normalize
  let disc = smoothstep(radius, 0.0, dist);

  let lineDensity = fieldLineDensity(uv, mouse, fieldStrength, bass, 4);

  // Idea 2: filings clump where the field is strong — bands get wider and
  // darker with |B|, thin and faint where it is weak.
  let clump = fieldMag / (fieldMag + 4.0);
  let bandWidth = mix(0.22, 0.7, clump);
  var filament = smoothstep(bandWidth, 0.0, abs(sin(lineDensity * filamentDensity * PI + depth * 6.2831853)))
               * disc;
  // Idea 2: bare pole caps — at luma extremes the filings stand off and leave
  // a clean polarity-coloured cap.
  let cap = smoothstep(0.82, 0.95, luma) + smoothstep(0.18, 0.05, luma);
  filament = filament * (1.0 - cap);

  let filingColor = vec3(0.15, 0.12, 0.10);
  let northColor = vec3(0.8, 0.2, 0.1);
  let southColor = vec3(0.1, 0.3, 0.8);
  let polarityColor = mix(southColor, northColor, polarity * 0.5 + 0.5);

  let bloom = fieldMag * 0.15 * disc;
  let hdrBloom = polarityColor * bloom * (1.0 + bass * 0.3);

  let filingGlow = filingColor * filament * (1.2 + 1.6 * clump);
  let capGlow = polarityColor * cap * disc * 0.3;

  let displacedUV = uv + fieldDir * fieldMag * 0.01 * disc;
  let displaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  let depthFade = mix(0.6, 1.0, depth * depthLayer);
  let filingMix = filament * mix(0.25, 0.55, clump);
  let emission_base = mix(displaced, polarityColor, filingMix) + hdrBloom + filingGlow + capGlow;
  let emission = emission_base * depthFade;
  let tonemapped = aces_tonemap(max(emission, vec3(0.0)));

  let noise = hash21(uv * 400.0) * 0.03;
  let alpha = clamp(filament * depth * 2.0 + bloom * depth * 3.0 + cap * disc * 0.5 + noise, 0.0, 1.0);
  let outCol = vec4(tonemapped, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), outCol);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), outCol);
}
