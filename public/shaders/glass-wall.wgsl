// ═══════════════════════════════════════════════════════════════
// Glass Wall — Upgraded with Alpha-Channel Translucency Blending
// Category: interactive-mouse
// Features: refraction, spectral-tint, upgraded-rgba
// Upgraded: 2026-05-17
// ═══════════════════════════════════════════════════════════════

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
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// ═══ Math Snippets ═══
fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

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

fn glassDepthBlend(depth: f32, edgeBlend: f32) -> f32 {
  let near = smoothstep(0.0, 0.25, depth);
  let far = 1.0 - smoothstep(0.6, 0.95, depth);
  return near * far * edgeBlend;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  var uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / dims.y;
  var mouse = u.zoom_config.yz;
  let time = u.config.x;

  // Grid configuration
  let gridSize = 20.0;
  let scale = vec2<f32>(gridSize * aspect, gridSize);
  let cellID = floor(uv * scale);
  let cellUV = fract(uv * scale);
  let cellCenter = (cellID + 0.5) / scale;

  // Interaction Vector
  let aspectVec = vec2<f32>(aspect, 1.0);
  let vecToMouse = (mouse - cellCenter) * aspectVec;
  let dist = length(vecToMouse);

  // Interaction Strength with smooth gaussian falloff
  let radius = 0.5;
  let influence = gaussianMask(dist, radius * 0.5);

  // Calculate tilt based on mouse interaction
  var tilt = vec2<f32>(0.0);
  if (dist > 0.001) {
    tilt = normalize(vecToMouse) * influence;
  }

  // Bevel edges for 3D look
  let bevelX = smoothstep(0.0, 0.1, cellUV.x) * (1.0 - smoothstep(0.9, 1.0, cellUV.x));
  let bevelY = smoothstep(0.0, 0.1, cellUV.y) * (1.0 - smoothstep(0.9, 1.0, cellUV.y));
  let bevel = bevelX * bevelY;

  // Single refraction displacement field — no RGB channel splitting
  let refractionStrength = 0.05;
  let offset = tilt * refractionStrength;
  let bevelDistort = (vec2<f32>(0.5) - cellUV) * 0.02 * (1.0 - bevel);
  let finalUV = uv + offset + bevelDistort;

  // Single RGB sample at unified UV
  let baseColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

  // Spectral tint from refraction strength mapped to wavelength
  let tiltMag = length(tilt);
  let wavelength = mix(480.0, 640.0, clamp(tiltMag * 3.0 + bevel * 0.2, 0.0, 1.0));
  let spectralTint = wavelengthToRGB(wavelength);
  let tintStrength = tentAlpha(tiltMag * 6.0) * 0.45;
  var color = mix(baseColor, baseColor * spectralTint, tintStrength);

  // Glass physical properties
  let glassDensity = u.zoom_params.w * 2.0 + 0.5;
  let thickness = 0.05 + (1.0 - bevel) * 0.1 + tiltMag * 0.05;

  // Normal and Fresnel for glass translucency
  let normal = normalize(vec3<f32>(tilt * 2.0 + (vec2<f32>(0.5) - cellUV) * 0.5, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let cosTheta = max(dot(viewDir, normal), 0.0);
  let F0 = 0.04;
  let fresnel = schlickFresnel(cosTheta, F0);

  // Glass color (slight blue tint) with Beer-Lambert absorption
  let glassColor = vec3<f32>(0.93, 0.96, 1.0);
  let absorption = exp(-(vec3<f32>(1.0) - glassColor) * thickness * glassDensity);
  color = color * absorption;

  // Specular Highlight
  let lightDir = normalize(vec3<f32>(vecToMouse, 0.5));
  let spec = pow(max(dot(normal, lightDir), 0.0), 16.0) * influence;
  color = color + vec3<f32>(spec * 0.8);

  // Audio-reactive refraction boost on beat
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  color = color * (1.0 + bass * 0.15 * influence);
  color = mix(color, color * 1.1, mids * bevel * 0.2);

  // Depth-aware compositing: read background depth first
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Extra depth-aware glass edge darkening
  let depthEdge = glassDepthBlend(depth, 1.0 - bevel);
  color = mix(color, color * 0.85, depthEdge * 0.4);

  // Depth-aware compositing: mortar deepens with background depth
  let depthSoft = smoothstep(0.1, 0.6, depth);

  // Grid lines (mortar) with depth-darkening and smooth edges
  let mortarX = smoothstep(0.0, 0.05, cellUV.x) * smoothstep(1.0, 0.95, cellUV.x);
  let mortarY = smoothstep(0.0, 0.05, cellUV.y) * smoothstep(1.0, 0.95, cellUV.y);
  let mortar = mortarX * mortarY;
  let mortarGlow = smoothstep(0.02, 0.06, cellUV.x) + smoothstep(0.02, 0.06, cellUV.y);
  let mortarAlpha = mix(0.15, 0.35, depthSoft);
  color = mix(vec3<f32>(color.rgb * 0.2), color, mortar);

  // Alpha = refraction strength * glass thickness * fresnel modulation
  let refractionAlpha = tiltMag * 2.0 + thickness * 4.0;
  let alpha = clamp(refractionAlpha * (1.0 - fresnel * 0.4) * 0.7 + 0.25, 0.2, 0.88);
  let finalAlpha = mix(alpha, mortarAlpha, 1.0 - mortar);

  textureStore(writeTexture, gid.xy, vec4<f32>(color, finalAlpha));

  let depthOut = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(color, finalAlpha));
}
