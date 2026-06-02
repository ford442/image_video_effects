// ═══════════════════════════════════════════════════════════════════
//  Cinematic Flare v2
//  Category: lighting-effects
//  Features: audio-reactive, depth-aware, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Strategy: Cooke triplet ghosts + diffraction spikes + scatter halo + anamorphic streaks
//  Upgraded: 2026-05-30
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: aces_tone_map ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Film grain
fn grain(uv: vec2<f32>, t: f32) -> f32 {
  return (hash12(uv * 437.0 + t) - 0.5) * 0.04;
}

// Diffraction spike from aperture blades (6-blade starburst)
fn diffraction_spike(dir: vec2<f32>, intensity: f32) -> f32 {
  let angle = atan2(dir.y, dir.x);
  var spike = 0.0;
  for (var b = 0; b < 6; b = b + 1) {
    let bladeAngle = f32(b) * 0.523599;
    let diff = angle - bladeAngle;
    let sinc = sin(diff * 8.0) / (diff * 8.0 + 0.001);
    spike = spike + sinc * sinc;
  }
  return spike * intensity * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let flareIntensity = u.zoom_params.x * (1.0 + bass * 0.8);
  let streakLen = u.zoom_params.y * 0.35;
  let chromaAmt = u.zoom_params.z * 0.025;
  let threshold = u.zoom_params.w * 0.4;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let haze = mix(0.4, 1.0, depth);

  // Mouse positions the light source; center fallback
  let mouse = u.zoom_config.yz;
  let hasMouse = mouse.x >= 0.0;
  let lightPos = select(vec2<f32>(0.5, 0.5), mouse, hasMouse);

  let aspect = resolution.x / resolution.y;
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let lightAspect = vec2<f32>(lightPos.x * aspect, lightPos.y);
  let toLight = lightAspect - uvAspect;
  let lightDist = length(toLight);
  let lightDir = normalize(toLight + vec2<f32>(0.0001));

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(sourceColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

  // Anamorphic streak sampling along light-to-pixel axis
  var streakAccum = vec3<f32>(0.0);
  var streakWeight = 0.0;
  let samples = 12;
  for (var i = 0; i < samples; i = i + 1) {
    let t = (f32(i) / f32(samples - 1)) - 0.5;
    let offsetUV = uv + vec2<f32>(t * streakLen * lightDir.x / aspect, t * streakLen * lightDir.y);
    let sampleColor = textureSampleLevel(readTexture, u_sampler, clamp(offsetUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let sampleLuma = dot(sampleColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let hot = smoothstep(threshold, threshold + 0.25, sampleLuma);
    streakAccum = streakAccum + sampleColor.rgb * hot;
    streakWeight = streakWeight + hot;
  }
  let streak = select(vec3<f32>(0.0), streakAccum / streakWeight, streakWeight > 0.0) * flareIntensity * haze;

  // Ghost reflections (Cooke triplet approx: 3 element surfaces)
  var ghosts = vec3<f32>(0.0);
  let ghostCoeffs = array<f32, 3>(0.35, -0.22, 0.12);
  let ghostColors = array<vec3<f32>, 3>(
    vec3<f32>(1.0, 0.85, 0.7),
    vec3<f32>(0.75, 0.9, 1.0),
    vec3<f32>(1.0, 0.75, 0.85)
  );
  for (var g = 0; g < 3; g = g + 1) {
    let ghostUV = lightPos + (lightPos - uv) * ghostCoeffs[g];
    let ghostSample = textureSampleLevel(readTexture, u_sampler, clamp(ghostUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let ghostLuma = dot(ghostSample.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let ghostHot = smoothstep(threshold + 0.1, threshold + 0.4, ghostLuma);
    let ghostDist = length(uv - ghostUV);
    let ghostFalloff = exp(-ghostDist * 4.0);
    ghosts = ghosts + ghostSample.rgb * ghostHot * ghostFalloff * ghostColors[g] * flareIntensity * 0.5;
  }

  // Diffraction starburst from bright source
  let spike = diffraction_spike(lightDir, flareIntensity * (1.0 + treble)) * exp(-lightDist * 1.5);

  // Scatter halo around light source
  let halo = exp(-lightDist * lightDist * 8.0) * flareIntensity * 0.6 * vec3<f32>(1.0, 0.92, 0.82);

  // Rainbow chromatic aberration on ghosts
  let rGhost = ghosts * vec3<f32>(1.3, 0.85, 0.7) * (1.0 + chromaAmt * 12.0 * bass);
  let bGhost = ghosts * vec3<f32>(0.7, 0.85, 1.3) * (1.0 + chromaAmt * 12.0 * treble);
  let chromaGhosts = vec3<f32>(rGhost.r, ghosts.g, bGhost.b);

  // Combine all flare components
  let flareTotal = streak + chromaGhosts + halo + vec3<f32>(spike);

  // Mids add warm gold atmospheric tint
  let goldTint = vec3<f32>(1.0, 0.82, 0.55) * mids * 0.25 * flareIntensity * haze;

  var finalRGB = sourceColor.rgb + flareTotal + goldTint;

  // Film grain
  finalRGB = finalRGB + grain(uv, time);

  finalRGB = aces_tonemap(finalRGB);

  // Alpha = flare intensity × atmospheric_transmission × depth
  let alpha = clamp(length(flareTotal) * 0.6 * haze * depth + sourceColor.a * 0.3, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(flareTotal, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
