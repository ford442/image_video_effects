// ═══════════════════════════════════════════════════════════════════
//  Edge Glow Mouse — Batch 60 (2nd polish after Batch 59)
//  Unsharp edge glow with oil-slick magenta/teal iridescence,
//  anisotropic bloom packets racing along tangents, richer click
//  ring bursts, held tighten+intensify, C-persisted halo trail,
//  ACES + semantic alpha, FFT band shimmer.
//
//  A packing: (glowMask, mouseAura, packetEnergy, finalAlpha)
//  B unused. C = previous-frame trail (exact textureLoad).
//  No extraBuffer writes.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sampleLuma(uv: vec2<f32>) -> f32 {
  return luminance(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let f = fract(p * vec2<f32>(123.34, 456.21));
  return fract(dot(f, vec2<f32>(1.0, 1.0)) * 78.233);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }
  let pixel = vec2<i32>(gid.xy);

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let held = u.zoom_config.w > 0.5;
  let heldF = select(0.0, 1.0, held);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  // Held: tighter radius + hotter intensity (Batch 60 punch)
  let edgeThreshold = mix(0.02, 0.35, u.zoom_params.x);
  let glowRadius = mix(0.08, 0.70, u.zoom_params.y) * (1.0 + bass * 0.35) * mix(1.0, 0.68, heldF);
  let intensity = mix(0.3, 2.5, u.zoom_params.z) * mix(1.0, 1.55, heldF);
  let colorSpeed = 0.2 + u.zoom_params.w * 4.0;

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  let center = sampleLuma(uv);
  let nb = sampleLuma(uv + vec2<f32>(px.x, 0.0)) + sampleLuma(uv - vec2<f32>(px.x, 0.0))
         + sampleLuma(uv + vec2<f32>(0.0, px.y)) + sampleLuma(uv - vec2<f32>(0.0, px.y));
  let sharpened = center * 5.0 - nb;

  let edgeX = sampleLuma(uv + vec2<f32>(px.x, 0.0)) - sampleLuma(uv - vec2<f32>(px.x, 0.0));
  let edgeY = sampleLuma(uv + vec2<f32>(0.0, px.y)) - sampleLuma(uv - vec2<f32>(0.0, px.y));
  let edgeGrad = vec2<f32>(edgeX, edgeY);
  let edgeMag = length(edgeGrad);
  let edgeTangent = normalize(vec2<f32>(-edgeY, edgeX) + 0.0001);
  let edgeNormal = normalize(edgeGrad + 0.0001);
  var glowMask = smoothstep(edgeThreshold, edgeThreshold + 0.15, edgeMag);

  // Anisotropic bloom along tangent
  var glowAccum = vec3<f32>(0.0);
  var weightSum = 0.0;
  for (var o: i32 = 0; o < 5; o = o + 1) {
    let radius = glowRadius * (1.0 + f32(o) * 0.55) * px;
    let offset = edgeTangent * radius * (1.0 + f32(o) * 0.35);
    let samp = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let w = 1.0 / (1.0 + f32(o) * 0.65);
    glowAccum = glowAccum + samp * w;
    weightSum = weightSum + w;
  }
  let glowColor = glowAccum / max(weightSum, 0.001);

  // Bloom packets racing along edge tangents (distinct from radial blobs)
  let aspectUV = uv * vec2<f32>(aspect, 1.0);
  let tangentPhase = dot(aspectUV, edgeTangent) * (42.0 + treble * 18.0)
                   - time * (6.5 + bass * 4.0 + heldF * 2.5);
  let packetA = pow(max(0.0, sin(tangentPhase)), 12.0);
  let packetB = pow(max(0.0, sin(tangentPhase * 1.7 + 1.3)), 16.0);
  let packetEnergy = (packetA * 0.75 + packetB * 0.55) * glowMask * (0.55 + mids * 0.45 + heldF * 0.35);

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseAura = 1.0 - smoothstep(0.0, glowRadius, mouseDist);

  // Oil-slick iridescent neon — psychedelic magenta/teal film (not plain cyan)
  let filmPhase = edgeMag * 14.0 + dot(aspectUV, edgeNormal) * 9.0
                + time * colorSpeed * 0.55 + mids * 1.4 + mouseDist * 6.0;
  let slickHue = fract(0.78 + 0.22 * sin(filmPhase) + 0.12 * sin(filmPhase * 1.7 + treble));
  let oilSlick = hsv2rgb(vec3<f32>(slickHue, 0.82 + treble * 0.12, 1.0));
  let tealPole = vec3<f32>(0.08, 0.95, 0.88);
  let magentaPole = vec3<f32>(1.0, 0.18, 0.72);
  let poleMix = 0.5 + 0.5 * sin(filmPhase * 0.65 + time * colorSpeed);
  let neonTint = mix(tealPole, magentaPole, poleMix) * oilSlick;

  let caStrength = (0.003 + treble * 0.0025 + heldF * 0.0015) * glowMask * intensity;
  let rSamp = textureSampleLevel(readTexture, u_sampler, clamp(uv + edgeTangent * caStrength, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSamp = textureSampleLevel(readTexture, u_sampler, clamp(uv - edgeTangent * caStrength, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var chromatic = vec3<f32>(rSamp, baseColor.g, bSamp);
  chromatic = mix(baseColor, chromatic, glowMask * 0.55);

  // Richer click ring bursts: thin expanding wavefront + sparkle lobes (not soft blobs)
  var clickBurst = 0.0;
  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.35) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let fade = 1.0 - age / 1.35;
      let core = smoothstep(0.12, 0.0, rDist) * max(1.0 - age * 3.5, 0.0);
      let ringR = age * 0.42;
      let ring = exp(-pow((rDist - ringR) * 36.0, 2.0)) * fade * fade;
      let lobe = pow(max(0.0, sin(atan2(uv.y - rp.y, (uv.x - rp.x) * aspect) * 6.0 + age * 9.0)), 4.0);
      clickBurst += (core * 0.85 + ring * (0.9 + lobe * 0.55)) * fade;
      clickRing += ring * (1.0 + lobe * 0.4);
    }
  }
  glowMask = clamp(glowMask + clickBurst * 0.55 + clickRing * 0.25, 0.0, 1.65);

  let band = min(u32(uv.x * 8.0), 7u);
  let bandShimmer = plasmaBuffer[band + 1u].x * 0.22;

  var finalColor = chromatic
                 + neonTint * glowMask * intensity * (0.28 + mouseAura + bass * 0.42 + bandShimmer)
                 + oilSlick * packetEnergy * intensity * 0.85
                 + neonTint * clickRing * intensity * 0.55;
  finalColor = finalColor + glowColor * glowMask * intensity * 0.38 * (1.0 + mouseAura + packetEnergy * 0.4);
  finalColor = mix(finalColor, finalColor * (1.0 + sharpened * 0.15), glowMask);
  // Thin-film fringe on strong edges / packets
  finalColor = mix(finalColor, finalColor * oilSlick * 1.15, glowMask * (0.18 + packetEnergy * 0.35 + heldF * 0.12));

  let trailGlow = mix(prev.rgb * 0.9, finalColor, 0.22 + glowMask * 0.16);
  finalColor = mix(finalColor, trailGlow, 0.28);

  let depthFalloff = mix(1.0, 0.3, depth);
  finalColor = finalColor * depthFalloff;
  finalColor = acesToneMap(finalColor * (1.25 + heldF * 0.1));
  let grain = (hash21(uv * 1000.0 + time * 60.0) - 0.5) * 0.03 * (1.0 + treble);
  finalColor = finalColor + grain;

  // Semantic (unpremultiplied) alpha
  let finalAlpha = clamp(glowMask * glowRadius * depth * 2.5 + clickBurst * 0.18 + packetEnergy * 0.2, 0.15, 0.95);
  let depthOut = clamp(mix(depth, 0.20 + glowMask * 0.72 + packetEnergy * 0.08, 0.28), 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(glowMask, mouseAura, packetEnergy, finalAlpha));
}
