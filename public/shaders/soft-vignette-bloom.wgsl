// ═══════════════════════════════════════════════════════════════════
//  Soft Vignette Bloom v3 — Lens Effects & Cinematic Lighting Enhanced
//  Category: post-processing
//  Features: bloom, cinematic, audio-reactive, depth-aware, lens-flare,
//            chromatic-aberration, bokeh-dof, starburst-diffraction,
//            anamorphic-streaks, enhanced-falloff
//  Complexity: High
//  Upgraded: 2026-05-30, 2026-06-28
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

const PI: f32 = 3.141592653589793;

// ═══ CHUNK: aces_approx ═══
fn aces_approx(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ Chromatic Aberration at Edges ═══
fn chromaticAberration(uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec3<f32> {
  let d = uv - center;
  let radialDist = length(d);
  let offset = radialDist * strength;
  let rUV = uv + d * offset * 1.5;
  let gUV = uv + d * offset * 0.8;
  let bUV = uv + d * offset * 2.2;
  return vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );
}

// ═══ Lens Flare: Ghost Images from Internal Reflections ═══
fn lensFlare(uv: vec2<f32>, lightPos: vec2<f32>, intensity: f32) -> vec3<f32> {
  let d = uv - lightPos;
  let dist = length(d);
  var flare = vec3<f32>(0.0);

  // Main flare halo
  let halo = exp(-dist * dist * 8.0) * 0.5;
  flare = flare + vec3<f32>(1.0, 0.95, 0.8) * halo * intensity;

  // Ghost images (internal reflections) - multiple flips around light source
  let ghosts = array<vec2<f32>, 3>(
    lightPos + d * 0.5,
    lightPos - d * 0.3,
    lightPos + d * 1.2
  );
  let ghostColors = array<vec3<f32>, 3>(
    vec3<f32>(0.8, 0.9, 1.0),
    vec3<f32>(1.0, 0.7, 0.5),
    vec3<f32>(0.6, 0.8, 1.0)
  );
  for (var i = 0; i < 3; i = i + 1) {
    let gDist = length(uv - ghosts[i]);
    let gSize = 0.03 + f32(i) * 0.01;
    let ghost = exp(-gDist * gDist / (gSize * gSize)) * 0.3;
    flare = flare + ghostColors[i] * ghost * intensity;
  }

  return flare;
}

// ═══ Starburst Diffraction Spikes (8-pointed) ═══
fn starburstSpikes(uv: vec2<f32>, center: vec2<f32>, intensity: f32, time: f32) -> f32 {
  let d = uv - center;
  let r = length(d);
  let angle = atan2(d.y, d.x);
  var spikes = 0.0;
  // 8-pointed starburst
  for (var i = 0; i < 8; i = i + 1) {
    let spikeAngle = f32(i) * PI / 4.0 + time * 0.05;
    let angleDiff = angle - spikeAngle;
    let spike = pow(max(0.0, cos(angleDiff * 2.0)), 10.0) * exp(-r * 8.0);
    spikes = spikes + spike;
  }
  return spikes * intensity;
}

// ═══ Bokeh Depth-of-Field (hexagonal aperture SDF) ═══
fn hexagonSDF(p: vec2<f32>, r: f32) -> f32 {
  let k = vec3<f32>(-0.8660254, 0.5, 0.57735);
  let q = abs(p);
  let h = q - r * vec2<f32>(0.866, 0.5);
  let a = dot(k.xy, h);
  let b = max(h.y, 0.0);
  let c = max(a, b);
  return length(max(vec2<f32>(c, h.x), vec2<f32>(0.0))) * sign(c);
}

fn bokehDOF(uv: vec2<f32>, center: vec2<f32>, depth: f32, focusDepth: f32, blurAmount: f32) -> vec3<f32> {
  let coc = abs(depth - focusDepth) * blurAmount; // Circle of confusion
  if (coc < 0.001) {
    return textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  }
  var bokeh = vec3<f32>(0.0);
  var weight = 0.0;
  let texel = vec2<f32>(1.0) / u.config.zw;
  // Hexagonal kernel sampling
  let hexDirs = array<vec2<f32>, 6>(
    vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.866),
    vec2<f32>(-0.5, 0.866), vec2<f32>(-1.0, 0.0),
    vec2<f32>(-0.5, -0.866), vec2<f32>(0.5, -0.866)
  );
  for (var ring = 0; ring < 3; ring = ring + 1) {
    let r = f32(ring + 1) * 0.3;
    let ringWeight = 1.0 / f32(ring + 1);
    for (var i = 0; i < 6; i = i + 1) {
      let sampleUV = uv + hexDirs[i] * texel * coc * r * 10.0;
      let hexWeight = 1.0 - hexagonSDF(sampleUV - center, coc * r * 0.5);
      let samp = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
      let luma = dot(samp, vec3<f32>(0.299, 0.587, 0.114));
      let brightWeight = smoothstep(0.3, 0.8, luma);
      bokeh = bokeh + samp * ringWeight * max(hexWeight, 0.0) * brightWeight;
      weight = weight + ringWeight * max(hexWeight, 0.0) * brightWeight;
    }
  }
  if (weight > 0.0) {
    bokeh = bokeh / weight;
  }
  return mix(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, bokeh, smoothstep(0.0, 0.1, coc));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let texel = 1.0 / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let vignetteStrength = u.zoom_params.x;
  let bloomRadius = u.zoom_params.y;
  let hazeAmount = u.zoom_params.z;
  let bloomIntensity = u.zoom_params.w;

  // ═══ BOKEH DEPTH OF FIELD ═══
  var col = bokehDOF(uv, mouse, depth, 0.5, bloomRadius * 0.5);
  let baseAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

  // Multi-scale Gaussian bloom pyramid (3 scales) with enhanced threshold
  var bloom = vec3<f32>(0.0);
  var bloomEnergy = 0.0;
  let scales = array<f32, 3>(1.0, 2.5, 5.0);
  let weights = array<f32, 3>(0.5, 0.3, 0.2);

  for (var level: u32 = 0u; level < 3u; level = level + 1u) {
    let r = max(bloomRadius * scales[level], 1.0);
    var lvlBloom = vec3<f32>(0.0);
    var lvlWeight = 0.0;
    for (var dy = -2; dy <= 2; dy = dy + 1) {
      for (var dx = -2; dx <= 2; dx = dx + 1) {
        let off = vec2<f32>(f32(dx), f32(dy)) * texel * r;
        let samp = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let luma = dot(samp, vec3<f32>(0.299, 0.587, 0.114));
        // Bass lowers bloom threshold, treble adds sparkle
        let thresh = 0.5 - bass * 0.25 + treble * 0.05;
        let brightMask = smoothstep(thresh, thresh + 0.2, luma);
        lvlBloom = lvlBloom + samp * brightMask;
        lvlWeight = lvlWeight + brightMask;
      }
    }
    if (lvlWeight > 0.0) {
      lvlBloom = lvlBloom / lvlWeight;
    }
    bloom = bloom + lvlBloom * weights[level];
    bloomEnergy = bloomEnergy + dot(lvlBloom, vec3<f32>(0.299, 0.587, 0.114)) * weights[level];
  }

  // Anamorphic streaks on bright highlights (horizontal stretch)
  var streak = vec3<f32>(0.0);
  let streakSamples = 8;
  for (var i = -streakSamples; i <= streakSamples; i = i + 1) {
    let off = vec2<f32>(f32(i) * texel.x * bloomRadius * 3.0, 0.0);
    let samp = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let luma = dot(samp, vec3<f32>(0.299, 0.587, 0.114));
    let weight = smoothstep(0.6, 0.9, luma) * exp(-abs(f32(i)) * 0.3);
    streak = streak + samp * weight;
  }
  bloom = bloom + streak * 0.15 * bloomIntensity;

  col = col + bloom * bloomIntensity * 0.4;

  // ═══ LENS FLARE (ghost images from bright areas) ═══
  // Find bright spot center (mouse-driven + audio reactive)
  let flareCenter = mix(vec2<f32>(0.5), mouse, 0.6 + bass * 0.2);
  let flareIntensity = bloomEnergy * 0.3 * (1.0 + bass * 0.5) * bloomIntensity;
  let flare = lensFlare(uv, flareCenter, flareIntensity);
  col = col + flare * 0.5;

  // ═══ STARBURST DIFFRACTION SPIKES ═══
  // 8-pointed star from the bright flare center
  let starburst = starburstSpikes(uv, flareCenter, flareIntensity * 0.6, time);
  let starburstColor = vec3<f32>(1.0, 0.95, 0.85) * starburst;
  col = col + starburstColor * 0.3;

  // Superellipse vignette with mouse center
  let vignetteCenter = mix(vec2<f32>(0.5), mouse, 0.5);
  let d = uv - vignetteCenter;
  let aspect = res.x / res.y;
  let dist = pow(pow(abs(d.x) * aspect, 2.5) + pow(abs(d.y), 2.5), 1.0 / 2.5);
  let vignette = smoothstep(0.8, 0.25, dist * (1.0 + vignetteStrength));

  // ═══ ENHANCED LIGHT FALLOFF ═══
  // Realistic light attenuation: 1/(1 + kd + qd^2)
  let falloffDist = length(d) * 2.0;
  let lightFalloff = 1.0 / (1.0 + 1.5 * falloffDist + 3.0 * falloffDist * falloffDist);
  col = col * (0.5 + lightFalloff * 0.5 + vignette * 0.5);

  // Depth-driven haze
  let haze = mix(vec3<f32>(0.6, 0.65, 0.75), vec3<f32>(1.0), depth);
  col = mix(col, col * haze, hazeAmount * (1.0 - depth));

  // Split-tone shadows
  let shadowMask = 1.0 - dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let shadowTint = vec3<f32>(0.15, 0.08, 0.25);
  col = col + shadowTint * shadowMask * 0.15;

  // ═══ CHROMATIC ABERRATION AT EDGES ═══
  let radialDist = length(d);
  let chromaticStrength = smoothstep(0.4, 0.9, radialDist) * 0.025 * (1.0 + bass * 0.1);
  if (chromaticStrength > 0.001) {
    let chromaticColor = chromaticAberration(uv, vignetteCenter, chromaticStrength);
    col = mix(col, chromaticColor, chromaticStrength * 4.0);
  }

  // Film grain
  let grain = hash12(uv * 43758.5453 + fract(time * 0.1)) * 0.04 - 0.02;
  col = col + grain * vignette;

  // Apply vignette and tone map
  col = col * vignette;
  col = aces_approx(max(col, vec3<f32>(0.0)));

  // Alpha: bloom energy × vignette factor + light falloff
  let alpha = clamp(bloomEnergy * vignette * 2.0 + baseAlpha * 0.3 + lightFalloff * 0.2, 0.0, 1.0);

  // Premultiplied alpha writeback
  textureStore(writeTexture, coord, vec4<f32>(col * alpha, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
