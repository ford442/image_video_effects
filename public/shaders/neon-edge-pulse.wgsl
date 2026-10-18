// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Pulse
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, advanced-alpha, semantic-alpha
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: per-layer neon edges (4-tap central difference at each layer's mirrored UV, hue = colorShift + layerDepth*0.25); inward bass pulse (phase time*pulseSpeed*4 - layerDepth*TAU); centre proximity gain 1 + 2*exp(-d^2/0.05)
//  A packing: ACES display RGBA (HEAD wrote no A)
// ═══════════════════════════════════════════════════════════════════
// Five mirrored (ping-pong) zoom layers centred on the pointer. Each layer is
// zoomed by 1 + fract(zoom_time*layerSpeed)*4, drifted by a 0.015 noise flow,
// weighted by exp(-depth*1.5) and split by a depth-driven 0.02 chroma offset.
// zoom_params: x = Edge Threshold, y = Pulse Speed, z = Glow Intensity, w = Color Shift (hue)

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
const LAYERS: i32 = 5;
const FOG_DENSITY: f32 = 0.0;          // constant: default look keeps no fog
const CHROMA_SPLIT: f32 = 0.02;        // depth-chroma split (was extraBuffer[0])

fn pingPong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn pingPong2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(pingPong(v.x), pingPong(v.y));
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + vec3<f32>(dot(p3, p3 + vec3<f32>(33.33)));
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (vec2<f32>(3.0) - 2.0 * f);
  let a = hash21(i + vec2<f32>(0.0, 0.0));
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let h6 = fract(h) * 6.0;
  let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
  var rgb = vec3<f32>(c, 0.0, x);
  if (h6 < 1.0) {
    rgb = vec3<f32>(c, x, 0.0);
  } else if (h6 < 2.0) {
    rgb = vec3<f32>(x, c, 0.0);
  } else if (h6 < 3.0) {
    rgb = vec3<f32>(0.0, c, x);
  } else if (h6 < 4.0) {
    rgb = vec3<f32>(0.0, x, c);
  } else if (h6 < 5.0) {
    rgb = vec3<f32>(x, 0.0, c);
  }
  return rgb + vec3<f32>(v - c);
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let v = max(x, vec3<f32>(0.0));
  return clamp((v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn reconstructNormal(uv: vec2<f32>) -> vec3<f32> {
  let offset = vec2<f32>(1.0) / u.config.zw;
  let dx = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).x
         - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(offset.x, 0.0), 0.0).x;
  let dy = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).x
         - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, offset.y), 0.0).x;
  let n = vec3<f32>(-dx, -dy, 1.0);
  return n / max(length(n), 1e-4);
}

fn schlickFresnel(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

fn calculateVolumetricAlpha(layerDepth: f32, fogDensity: f32, viewDotNormal: f32, accumulatedWeight: f32) -> f32 {
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), 0.03);
  let fogAmount = exp(-layerDepth * fogDensity * 3.0);
  let depthAlpha = mix(0.95, 0.4, fogAmount);
  let weightAlpha = mix(0.5, 0.9, smoothstep(0.0, 1.0, accumulatedWeight));
  let alpha = depthAlpha * weightAlpha * (1.0 - fresnel * 0.2);
  return clamp(alpha, 0.0, 1.0);
}

// ═══ ADVANCED ALPHA FUNCTION (kept) ═══
fn calculateAdvancedAlpha(color: vec3<f32>, uv: vec2<f32>, depth: f32, depthGrad: f32, baseAlpha: f32) -> f32 {
  let edgeThreshold = u.zoom_params.x;   // Edge Threshold
  let glowIntensity = u.zoom_params.z;   // Glow Intensity

  // Edge magnitude from depth gradient
  let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold + 1e-3, depthGrad);

  // Glow-driven alpha: brighter glow = more opaque
  let glowAlpha = smoothstep(0.05, 0.3, luma(color)) * glowIntensity;

  // Combine: edges are opaque, glow areas are opaque, smooth interiors transparent
  let combinedAlpha = max(edgeMask * 0.9, glowAlpha) + baseAlpha * 0.2;

  // Depth influence: foreground edges more opaque
  let depthAlpha = mix(0.25, 1.0, depth);
  let alpha = mix(combinedAlpha, depthAlpha, 0.3);
  return clamp(alpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let ps = vec2<f32>(1.0) / resolution;
  let time = u.config.x;
  let zoomTime = u.zoom_config.x;
  let zoomCenter = u.zoom_config.yz;              // tunnel centre = pointer (idle parks at 0.5,0.5)
  let clickIntensity = select(0.0, 1.0, u.zoom_config.w > 0.5);   // vortex from mouse_down (was extraBuffer[10])

  let edgeThreshold = u.zoom_params.x;
  let pulseSpeed = u.zoom_params.y;
  let glowIntensity = u.zoom_params.z;
  let colorShift = u.zoom_params.w;               // hue
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);

  // Edge threshold mapped onto the 2-texel central-difference luma gradient
  // (typical edges 0.1..0.6, bilinear noise ~0.02): default 0.5 -> 0.05..0.25.
  let edgeLo = 0.01 + edgeThreshold * 0.08;
  let edgeHi = edgeLo + 0.05 + edgeThreshold * 0.3;

  // IDEA 3: centre proximity gain — edges nearest the tunnel centre burn brightest.
  let dCentre = length(uv - zoomCenter);
  let proximityGain = 1.0 + 2.0 * exp(-(dCentre * dCentre) / 0.05);

  var accumulatedColor = vec3<f32>(0.0);
  var accumulatedEdge = vec3<f32>(0.0);
  var accumulatedDepth = 0.0;
  var totalWeight = 0.0;

  for (var i = 0; i < LAYERS; i = i + 1) {
    let layerDepth = f32(i) / f32(LAYERS - 1);
    let layerSpeed = pulseSpeed;                                    // FIX: was mix(p.x, p.y, depth)
    // Kept zoom law; the layerDepth*0.8 phase stagger spreads the five layers through the
    // cycle (with a single layerSpeed they would otherwise coincide and the tunnel collapses).
    let layerZoom = 1.0 + fract(zoomTime * layerSpeed + layerDepth * 0.8) * 4.0;

    let toCenter = uv - zoomCenter;
    let dist = length(toCenter);
    let vortexStrength = (clickIntensity * 0.3) / (dist + 0.1);
    let spinAngle = vortexStrength * layerDepth * (1.0 - layerDepth);
    let cs = cos(spinAngle);
    let sn = sin(spinAngle);
    let rotatedUV = vec2<f32>(cs * toCenter.x - sn * toCenter.y,
                              sn * toCenter.x + cs * toCenter.y) + zoomCenter;

    let flow = vec2<f32>(noise(rotatedUV * 6.0 + vec2<f32>(time * 0.15, 0.0)),
                         noise(rotatedUV * 6.0 + vec2<f32>(0.0, time * 0.15)));
    let flowUV = rotatedUV + flow * 0.015 * layerDepth;
    let transformed = (flowUV - zoomCenter) / vec2<f32>(layerZoom) + zoomCenter;
    let mirroredUV = pingPong2(transformed);

    let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, mirroredUV, 0.0).x;

    // Kept depth-chroma split (0.02 * depth), now applied inside the layer so the tunnel is what is shown.
    let split = vec2<f32>(CHROMA_SPLIT * sampleDepth, 0.0);
    let sampleColor = vec3<f32>(
      textureSampleLevel(readTexture, u_sampler, mirroredUV + split, 0.0).r,
      textureSampleLevel(readTexture, u_sampler, mirroredUV, 0.0).g,
      textureSampleLevel(readTexture, u_sampler, mirroredUV - split, 0.0).b);

    let density = exp(-layerDepth * 1.5);
    let weight = density * (1.0 + sampleDepth * 0.5);

    // IDEA 1: per-layer neon edges — 4-tap central difference at this layer's mirrored UV.
    let lumL = luma(textureSampleLevel(readTexture, u_sampler, mirroredUV - vec2<f32>(ps.x, 0.0), 0.0).rgb);
    let lumR = luma(textureSampleLevel(readTexture, u_sampler, mirroredUV + vec2<f32>(ps.x, 0.0), 0.0).rgb);
    let lumT = luma(textureSampleLevel(readTexture, u_sampler, mirroredUV - vec2<f32>(0.0, ps.y), 0.0).rgb);
    let lumB = luma(textureSampleLevel(readTexture, u_sampler, mirroredUV + vec2<f32>(0.0, ps.y), 0.0).rgb);
    let grad = length(vec2<f32>(lumR - lumL, lumB - lumT));
    let layerEdge = smoothstep(edgeLo, edgeHi, grad);
    let edgeHue = hsv2rgb(colorShift + layerDepth * 0.2, 0.85, 1.0);

    // IDEA 2: inward pulse — sin(wt - k*depth) crests move toward increasing depth,
    // so the glow runs from the viewer into the tunnel; bass raises the amplitude.
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * 4.0 - layerDepth * TAU * 0.8);
    let pulseAmp = (0.4 + 0.6 * pulse) * (1.0 + bass);

    accumulatedColor += sampleColor * weight;
    accumulatedEdge += edgeHue * layerEdge * pulseAmp * weight;
    accumulatedDepth += sampleDepth * weight;
    totalWeight += weight;
  }

  let invWeight = 1.0 / max(totalWeight, 0.0001);
  let baseColor = accumulatedColor * invWeight;
  let baseDepth = accumulatedDepth * invWeight;
  let neonEdges = accumulatedEdge * invWeight * glowIntensity * 2.5 * proximityGain;

  // Depth gradient of the scene around this pixel (feeds the kept advanced alpha).
  let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0).x;
  let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, ps.y), 0.0).x;
  let depthGrad = length(vec2<f32>(depthX - baseDepth, depthY - baseDepth));

  let finalColor = baseColor + neonEdges;

  let normal = reconstructNormal(uv);
  let viewDotNormal = dot(vec3<f32>(0.0, 0.0, 1.0), normal);
  let normalizedWeight = totalWeight / f32(LAYERS);
  let volumetricAlpha = calculateVolumetricAlpha(0.5, FOG_DENSITY, viewDotNormal, normalizedWeight);
  let fog = exp(-baseDepth * FOG_DENSITY * 3.0);
  let fogColor = vec3<f32>(0.02, 0.05, 0.1);
  let outColor = mix(finalColor, fogColor, 1.0 - fog);

  let display = aces(outColor);
  let alpha = calculateAdvancedAlpha(display, uv, baseDepth, depthGrad, volumetricAlpha);
  let result = vec4<f32>(display, alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(baseDepth, 0.0, 1.0), 0.0, 0.0, 0.0));
}
