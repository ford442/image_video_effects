// ================================================================
//  Hex Lens Interactive
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, chromatic-aberration,
//            hexagonal-bokeh, chromatic-dispersion, diffraction-patterns
//  Complexity: Very High
//  Chunks From: hex-lens
//  Created: 2026-05-30
//  Upgraded: 2026-06-28
//  By: The Complexity Architect
// ================================================================

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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=TileSize, y=LensZoom, z=Rotation, w=MouseInfluence
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453;
  return fract(h);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var total = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    total = total + amplitude * noise2(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.1;
  }
  return total;
}

fn hexBokeh(uv: vec2<f32>, center: vec2<f32>, radius: f32, time: f32, bass: f32) -> f32 {
  let diff = uv - center;
  let angle = atan2(diff.y, diff.x);
  // Hexagonal blur kernel
  let hexAngle = TAU / 6.0;
  let sector = floor(angle / hexAngle + 0.5);
  let sectorAngle = sector * hexAngle;
  let hexDist = abs(diff.x * cos(sectorAngle) + diff.y * sin(sectorAngle));
  let perpDist = abs(-diff.x * sin(sectorAngle) + diff.y * cos(sectorAngle));
  let hexShape = max(hexDist, perpDist * 0.866);

  // FBM-perturbed bokeh edge
  let edgeNoise = fbm(diff * 8.0 + time * 0.2, 4);
  return 1.0 - smoothstep(radius * 0.7, radius * (1.0 + edgeNoise * 0.3), hexShape);
}

fn chromaticDispersion(uv: vec2<f32>, center: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
  let diff = uv - center;
  let dist = length(diff);
  let angle = atan2(diff.y, diff.x);

  // Wavelength-dependent offsets (simplified)
  let rOffset = diff * (1.0 + strength * 0.015);
  let gOffset = diff * (1.0 + strength * 0.010);
  let bOffset = diff * (1.0 + strength * 0.005);

  // Add FBM warp to chromatic split
  let warp = fbm(uv * 6.0 + time * 0.1, 4) * strength * 0.005;

  let rUV = clamp(center + rOffset + vec2<f32>(warp, -warp * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(center + gOffset + vec2<f32>(-warp * 0.3, warp * 0.3), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(center + bOffset + vec2<f32>(warp * 0.5, -warp), vec2<f32>(0.0), vec2<f32>(1.0));

  return vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );
}

fn diffractionPattern(uv: vec2<f32>, center: vec2<f32>, hexRadius: f32, time: f32, treble: f32) -> f32 {
  let diff = uv - center;
  let dist = length(diff);
  let angle = atan2(diff.y, diff.x);

  // Hexagonal aperture diffraction spikes
  var spikes = 0.0;
  for (var i = 0; i < 6; i = i + 1) {
    let spikeAngle = f32(i) * PI / 3.0;
    let angleDiff = abs(fract((angle - spikeAngle) / PI + 0.5) - 0.5) * PI;
    let spike = smoothstep(0.05 + treble * 0.03, 0.0, angleDiff) * smoothstep(hexRadius * 3.0, hexRadius * 0.5, dist);
    spikes = spikes + spike;
  }

  // Concentric diffraction rings
  let ringFreq = 15.0 + treble * 10.0;
  let rings = sin(dist * ringFreq - time * 2.0) * 0.5 + 0.5;
  let ringFalloff = smoothstep(hexRadius * 2.0, hexRadius * 0.3, dist);

  return spikes * 0.4 + rings * ringFalloff * 0.2 * treble;
}

fn hexStarPattern(uv: vec2<f32>, time: f32, freq: f32) -> f32 {
  let angle = atan2(uv.y, uv.x);
  let dist = length(uv);
  let sixFold = cos(angle * 6.0 + time * 0.5);
  let twelveFold = cos(angle * 12.0 - time * 0.3) * 0.5;
  return (sixFold + twelveFold) * smoothstep(0.5, 0.0, dist) * 0.3;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let scale = mix(8.0, 38.0, u.zoom_params.x);
  let zoomAmount = mix(1.0, 4.5, u.zoom_params.y);
  let rotation = u.zoom_params.z * TAU + time * 0.25 * (0.2 + mids);
  let mouseInfluence = u.zoom_params.w;

  let axial = vec2<f32>(1.7320508, 1.0);
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let scaled = uvAspect * scale;

  let gridA = (fract(scaled / axial) - 0.5) * axial;
  let idA = floor(scaled / axial);
  let shifted = scaled - axial * 0.5;
  let gridB = (fract(shifted / axial) - 0.5) * axial;
  let idB = floor(shifted / axial);

  let distA = dot(gridA, gridA);
  let distB = dot(gridB, gridB);
  let useB = distB < distA;

  let local = select(gridA, gridB, useB);
  let cellId = select(idA, idB + 0.5, useB);
  let centerScaled = select((idA + 0.5) * axial, (idB + 0.5) * axial + axial * 0.5, useB);
  let centerUV = vec2<f32>(centerScaled.x / scale / aspect, centerScaled.y / scale);

  let mouseVec = (mouse - centerUV) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(mouseVec);
  let influence = (1.0 - smoothstep(0.0, 0.55, mouseDist)) * mouseInfluence;
  let hexMask = 1.0 - smoothstep(0.42, 0.52, length(local));

  // FBM-perturbed rotation
  let rotNoise = fbm(local * 3.0 + cellId * 0.5 + time * 0.1, 4) * 0.3;
  let rotLocal = rotate(local, rotation * influence + rotNoise * influence);
  let zoom = mix(1.0, 1.0 / zoomAmount, influence);

  // Domain-warped refracted coordinates
  let warpStrength = influence * 0.02 * (1.0 + bass * 0.5);
  let warpUV = local * 2.0 + time * 0.15;
  let warpOffset = vec2<f32>(
    fbm(warpUV + vec2<f32>(0.0, 0.0), 4),
    fbm(warpUV + vec2<f32>(5.2, 1.3), 4)
  ) * warpStrength;

  let refractedScaled = centerScaled + rotLocal * zoom + warpOffset * scale;
  let refractedUV = clamp(vec2<f32>(refractedScaled.x / scale / aspect, refractedScaled.y / scale), vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic dispersion with wavelength-dependent refraction
  let chromaticStrength = (0.006 + 0.010 * treble) * influence;
  var finalColor = chromaticDispersion(refractedUV, centerUV, chromaticStrength, time);

  // Hexagonal bokeh overlay
  let bokehRadius = 0.08 + influence * 0.05 + bass * 0.02;
  let bokeh = hexBokeh(uv, centerUV, bokehRadius, time, bass);
  let bokehColor = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0).rgb;
  finalColor = mix(finalColor, bokehColor, bokeh * influence * 0.3);

  // Diffraction pattern (starburst)
  let diffraction = diffractionPattern(uv, centerUV, 0.06, time, treble);
  let diffColor = vec3<f32>(1.0, 0.9, 0.7) * diffraction * influence;
  finalColor = finalColor + diffColor;

  // Enhanced rim with hex star pattern
  let rim = smoothstep(0.30, 0.50, length(local)) * hexMask;
  let starPattern = hexStarPattern(local * 2.0, time, 1.0);
  let shimmer = hash12(cellId + vec2<f32>(time * 0.7, 0.0));
  let honeyTint = mix(
    vec3<f32>(0.12, 0.75, 1.0),
    vec3<f32>(1.0, 0.45, 0.85),
    0.35 + bass * 0.4 + fbm(cellId * 2.0 + time * 0.1, 4) * 0.3
  );
  finalColor = finalColor + honeyTint * (rim * (0.18 + 0.18 * shimmer) + influence * 0.10 + starPattern * influence * 0.15);

  // FBM-based lens distortion vignette
  let vignette = fbm(uv * 3.0 + time * 0.05, 5);
  finalColor = finalColor * (0.9 + vignette * 0.2 * influence);

  // Particle sparkle from treble (hex-grid sparkle)
  let sparkleGrid = hash12(floor(gid.xy / 3u) + vec2<f32>(time * 12.0, time * 8.0));
  let sparkle = smoothstep(0.995, 1.0, sparkleGrid) * treble * hexMask * 2.0;
  finalColor = finalColor + vec3<f32>(sparkle);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, refractedUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, baseDepth * 0.4 + influence * 0.5, 0.30), 0.0, 1.0);
  let finalAlpha = clamp(0.70 + influence * 0.18 + rim * 0.10 + bokeh * 0.05 + diffraction * 0.1, 0.48, 0.98);

  // Premultiplied alpha
  let premultColor = finalColor * finalAlpha;
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(premultColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(influence, hexMask, rim + bokeh, finalAlpha));
}
