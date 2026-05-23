// ═══════════════════════════════════════════════════════════════════
//  Neon Edges
//  Category: retro-glitch
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven, mach-band, blackbody-spectrum
//  Complexity: High
//  Scientific: Multi-scale Sobel and directional second-derivative enhancement approximate Mach bands for perceptual edge glow.
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

struct EdgeMetrics {
  grad: vec2<f32>,
  magnitude: f32,
  depthMagnitude: f32,
  mach: f32,
};

fn luminance(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn sampleColor(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn sampleDepth(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 15000.0);
  let tt = t / 100.0;
  var r = 1.0;
  var g = 1.0;
  var b = 1.0;

  if (t <= 6600.0) {
    r = 1.0;
    g = 0.39008157 * log(tt) - 0.63184144;
    if (t < 2000.0) {
      b = 0.0;
    } else {
      b = 0.54320679 * log(max(tt - 10.0, 0.01)) - 1.19625408;
    }
  } else {
    r = 1.29293618 * pow(tt - 60.0, -0.1332047592);
    g = 1.12989086 * pow(tt - 60.0, -0.0755148492);
    b = 1.0;
  }

  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn edgeAtScale(uv: vec2<f32>, texel: vec2<f32>) -> EdgeMetrics {
  let tl = sampleColor(uv + vec2<f32>(-texel.x, -texel.y));
  let  t = sampleColor(uv + vec2<f32>(0.0, -texel.y));
  let tr = sampleColor(uv + vec2<f32>(texel.x, -texel.y));
  let  l = sampleColor(uv + vec2<f32>(-texel.x, 0.0));
  let  c = sampleColor(uv);
  let  r = sampleColor(uv + vec2<f32>(texel.x, 0.0));
  let bl = sampleColor(uv + vec2<f32>(-texel.x, texel.y));
  let  b = sampleColor(uv + vec2<f32>(0.0, texel.y));
  let br = sampleColor(uv + vec2<f32>(texel.x, texel.y));

  let tlD = sampleDepth(uv + vec2<f32>(-texel.x, -texel.y));
  let  tD = sampleDepth(uv + vec2<f32>(0.0, -texel.y));
  let trD = sampleDepth(uv + vec2<f32>(texel.x, -texel.y));
  let  lD = sampleDepth(uv + vec2<f32>(-texel.x, 0.0));
  let  cD = sampleDepth(uv);
  let  rD = sampleDepth(uv + vec2<f32>(texel.x, 0.0));
  let blD = sampleDepth(uv + vec2<f32>(-texel.x, texel.y));
  let  bD = sampleDepth(uv + vec2<f32>(0.0, texel.y));
  let brD = sampleDepth(uv + vec2<f32>(texel.x, texel.y));

  let tlL = luminance(tl.rgb);
  let tL = luminance(t.rgb);
  let trL = luminance(tr.rgb);
  let lL = luminance(l.rgb);
  let cL = luminance(c.rgb);
  let rL = luminance(r.rgb);
  let blL = luminance(bl.rgb);
  let bL = luminance(b.rgb);
  let brL = luminance(br.rgb);

  let gradColor = vec2<f32>(
    (trL + 2.0 * rL + brL) - (tlL + 2.0 * lL + blL),
    (blL + 2.0 * bL + brL) - (tlL + 2.0 * tL + trL)
  );
  let gradDepth = vec2<f32>(
    (trD + 2.0 * rD + brD) - (tlD + 2.0 * lD + blD),
    (blD + 2.0 * bD + brD) - (tlD + 2.0 * tD + trD)
  );

  var dir = gradColor + gradDepth * 1.8;
  let dirLength = length(dir);
  if (dirLength < 1e-5) {
    dir = vec2<f32>(1.0, 0.0);
  } else {
    dir = dir / dirLength;
  }

  let sampleDist = max(texel.x, texel.y);
  let lumForward = luminance(sampleColor(uv + dir * sampleDist).rgb);
  let lumBackward = luminance(sampleColor(uv - dir * sampleDist).rgb);
  let depthForward = sampleDepth(uv + dir * sampleDist);
  let depthBackward = sampleDepth(uv - dir * sampleDist);

  let mach = (lumForward + lumBackward - 2.0 * cL) * 1.6 + (depthForward + depthBackward - 2.0 * cD) * 1.2;

  var metrics: EdgeMetrics;
  metrics.grad = dir;
  metrics.magnitude = length(gradColor) * 0.75 + length(gradDepth) * 1.4;
  metrics.depthMagnitude = length(gradDepth);
  metrics.mach = mach;
  return metrics;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = 1.0 / resolution;

  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;
  let base = sampleColor(uv);
  let depth = sampleDepth(uv);

  let scale1 = edgeAtScale(uv, texel * 1.0);
  let scale2 = edgeAtScale(uv, texel * 2.0);
  let scale3 = edgeAtScale(uv, texel * 4.0);
  let scale4 = edgeAtScale(uv, texel * 8.0);
  let scale5 = edgeAtScale(uv, texel * 16.0);

  let sensitivity = mix(0.35, 2.1, u.zoom_params.x);
  let machStrength = mix(0.3, 2.4, u.zoom_params.y);
  let spotlightRadius = mix(0.45, 0.08, u.zoom_params.z);
  let neonGain = mix(0.7, 4.8, u.zoom_params.w);

  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let deltaMouse = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);
  let depthReveal = exp(-dot(deltaMouse, deltaMouse) / max(spotlightRadius * spotlightRadius, 0.002)) * (0.35 + 0.65 * max(u.zoom_config.w, 0.35));

  let combinedEdge = (
    scale1.magnitude * 1.35 * (1.0 + treble * 0.75) +
    scale2.magnitude * 1.15 +
    scale3.magnitude * 0.95 +
    scale4.magnitude * 0.70 * (1.0 + bass * 0.35) +
    scale5.magnitude * 0.50 * (1.0 + bass * 0.35)
  ) * sensitivity;

  let depthEdge = (
    scale1.depthMagnitude * 1.40 +
    scale2.depthMagnitude * 1.10 +
    scale3.depthMagnitude * 0.85 +
    scale4.depthMagnitude * 0.60 +
    scale5.depthMagnitude * 0.40
  ) * (1.0 + depthReveal * 1.8);

  let machResponse = (
    scale1.mach * 1.30 * (1.0 + treble * 0.60) +
    scale2.mach * 1.15 +
    scale3.mach * 0.85 +
    scale4.mach * 0.55 +
    scale5.mach * 0.35
  ) * machStrength;

  let brightBand = max(machResponse, 0.0);
  let darkBand = max(-machResponse, 0.0);
  let edgeSignal = max(combinedEdge + depthEdge * 0.95 + brightBand * 1.2, 0.0);
  let edgeStrength = smoothstep(0.02, 0.90, edgeSignal);

  let temperature = mix(1400.0, 11200.0, clamp(edgeStrength * 0.85 + brightBand * 0.5 + bass * 0.12, 0.0, 1.0));
  let spectral = blackbodyRGB(temperature);
  let glow = spectral * edgeSignal * neonGain * (0.28 + 0.72 * depthReveal + 0.55 * bass);
  let fineDetail = spectral * scale1.magnitude * treble * 0.45;
  let halo = smoothstep(0.02, 0.45, combinedEdge) * smoothstep(0.0, 0.35, darkBand) * 0.75;
  let fogLift = spectral * depthReveal * 0.06 * (1.0 - depth);

  let finalColor = max(base.rgb * (1.0 - halo * 0.45) + glow + fineDetail + fogLift, vec3<f32>(0.0));
  let alpha = clamp(luminance(finalColor) + edgeStrength * 0.25, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(edgeStrength, brightBand, (temperature - 1400.0) / 9800.0, halo));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
