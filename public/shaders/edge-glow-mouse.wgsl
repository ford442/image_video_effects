// ═══════════════════════════════════════════════════════════════════
//  Edge Glow Mouse — Batch 59
//  Unsharp edge glow, C-persisted halo trail, capped click bursts,
//  held tightens radius, ACES + semantic alpha, FFT band shimmer.
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
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let edgeThreshold = mix(0.02, 0.35, u.zoom_params.x);
  let glowRadius = mix(0.08, 0.70, u.zoom_params.y) * (1.0 + bass * 0.35) * select(1.0, 0.82, held);
  let intensity = mix(0.3, 2.5, u.zoom_params.z) * select(1.0, 1.25, held);
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
  var glowMask = smoothstep(edgeThreshold, edgeThreshold + 0.15, edgeMag);

  var glowAccum = vec3<f32>(0.0);
  var weightSum = 0.0;
  for (var o: i32 = 0; o < 4; o = o + 1) {
    let radius = glowRadius * (1.0 + f32(o) * 0.6) * px;
    let offset = edgeTangent * radius * (1.0 + f32(o) * 0.4);
    let samp = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let w = 1.0 / (1.0 + f32(o) * 0.7);
    glowAccum = glowAccum + samp * w;
    weightSum = weightSum + w;
  }
  let glowColor = glowAccum / max(weightSum, 0.001);

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseAura = 1.0 - smoothstep(0.0, glowRadius, mouseDist);
  let hue = 0.5 + 0.5 * sin(time * colorSpeed + mouseDist * 18.0 + mids * 2.0);
  let neonTint = mix(vec3<f32>(0.10, 0.85, 1.0), vec3<f32>(1.0, 0.45, 0.75), hue);

  let caStrength = (0.003 + treble * 0.002) * glowMask * intensity;
  let rSamp = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(caStrength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSamp = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(caStrength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var chromatic = vec3<f32>(rSamp, baseColor.g, bSamp);
  chromatic = mix(baseColor, chromatic, glowMask * 0.5);

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst += smoothstep(0.15, 0.0, rDist) * (1.0 - age * 0.7);
    }
  }
  glowMask = clamp(glowMask + clickBurst * 0.5, 0.0, 1.5);

  let band = min(u32(uv.x * 8.0), 7u);
  let bandShimmer = plasmaBuffer[band + 1u].x * 0.2;

  var finalColor = chromatic + neonTint * glowMask * intensity * (0.25 + mouseAura + bass * 0.4 + bandShimmer);
  finalColor = finalColor + glowColor * glowMask * intensity * 0.35 * (1.0 + mouseAura);
  finalColor = mix(finalColor, finalColor * (1.0 + sharpened * 0.15), glowMask);

  let trailGlow = mix(prev.rgb * 0.9, finalColor, 0.2 + glowMask * 0.15);
  finalColor = mix(finalColor, trailGlow, 0.25);

  let depthFalloff = mix(1.0, 0.3, depth);
  finalColor = finalColor * depthFalloff;
  finalColor = acesToneMap(finalColor * 1.2);
  let grain = (hash21(uv * 1000.0 + time * 60.0) - 0.5) * 0.03 * (1.0 + treble);
  finalColor = finalColor + grain;

  let finalAlpha = clamp(glowMask * glowRadius * depth * 2.5 + clickBurst * 0.15, 0.15, 0.95);
  let depthOut = clamp(mix(depth, 0.20 + glowMask * 0.72, 0.26), 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(glowMask, mouseAura, intensity, finalAlpha));
}
