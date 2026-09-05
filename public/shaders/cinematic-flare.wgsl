// Cinematic Flare — Cooke triplet ghosts, 6-blade diffraction starburst, anamorphic streaks, and Cauchy dispersion.
// A/C stores ACES display RGBA for continuous persistence of vision; B is unused; depth passes through source depth.

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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

fn diffractionSpike(dir: vec2<f32>, intensity: f32) -> f32 {
  let angle = atan2(dir.y, dir.x);
  var spike = 0.0;
  for (var b = 0; b < 6; b = b + 1) {
    let bladeAngle = f32(b) * 0.5235987756;
    let diff = angle - bladeAngle;
    let sinc = sin(diff * 8.0) / (diff * 8.0 + 0.001);
    spike = spike + sinc * sinc;
  }
  return spike * intensity * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let flareIntensity = (0.2 + u.zoom_params.x * 2.2) * (1.0 + bass * 0.45);
  let streakLen = 0.05 + u.zoom_params.y * 0.45;
  let chromaShift = 0.005 + u.zoom_params.z * 0.045;
  let threshold = 0.2 + u.zoom_params.w * 0.65;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let haze = mix(0.5, 1.0, depth);

  let mouse = u.zoom_config.yz;
  let hasMouse = mouse.x >= 0.0 && mouse.x <= 1.0 && mouse.y >= 0.0 && mouse.y <= 1.0;
  let lightPos = select(vec2<f32>(0.5, 0.5), mouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  let uvAspect = uv * aspectVec;
  let lightAspect = lightPos * aspectVec;
  let toLight = lightAspect - uvAspect;
  let lightDist = length(toLight);
  let lightDir = normalize(toLight + vec2<f32>(0.0001));

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Click ripple interaction
  var rippleDeflect = vec2<f32>(0.0);
  var rippleLight = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.35 + bass * 0.1);
      let ring = sin((rd - front) * 65.0) * exp(-abs(rd - front) * 28.0) * exp(-age * 1.2);
      rippleDeflect += rDelta / max(rd, 0.0001) * ring * 0.015;
      rippleLight += abs(ring) * 0.2;
    }
  }

  // Anamorphic horizontal streak with Cauchy dispersion
  var streakAccum = vec3<f32>(0.0);
  var streakWeight = 0.0;
  let streakSamples = 14;
  let streakAxis = vec2<f32>(1.0, 0.0);
  let heldStreakBoost = select(1.0, 1.6, held);

  for (var s = 0; s < streakSamples; s = s + 1) {
    let t = (f32(s) / f32(streakSamples - 1)) - 0.5;
    let offsetUV = uv + streakAxis * (t * streakLen * heldStreakBoost) + rippleDeflect;
    let clampedUV = clamp(offsetUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleColor = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);
    let sampleLuma = dot(sampleColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let hot = smoothstep(threshold, threshold + 0.2, sampleLuma);

    // Spectral dispersion across streak samples
    let disp = t * chromaShift;
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(offsetUV + vec2<f32>(disp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(offsetUV - vec2<f32>(disp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let dispersed = vec3<f32>(rSample, sampleColor.g, bSample);

    streakAccum += dispersed * hot;
    streakWeight += hot;
  }
  let streak = select(vec3<f32>(0.0), streakAccum / max(streakWeight, 0.0001), streakWeight > 0.0) * flareIntensity * haze;

  // Cooke triplet ghosts: 3 elements with anti-reflection coating colors
  var ghosts = vec3<f32>(0.0);
  let ghostCoeffs = array<f32, 3>(0.38, -0.24, 0.14);
  let ghostColors = array<vec3<f32>, 3>(
    vec3<f32>(1.0, 0.82, 0.65),
    vec3<f32>(0.65, 0.88, 1.0),
    vec3<f32>(0.95, 0.65, 0.9)
  );

  for (var g = 0; g < 3; g = g + 1) {
    let ghostUV = lightPos + (lightPos - uv) * ghostCoeffs[g] + rippleDeflect;
    let ghostSample = textureSampleLevel(readTexture, u_sampler, clamp(ghostUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let ghostLuma = dot(ghostSample.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let ghostHot = smoothstep(threshold + 0.05, threshold + 0.35, ghostLuma);
    let ghostDist = length((uv - ghostUV) * aspectVec);
    let ghostFalloff = exp(-ghostDist * 5.0);

    // Cauchy dispersion on ghosts
    let ghostDisp = chromaShift * (f32(g) + 1.0) * 0.5;
    let rG = textureSampleLevel(readTexture, u_sampler, clamp(ghostUV + vec2<f32>(ghostDisp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bG = textureSampleLevel(readTexture, u_sampler, clamp(ghostUV - vec2<f32>(ghostDisp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let dispersedGhost = vec3<f32>(rG, ghostSample.g, bG);

    ghosts += dispersedGhost * ghostHot * ghostFalloff * ghostColors[g] * flareIntensity * 0.6;
  }

  // 6-blade diffraction starburst from bright light source
  let spike = diffractionSpike(lightDir, flareIntensity * (0.8 + treble * 0.4)) * exp(-lightDist * 1.8);

  // Mie scattering halo around light source
  let haloRadius = 7.0 / max(0.5 + bass * 0.5, 0.1);
  let halo = exp(-lightDist * lightDist * haloRadius) * flareIntensity * 0.65 * vec3<f32>(1.0, 0.92, 0.8);

  // Combine flare components
  let flareTotal = streak + ghosts + halo + vec3<f32>(spike) + vec3<f32>(rippleLight);
  let goldAtmosphere = vec3<f32>(1.0, 0.85, 0.55) * mids * 0.3 * flareIntensity * haze;

  // Exact previous frame history load for persistence of vision
  let history = historyAt(uv - rippleDeflect * 0.5, resolution);

  var hdr = sourceColor.rgb + flareTotal + goldAtmosphere;
  hdr += history.rgb * 0.06;

  // Film grain
  let grain = (hash12(uv * resolution.xy + time * 10.0) - 0.5) * 0.025 * (1.0 + treble * 0.5);
  hdr += vec3<f32>(grain);

  let flareLuma = dot(flareTotal, vec3<f32>(0.2126, 0.7152, 0.0722));
  let alpha = clamp(sourceColor.a * 0.5 + flareLuma * 0.5 * haze + rippleLight * 0.1, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
