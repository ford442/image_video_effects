// ═══════════════════════════════════════════════════════════════════
//  Circuit Breaker Explosion
//  Category: advanced-hybrid
//  Features: mouse-driven, chromatic, circuit-simulation, glitch, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-01
//  Ideas: voltage drop along the trace; contact latch from C.a
//  A packing: A.rgb ACES display; A.a contact latch
// ═══════════════════════════════════════════════════════════════════
//  Circuit board edges and grid lines are chromatically separated
//  near the mouse prism. Overload flashes become spectral rainbows.
//  Click ripples launch chromatic shockwaves that distort the
//  circuit pattern and scatter channels.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=GridScale, y=Intensity, z=Jitter, w=PrismStrength

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// ═══ CHUNK: prismDisplace (from mouse-chromatic-explosion.wgsl) ═══
fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let time = u.config.x;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;

  // Parameters
  let gridScale = mix(20.0, 100.0, u.zoom_params.x);
  let intensity = u.zoom_params.y;
  let jitterStrength = u.zoom_params.z;
  let prismStrength = mix(0.02, 0.12, u.zoom_params.w);
  let dispersion = 2.0;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // ── Chromatic Prism Offsets (from mouse-chromatic-explosion) ──
  let rUV = prismDisplace(uv, mousePos, -1.0 * dispersion, prismStrength);
  let gUV = prismDisplace(uv, mousePos, 0.0, prismStrength);
  let bUV = prismDisplace(uv, mousePos, 1.0 * dispersion, prismStrength);

  // Ripple chromatic shockwaves
  let rippleCount = min(u32(u.config.y), 50u);
  var rOffset = vec2<f32>(0.0);
  var gOffset = vec2<f32>(0.0);
  var bOffset = vec2<f32>(0.0);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rOffset = rOffset + dir * rWave * 0.03;
      gOffset = gOffset + dir * wave * 0.03;
      bOffset = bOffset + dir * bWave * 0.03;
    }
  }

  let prismIntensity = 1.0 + mouseDown * 1.5;

  // ── Circuit Breaker Logic (from circuit-breaker) ──
  let aspectRatio = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspectRatio, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspectRatio, mousePos.y);
  let mouseDist = distance(uv_corrected, mouse_corrected);

  let hasMouse = step(0.001, mousePos.x + mousePos.y);
  let influence = smoothstep(0.4, 0.0, mouseDist) * hasMouse * (1.0 + intensity * 2.0);

  // Grid generation
  let gridUV = uv * gridScale;
  let gridID = floor(gridUV);
  let gridLine = smoothstep(0.95, 1.0, fract(gridUV.x)) + smoothstep(0.95, 1.0, fract(gridUV.y));
  let isGrid = clamp(gridLine, 0.0, 1.0);

  // Circuit nodes
  let node = step(0.9, hash21(gridID));

  let jitter = (vec2<f32>(hash21(uv + time), hash21(uv + time + 10.0)) - 0.5) * jitterStrength * influence * 0.1 * step(0.1, influence);
  let sampleUV = uv + jitter;
  let coord = vec2<i32>(global_id.xy);
  let prevLatch = textureLoad(dataTextureC, coord, 0).a;

  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(rUV + rOffset * prismIntensity + (sampleUV - uv), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let gSample = textureSampleLevel(readTexture, u_sampler, clamp(gUV + gOffset * prismIntensity + (sampleUV - uv), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(bUV + bOffset * prismIntensity + (sampleUV - uv), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  var color = vec3<f32>(rSample.r, gSample.g, bSample.b);

  // Edge detection on chromatically-separated samples
  let offset = 1.0 / resolution;
  let left = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let up = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let down = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let lumaL = dot(left.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumaR = dot(right.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumaU = dot(up.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let lumaD = dot(down.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let edgeX = lumaL - lumaR;
  let edgeY = lumaU - lumaD;
  let edge = sqrt(edgeX * edgeX + edgeY * edgeY);

  var finalColor = color;
  let edgeThreshold = 0.1;
  let isEdge = step(edgeThreshold, edge);

  // Spectral circuit colors instead of plain green
  let hue = atan2(uv.y - mousePos.y, uv.x - mousePos.x) * 0.159 + 0.5 + time * 0.2;
  let spectralColor = vec3<f32>(
    0.5 + 0.5 * cos(hue * 6.28),
    0.5 + 0.5 * cos(hue * 6.28 + 2.09),
    0.5 + 0.5 * cos(hue * 6.28 + 4.18)
  );
  let overloadColor = vec3<f32>(1.0, 0.9, 0.7);

  // ── Idea 1: voltage drop. Overload shallows the falloff along the trace.
  let drop = exp(-mouseDist * mix(7.0, 1.6, clamp(intensity, 0.0, 1.0)));
  let trace = max(isEdge, isGrid);
  let traceGlow = mix(spectralColor, overloadColor, influence) * mix(0.25, 1.0, drop);
  finalColor = mix(finalColor, traceGlow, trace * (0.5 + influence * 0.5));

  // ── Idea 2: contact latch (§12.2B). Holds between the thresholds, releases outside.
  let drive = influence * node;
  var latch = step(0.5, prevLatch);
  latch = select(latch, 1.0, drive > 0.72);
  latch = select(latch, 0.0, drive < 0.28);
  let chatter = latch * (0.72 + 0.28 * sin(time * 14.0 + hash21(gridID) * 6.28));
  finalColor = mix(finalColor, spectralColor, chatter * step(0.5, node));

  // Scanline effect
  let scanline = sin(uv.y * resolution.y * 0.5) * 0.1;
  finalColor = finalColor - scanline;

  // Spectral glow near mouse
  let mouseGlow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  finalColor = finalColor + spectralColor * mouseGlow * 0.5;

  // Alpha = total chromatic displacement magnitude
  let totalDisp = length(rUV - gUV) + length(gUV - bUV) + length(rOffset) + length(gOffset) + length(bOffset);
  let alpha = clamp(totalDisp * 3.0 + trace * 0.45 + latch * 0.25, 0.0, 1.0);
  let display = acesToneMap(max(finalColor, vec3<f32>(0.0)));

  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(display, latch));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
