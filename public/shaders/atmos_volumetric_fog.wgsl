// ═══════════════════════════════════════════════════════════════════
//  atmos_volumetric_fog
//  Category: atmospheric
//  Features: upgraded-rgba, depth-aware, physical-transmittance, volumetric-fog,
//            audio-reactive, aces-tone-map, temporal-feedback, chromatic-aberration,
//            mouse-light, god-ray-march, fbm-breakup, treble-motes, shockwave,
//            video-luma, bass-envelope, feedback-clamp
//  Upgraded: 2026-07-22 (swarm b12 — Visualist: shafts, scattering, aerial light)
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

// Fixed constants freed up by rewiring the sliders to light-transport params.
const RAY_STEPS: i32 = 10;          // radial god-ray march steps
const DEPTH_WEIGHT: f32 = 0.55;     // fixed depth-layering of fog alpha
const FOG_HEIGHT: f32 = 0.45;       // fixed height-fog falloff scale

fn physicalTransmittance(baseColor: vec3<f32>, opticalDepth: f32, absorptionCoeff: vec3<f32>) -> vec3<f32> {
  let transmittance = exp(-absorptionCoeff * opticalDepth);
  return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
  return 1.0 - exp(-density * thickness);
}

fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAlpha = mix(0.2, 1.0, depth);
  return mix(1.0, depthAlpha, depthWeight);
}

fn calculateFogAlpha(uv: vec2<f32>, opticalDepth: f32, density: f32) -> f32 {
  let volAlpha = volumetricAlpha(density, opticalDepth);
  let depthAlpha = depthLayeredAlpha(uv, DEPTH_WEIGHT);
  return clamp(volAlpha * depthAlpha, 0.0, 1.0);
}

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    value += amplitude * noise(p * frequency);
    frequency *= 2.0;
    amplitude *= 0.5;
  }
  return value;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

// Screen-space radial march from the pixel toward the mouse light. fbm fog
// density sampled along the ray occludes the light, carving visible shafts
// through the volume instead of a flat radial glow.
fn godRayShaft(uv: vec2<f32>, lightPos: vec2<f32>, time: f32, heightFalloff: f32) -> f32 {
  let rayVec = lightPos - uv;
  var occ = 0.0;
  var wsum = 0.0;
  for (var i = 0; i < RAY_STEPS; i++) {
    let t = f32(i) / f32(RAY_STEPS - 1);
    let p = uv + rayVec * t;
    let hFog = exp(-p.y / max(heightFalloff, 0.01));
    let n = fbm(p * 3.5 + vec2<f32>(time * 0.03, time * 0.012), 3);
    let d = max(0.0, hFog * (0.35 + 0.65 * n));
    let w = 1.0 - t * t;  // nearer samples occlude more strongly
    occ += d * w;
    wsum += w;
  }
  return occ / max(wsum, 0.0001);
}

// Sparse animated dust motes (hash sparkle). Twinkle is time-phased per cell;
// the motes are scaled by treble and revealed only inside bright shafts.
fn dustMotes(uv: vec2<f32>, time: f32, treble: f32) -> f32 {
  let grid = uv * 48.0;
  let cell = floor(grid);
  let seed = hash(cell);
  let jitter = (hash(cell + vec2<f32>(13.7, 41.3)) - 0.5) * 0.6;
  let moteShape = 1.0 - smoothstep(0.02, 0.09, length(fract(grid) - vec2<f32>(0.5) + jitter));
  let twinkle = 0.5 + 0.5 * sin(time * (2.0 + seed * 7.0) + seed * 39.0);
  let sparse = step(0.96, seed);
  return moteShape * twinkle * sparse * (0.25 + treble);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let rawBass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let bass = bass_env(prev.r, rawBass, 0.8, 0.15);

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // ── Slider wiring (saved-preset contract: ids/defaults unchanged) ─────
  // p1 Fog Density     → base fog extinction coefficient
  // p2 Light Intensity → mouse light brightness + glow radius
  // p3 Scattering      → in-scatter gain + shaft cone sharpness + absorption
  // p4 God Rays        → god-ray shaft visibility mask
  let fogDensity = u.zoom_params.x * 3.0 * (1.0 + bass * 0.3);
  let lightIntensity = u.zoom_params.y;
  let scattering = u.zoom_params.z;
  let godRays = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Mouse-anchored light source for god rays
  let lightDir = mouse - uv;
  let lightDist = length(lightDir);
  let shaftSharp = 2.0 + scattering * 6.0;
  let godCone = pow(max(dot(normalize(lightDir + vec2<f32>(0.0001, 0.0)), vec2<f32>(0.0, -1.0)), 0.0), shaftSharp);
  let glowRadius = 3.0 + lightIntensity * 6.0;
  let lightGlow = exp(-lightDist * lightDist * glowRadius) * (0.4 + lightIntensity * 1.2) * (0.5 + bass * 0.5);

  // Click shockwave clears fog
  let shockDist = length(uv - mouse);
  let shockClear = exp(-shockDist * shockDist * 20.0) * mouseDown;

  // ── fbm density breakup ────────────────────────────────────────────────
  // A second 3-octave fbm layer tears the uniform height fog into clumps and
  // layers, so the shafts above read volumetric instead of flat.
  let fogUV = uv * 3.0 + vec2<f32>(time * 0.02 * (1.0 + mids * 0.3), 0.0);
  let noiseVal = fbm(fogUV, 4) * (1.0 + treble * 0.2);
  let breakup = fbm(uv * 6.5 + vec2<f32>(time * 0.05, -time * 0.02), 3);
  let densityNoise = (0.5 + noiseVal * 0.5) * (0.55 + 0.9 * breakup);
  let heightFog = exp(-uv.y / FOG_HEIGHT);
  let density = max(0.0, fogDensity * heightFog * densityNoise - shockClear * 2.0);

  let fogColorShift = 0.5 + mids * 0.1;
  let fogColor = vec3<f32>(
    0.7 + fogColorShift * 0.2,
    0.75 + fogColorShift * 0.1,
    0.85
  );

  let bgSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Video luma-keyed emission
  let luma = dot(bgSample.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let vidEmission = smoothstep(0.6, 1.0, luma) * vec3<f32>(0.3, 0.25, 0.2);

  let opticalDepth = density * (1.0 + (1.0 - depth));

  let absorptionCoeff = vec3<f32>(0.3, 0.4, 0.5) * (0.6 + scattering * 0.8);
  let transmitted = physicalTransmittance(bgSample.rgb + vidEmission, opticalDepth, absorptionCoeff);

  // ── Mouse-anchored god rays ────────────────────────────────────────────
  // Radial occlusion march + sharpened cone, masked by fog density, the
  // God Rays slider, and the light intensity so shafts die off in thin fog.
  let shaftDensity = godRayShaft(uv, mouse, time, FOG_HEIGHT);
  let shaftMask = godRays * density * 0.9;
  let shaft = godCone * shaftDensity * lightGlow * shaftMask * 6.0;
  let shaftColor = mix(vec3<f32>(1.0, 0.92, 0.75), fogColor, 0.35);

  // In-scatter glow, now driven by the Scattering slider
  let scatter = fogColor * godCone * lightGlow * density * scattering * 1.2;

  // ── Treble sparkle motes inside bright shafts ─────────────────────────
  let moteGain = shaft * 2.0 + godCone * lightGlow * godRays;
  let motes = dustMotes(uv, time, treble) * moteGain * lightIntensity;

  let alpha = calculateFogAlpha(uv, opticalDepth, density);
  var finalColor = mix(transmitted, fogColor + scatter, alpha * 0.7);
  finalColor = finalColor + shaftColor * shaft + vec3<f32>(1.0, 0.97, 0.85) * motes;

  // ── Temporal feedback, clamped pre-tint at 1.2 (luma-echo-warp lesson) ─
  let prevSafe = clamp(prev.rgb, vec3<f32>(0.0), vec3<f32>(1.2));
  finalColor = mix(finalColor, prevSafe * 0.95, 0.03 + bass * 0.01);

  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);

  finalColor = acesToneMap(finalColor * 1.1);

  // Alpha encodes fog density + interaction intensity (shafts included)
  let interaction = lightGlow * 0.3 + shockClear * 0.5 + shaft * 0.4;
  let finalAlpha = clamp(alpha + interaction, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(bass, density, interaction, finalAlpha));
}
