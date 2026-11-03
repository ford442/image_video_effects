// ═══════════════════════════════════════════════════════════════════
//  Rotoscope Ink
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, edge-stylization
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-02
//  Ideas: edge-magnitude ink weight; cel hold-flats; double weight; cel boil
//  A packing: telemetry RGBA (outline, motion, mouse, alpha)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sampleLuma(uv: vec2<f32>) -> f32 {
  return luminance(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let edgeThreshold = mix(0.025, 0.32, u.zoom_params.x);
  let levels = mix(2.0, 10.0, u.zoom_params.y);
  let inkDensity = mix(0.25, 1.5, u.zoom_params.z);
  let shadeMix = mix(0.06, 1.0, u.zoom_params.w);

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let l = sampleLuma(uv - px);
  let r = sampleLuma(uv + vec2<f32>(px.x, -px.y));
  let t = sampleLuma(uv + vec2<f32>(-px.x, px.y));
  let b = sampleLuma(uv + px);
  let edgeGrad = vec2<f32>(r - l, t - b);
  let edge = length(edgeGrad);
  let edgeDir = atan2(edgeGrad.y, edgeGrad.x);

  let temporalNoise = hash12(floor(uv * 80.0) + vec2<f32>(time * 8.0, time * 5.0));
  let motionStrength = smoothstep(edgeThreshold, edgeThreshold + 0.18, edge) * (0.7 + temporalNoise * 0.3);
  let inkWeight = mix(0.68, 1.48, smoothstep(edgeThreshold, edgeThreshold + 0.28, edge));

  let brushAngle = edgeDir + temporalNoise * 0.4 * (1.0 + audio.x);
  let brushUV = vec2<f32>(
    uv.x * cos(brushAngle) + uv.y * sin(brushAngle),
    -uv.x * sin(brushAngle) + uv.y * cos(brushAngle)
  );
  let brushStroke = smoothstep(0.0, 0.5, sin(brushUV.x * 120.0)) * smoothstep(0.0, 0.15, abs(sin(brushUV.y * 60.0)));
  let taperedLine = brushStroke * motionStrength * inkWeight * (0.6 + 0.4 * sin(brushUV.x * 30.0 + time * 3.0));

  // ── Idea 2: cel boil — flats hop one pixel on a 12-per-second hold; the line stays put
  let holdFlat = 1.0 - smoothstep(0.0, edgeThreshold * 2.2, edge);
  let celFrame = floor(time * 12.0);
  let boilOff = vec2<f32>(
    hash12(vec2<f32>(celFrame, 2.3)) - 0.5,
    hash12(vec2<f32>(celFrame, 5.1)) - 0.5
  ) * px * 2.0;
  let boiled = textureSampleLevel(readTexture, u_sampler, clamp(uv + boilOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let celSrc = mix(src.rgb, boiled, holdFlat);
  let posterized = floor(celSrc * levels) / max(levels - 1.0, 1.0);
  let mouseMask = 1.0 - smoothstep(0.0, 0.5, length((uv - mouse) * vec2<f32>(aspect, 1.0)));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let parallax = (depth - 0.5) * 0.008;
  let parallaxUV = clamp(uv + vec2<f32>(parallax, parallax * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
  let parallaxSrc = textureSampleLevel(readTexture, u_sampler, parallaxUV, 0.0).rgb;

  let inkTint = mix(vec3<f32>(0.04, 0.04, 0.05), vec3<f32>(0.10, 0.18, 0.30), audio.z * 0.45);
  let edgeGlow = mix(vec3<f32>(0.85, 0.45, 0.15), vec3<f32>(0.25, 0.85, 1.0), 0.5 + 0.5 * sin(time + uv.y * 14.0));

  let fastEdge = smoothstep(0.12, 0.35, edge) * (0.5 + 0.5 * sin(time * 6.0 + edge * 20.0));
  let chromaSepR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(fastEdge * 0.003, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let chromaSepB = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(fastEdge * 0.003, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chromaticSrc = vec3<f32>(chromaSepR, src.g, chromaSepB);

  var toon = mix(chromaticSrc, posterized, shadeMix);
  toon = mix(toon, posterized, holdFlat * shadeMix * 0.55);
  let bleedEdge = smoothstep(0.02, 0.08, edge) * (1.0 - smoothstep(0.08, 0.18, edge));
  toon = mix(toon, toon * (1.0 - inkDensity * 0.22) + inkTint * 0.12, bleedEdge * 0.4);

  let jitter = (hash12(uv * 200.0 + time * 20.0) - 0.5) * audio.x * 0.035;
  let handDrawn = toon + inkTint * (taperedLine * inkDensity + jitter);
  let mouseInk = mouseMask * smoothstep(0.4, 0.6, hash12(floor(uv * 70.0) + vec2<f32>(time * 4.0, 0.0))) * 0.2;

  let filmGrain = (hash12(uv * 600.0 + fract(time) * 100.0) - 0.5) * 0.035;
  // ── Idea 1: double weight — a dry-brush halo under the existing tapered core
  let wideStroke = smoothstep(-0.4, 0.2, sin(brushUV.x * 120.0)) * smoothstep(0.0, 0.22, abs(sin(brushUV.y * 40.0)));
  let dryBrush = wideStroke * motionStrength * inkWeight * 0.42;
  let underDrawn = mix(handDrawn, inkTint * 0.72, clamp(dryBrush * inkDensity, 0.0, 1.0));
  var finalColor = mix(underDrawn, inkTint, taperedLine * inkDensity * 0.8) + edgeGlow * taperedLine * mouseMask * (0.06 + audio.x * 0.2) + mouseInk * inkTint;
  finalColor = mix(finalColor, parallaxSrc * 0.5 + finalColor * 0.5, depth * 0.3);
  finalColor = finalColor + filmGrain;
  finalColor = acesToneMap(clamp(finalColor * 1.05, vec3<f32>(0.0), vec3<f32>(4.0)));

  let outlineConfidence = clamp(taperedLine + motionStrength * 0.5 + bleedEdge * 0.3, 0.0, 1.0);
  let finalAlpha = clamp(outlineConfidence * motionStrength * depth + src.a * 0.12 + bleedEdge * 0.15, 0.07, 0.95);

  let outDepth = clamp(mix(depth, 0.16 + outlineConfidence * 0.8, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(outlineConfidence, motionStrength, mouseMask, finalAlpha));
}
