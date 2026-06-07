// ═══════════════════════════════════════════════════════════════════
//  Neural Raymarcher Gabor
//  Category: advanced-hybrid
//  Features: advanced-hybrid, neural-raymarching, gabor-texture, volumetric
//  Complexity: Very High
//  Chunks From: neural-raymarcher.wgsl, conv-gabor-texture-analyzer.wgsl
//  Created: 2026-04-18
//  By: Agent CB-3 — Convolution Post-Processor
// ═══════════════════════════════════════════════════════════════════
//  Raymarched neural network visualization with Gabor oriented texture
//  detection applied to surfaces. Gabor responses highlight connection
//  directions and layer boundaries with psychedelic color mapping.
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Gabor-modulated neural raymarched color
//    Alpha: Dominant orientation magnitude — strength of detected
//           directional structure at each pixel
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
  zoom_params: vec4<f32>,  // x=NetworkDepth, y=ActivationVis, z=Glow, w=CameraRotation
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: ping_pong (from neural-raymarcher.wgsl) ═══
fn ping_pong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

// ═══ CHUNK: hash21 (from neural-raymarcher.wgsl) ═══
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: noise (from neural-raymarcher.wgsl) ═══
fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (vec2<f32>(3.0) - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

// ═══ CHUNK: hsv2rgb (from neural-raymarcher.wgsl) ═══
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  var rgb = vec3<f32>(0.0);
  let c = v * s;
  let h6 = h * 6.0;
  let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
  if (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(v - c);
}

// ═══ CHUNK: reconstruct_normal (from neural-raymarcher.wgsl) ═══
fn reconstruct_normal(uv: vec2<f32>, depth: f32) -> vec3<f32> {
  let resolution = u.config.zw;
  let offset = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
  let dx = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).x
         - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(offset.x, 0.0), 0.0).x;
  let dy = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).x
         - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, offset.y), 0.0).x;
  return normalize(vec3<f32>(-dx, -dy, 1.0));
}

// ═══ CHUNK: schlickFresnel (from neural-raymarcher.wgsl) ═══
fn schlickFresnel(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ CHUNK: gaborResponse (from conv-gabor-texture-analyzer.wgsl) ═══
fn gaborResponse(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
  var response = 0.0;
  let radius = i32(ceil(sigma * 3.0));
  let maxRadius = min(radius, 4);
  let cosTheta = cos(theta);
  let sinTheta = sin(theta);
  for (var dy = -maxRadius; dy <= maxRadius; dy = dy + 1) {
    for (var dx = -maxRadius; dx <= maxRadius; dx = dx + 1) {
      let x = f32(dx);
      let y = f32(dy);
      let xTheta = x * cosTheta + y * sinTheta;
      let yTheta = -x * sinTheta + y * cosTheta;
      let gaussian = exp(-(xTheta * xTheta + yTheta * yTheta) / (2.0 * sigma * sigma + 0.001));
      let sinusoidal = cos(2.0 * 3.14159265 * freq * xTheta);
      let kernel = gaussian * sinusoidal;
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
      response = response + luma * kernel;
    }
  }
  return response;
}

// ═══ CHUNK: palette (from conv-gabor-texture-analyzer.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;

  // Parameters
  let networkDepth = mix(0.5, 1.0, u.zoom_params.x);
  let activationVis = u.zoom_params.y;
  let glow = u.zoom_params.z;
  let cameraRotation = u.zoom_params.w * 6.28;
  let gaborFreq = mix(0.05, 0.3, u.zoom_config.x);
  let gaborSigma = mix(1.5, 4.0, u.zoom_config.y);
  let gaborScale = mix(0.5, 3.0, u.zoom_config.z);

  let zoom_time = time * networkDepth;
  let zoom_center = mousePos;
  let clickIntensity = select(0.0, extraBuffer[10], arrayLength(&extraBuffer) > 10u);

  // ── Neural raymarcher core ──
  var accumulatedColor = vec3<f32>(0.0);
  var accumulatedDepth = 0.0;
  var totalWeight = 0.0;

  for (var i: i32 = 0; i < 5; i = i + 1) {
    let layerDepth = f32(i) / f32(4);
    let layerSpeed = mix(0.2, 1.0, layerDepth);
    let layerZoom = 1.0 + fract(zoom_time * layerSpeed) * 4.0;
    let toCenter = uv - zoom_center;
    let angle = atan2(toCenter.y, toCenter.x);
    let dist = length(toCenter);
    let vortexStrength = clickIntensity * 0.3 / (dist + 0.1);
    let spinAngle = vortexStrength * layerDepth * (1.0 - layerDepth);
    let rotatedUV = vec2<f32>(
      cos(spinAngle) * toCenter.x - sin(spinAngle) * toCenter.y,
      sin(spinAngle) * toCenter.x + cos(spinAngle) * toCenter.y
    ) + zoom_center;

    let flowUV = rotatedUV + vec2<f32>(noise(rotatedUV * 6.0 + vec2<f32>(time * 0.15, 0.0)),
                                        noise(rotatedUV * 6.0 + vec2<f32>(0.0, time * 0.15))) * 0.015 * layerDepth;
    let transformed = (flowUV - zoom_center) / vec2<f32>(layerZoom) + zoom_center;
    let sampleUV = ping_pong_v2(transformed);
    let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    let density = exp(-layerDepth * 1.5);
    let weight = density * (1.0 + sampleDepth * 0.5);
    accumulatedColor = accumulatedColor + sampleColor * weight;
    accumulatedDepth = accumulatedDepth + sampleDepth * weight;
    totalWeight = totalWeight + weight;
  }

  let baseColor = accumulatedColor / vec3<f32>(max(totalWeight, 0.0001));
  let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

  // Chromatic aberration
  let chroma = select(0.02, extraBuffer[0], arrayLength(&extraBuffer) > 0u);
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chroma * baseDepth, 0.0), 0.0).x;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).y;
  let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(chroma * baseDepth, 0.0), 0.0).z;
  let chromaticColor = vec3<f32>(r, g, b);

  // Edge glow
  let ps = pixelSize;
  let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0).x;
  let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, ps.y), 0.0).x;
  let depthGrad = length(vec2<f32>(depthX - baseDepth, depthY - baseDepth));
  let edgeGlow = exp(-depthGrad * 30.0) * baseDepth * 2.0;
  let raymarchedColor = chromaticColor + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

  // Volumetric fog
  let normal = reconstruct_normal(uv, baseDepth);
  let viewDotNormal = dot(vec3<f32>(0.0, 0.0, 1.0), normal);
  let fog = exp(-baseDepth * glow * 3.0);
  let fogColor = vec3<f32>(0.02, 0.05, 0.1);
  let foggedColor = mix(raymarchedColor, fogColor, 1.0 - fog);

  // ── Gabor texture post-processing ──
  let mouseAngle = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
  let mouseDist = length(uv - mousePos);
  let mouseFactor = exp(-mouseDist * mouseDist * 4.0);
  let rotationOffset = mouseAngle * mouseFactor + cameraRotation * 0.1;

  let r0 = gaborResponse(uv, 0.0 + rotationOffset, gaborFreq, gaborSigma, pixelSize) * gaborScale;
  let r45 = gaborResponse(uv, 0.785398 + rotationOffset, gaborFreq, gaborSigma, pixelSize) * gaborScale;
  let r90 = gaborResponse(uv, 1.570796 + rotationOffset, gaborFreq, gaborSigma, pixelSize) * gaborScale;
  let r135 = gaborResponse(uv, 2.356194 + rotationOffset, gaborFreq, gaborSigma, pixelSize) * gaborScale;

  let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
  let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
  let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
  let pal135 = palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33));

  var gaborColor = vec3<f32>(0.0);
  gaborColor = gaborColor + pal0 * abs(r0);
  gaborColor = gaborColor + pal45 * abs(r45);
  gaborColor = gaborColor + pal90 * abs(r90);
  gaborColor = gaborColor + pal135 * abs(r135);
  let totalResponse = abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001;
  gaborColor = gaborColor / totalResponse;
  gaborColor = gaborColor * 1.3;

  // Blend Gabor onto raymarched result based on activationVis
  let neuralColor = mix(foggedColor, foggedColor * 0.5 + gaborColor * 0.5, activationVis);

  // Dominant orientation magnitude for alpha
  let dominantOrientation = max(max(abs(r0), abs(r45)), max(abs(r90), abs(r135))) / gaborScale;

  let alpha = mix(0.85, 1.0, glow * 0.3);

  textureStore(writeTexture, global_id.xy, vec4<f32>(neuralColor, dominantOrientation));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
