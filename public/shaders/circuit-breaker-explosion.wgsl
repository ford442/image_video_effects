// ═══════════════════════════════════════════════════════════════════
//  Circuit Breaker Explosion
//  Category: advanced-hybrid
//  Features: mouse-driven, chromatic, circuit-simulation, glitch
//  Complexity: High
//  Chunks From: circuit-breaker.wgsl, mouse-chromatic-explosion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-9
// ═══════════════════════════════════════════════════════════════════
//  Circuit board edges and grid lines are chromatically separated
//  near the mouse prism. Overload flashes become spectral rainbows.
//  Click ripples launch chromatic shockwaves that distort the
//  circuit pattern and scatter channels.
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GridScale, y=Intensity, z=Jitter, w=PrismStrength
  ripples: array<vec4<f32>, 50>,
};

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

@compute @workgroup_size(8, 8, 1)
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

  // Jitter based on influence
  var sampleUV = uv;
  if (influence > 0.1) {
    let jitter = (vec2<f32>(hash21(uv + time), hash21(uv + time + 10.0)) - 0.5) * jitterStrength * influence * 0.1;
    sampleUV = uv + jitter;
  }

  // Sample each channel with prism displacement + jitter
  let rSample = textureSampleLevel(readTexture, u_sampler, rUV + rOffset * prismIntensity + (sampleUV - uv), 0.0);
  let gSample = textureSampleLevel(readTexture, u_sampler, gUV + gOffset * prismIntensity + (sampleUV - uv), 0.0);
  let bSample = textureSampleLevel(readTexture, u_sampler, bUV + bOffset * prismIntensity + (sampleUV - uv), 0.0);

  var color = vec3<f32>(rSample.r, gSample.g, bSample.b);

  // Edge detection on chromatically-separated samples
  let offset = 1.0 / resolution;
  let left = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(offset.x, 0.0), 0.0);
  let right = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(offset.x, 0.0), 0.0);
  let up = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(0.0, offset.y), 0.0);
  let down = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(0.0, offset.y), 0.0);

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

  if (isEdge > 0.5 || isGrid > 0.5) {
    let glow = mix(spectralColor, overloadColor, influence);
    finalColor = mix(finalColor, glow, 0.5 + influence * 0.5);
  }

  // Spectral overload flash on nodes
  if (influence > 0.5 && node > 0.5) {
    let flash = sin(time * 20.0 + hash21(gridID) * 6.28) * 0.5 + 0.5;
    finalColor = mix(finalColor, spectralColor, flash * influence);
  }

  // Scanline effect
  let scanline = sin(uv.y * resolution.y * 0.5) * 0.1;
  finalColor = finalColor - scanline;

  // Spectral glow near mouse
  let mouseGlow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  finalColor = finalColor + spectralColor * mouseGlow * 0.5;

  // Alpha = total chromatic displacement magnitude
  let totalDisp = length(rUV - gUV) + length(gUV - bUV) + length(rOffset) + length(gOffset) + length(bOffset);
  let alpha = clamp(totalDisp * 5.0 + 0.9, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
