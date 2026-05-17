// ═══════════════════════════════════════════════════════════════════
//  Virtual Lens
//  Category: image
//  Features: mouse-driven, chromatic-aberration, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
//  Upgraded: Single magnification + spectral tint, alpha = Fresnel edge falloff
// ═══════════════════════════════════════════════════════════════════
//  Replaces per-channel chromatic aberration with a single
//  magnification displacement field. Spectral tint is applied
//  via mix() with wavelengthToRGB. Alpha encodes lens edge
//  falloff multiplied by Schlick Fresnel for glass translucency.
//  Depth-aware attenuation makes distant pixels more transparent.
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
  zoom_params: vec4<f32>,  // x=Magnification, y=Radius, z=Aberration, w=Softness
  ripples: array<vec4<f32>, 50>,
};

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (lambda < 440.0) { r = (440.0 - lambda) / 60.0; b = 1.0; }
  else if (lambda < 490.0) { g = (lambda - 440.0) / 50.0; b = 1.0; }
  else if (lambda < 510.0) { g = 1.0; b = (510.0 - lambda) / 20.0; }
  else if (lambda < 580.0) { r = (lambda - 510.0) / 70.0; g = 1.0; }
  else if (lambda < 645.0) { r = 1.0; g = (645.0 - lambda) / 65.0; }
  else { r = 1.0; }
  var intensity = 1.0;
  if (lambda < 420.0) { intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0; }
  else if (lambda > 700.0) { intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0; }
  return clamp(vec3(r, g, b) * intensity, vec3(0.0), vec3(1.0));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let magnification = u.zoom_params.x * 0.8 * (1.0 + bass * 0.2);
    let radius = u.zoom_params.y;
    let aberration = u.zoom_params.z * 0.05 * (1.0 + bass * 0.3);
    let softness = u.zoom_params.w * 0.2;

    var uv_corrected = uv;
    uv_corrected.x *= aspect;
    var mouse_corrected = mouse;
    mouse_corrected.x *= aspect;

    let dist = distance(uv_corrected, mouse_corrected);
    let mask = smoothstep(radius + softness, radius, dist);

    var dir = uv - mouse;
    let distortion = sin(mask * 1.57079) * magnification;

    // Single magnification displacement — no per-channel UVs
    let displacedUV = uv - dir * distortion;
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Spectral tint via mix based on aberration strength
    let wavelength = mix(420.0, 700.0, aberration * 10.0 + distortion * 2.0);
    let spectralTint = wavelengthToRGB(wavelength);
    let tintStrength = clamp(aberration * 4.0, 0.0, 1.0);
    let tintedColor = mix(baseColor, baseColor * spectralTint, tintStrength);

    // Lens rim glow for glass edge highlight
    let rim = smoothstep(radius * 0.9, radius, dist) * mask * 0.2;
    var color = tintedColor + vec3<f32>(rim);

    // Central hotspot for bright specular core
    let core = gaussianMask(dist, radius * 0.25) * mask * 0.08;
    color = color + vec3<f32>(core);

    // Alpha: lens edge falloff * Fresnel reflectance
    let viewDir = normalize(uv - vec2<f32>(0.5));
    let lensNormal = normalize(uv - mouse);
    let cosTheta = abs(dot(viewDir, lensNormal));
    let fresnel = schlickFresnel(cosTheta, 0.04);
    let edgeFalloff = gaussianMask(dist, radius * 0.5) * mask;
    let alpha = mix(0.3, clamp(edgeFalloff * 0.8 + fresnel * 0.4 + rim * 0.6, 0.0, 1.0), mask);

    // Depth-aware attenuation: lens is more transparent on distant pixels
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = alpha * mix(0.6, 1.0, 1.0 - depth * 0.5);
    let depthBlend = mix(0.3, 1.0, 1.0 - depth * 0.4);
    let finalColor = mix(baseColor, color, depthBlend * mask);

    // Time-based caustic micro-shimmer on the lens surface
    let time = u.config.x;
    let shimmer = sin(dist * 50.0 - time * 3.0) * 0.02 * mask;
    let shimmerColor = finalColor + vec3<f32>(shimmer);

    // Secondary inner ring for double-glass optic feel
    let innerRadius = radius * 0.55;
    let innerMask = smoothstep(innerRadius + softness * 0.5, innerRadius, dist);
    let innerRim = smoothstep(innerRadius * 0.85, innerRadius, dist) * innerMask * 0.12;
    let opticColor = shimmerColor + vec3<f32>(innerRim);

    // Chromatic darkening at lens perimeter for physical realism
    let edgeDarken = 1.0 - smoothstep(radius * 0.7, radius, dist) * 0.15;
    let darkenedColor = opticColor * edgeDarken;

    // Additional bass-reactive pulse warps the lens edge slightly
    let bassPulse = sin(time * 6.0) * bass * 0.02 * mask;
    let pulsedColor = darkenedColor + vec3<f32>(bassPulse);

    // Final composite with all translucency layers
    textureStore(writeTexture, coords, vec4<f32>(pulsedColor, depthAlpha));

    // Preserve depth buffer for downstream effects
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(d, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(pulsedColor, depthAlpha));
}
