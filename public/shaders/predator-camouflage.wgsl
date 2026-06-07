// ═══════════════════════════════════════════════════════════════════
//  Predator Camouflage
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, chromatophore-simulation, thermal-vision, chromatic-separation, semantic-alpha
//  Complexity: Very High
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (4-Agent Swarm Upgrade)
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

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn thermalMap(t: f32) -> vec3<f32> {
  return vec3<f32>(
    smoothstep(0.0, 0.35, t) * 0.9 + smoothstep(0.35, 0.7, t) * 0.4,
    smoothstep(0.15, 0.55, t) * 0.7 + smoothstep(0.55, 0.9, t) * 0.5,
    smoothstep(0.4, 0.8, t) * 0.8 + smoothstep(0.8, 1.0, t) * 0.6
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let cloakRadius = mix(0.08, 0.70, u.zoom_params.x);
  let refractionStrength = u.zoom_params.y * 0.10;
  let chromatophoreSpeed = 0.2 + u.zoom_params.z * 6.0;
  let noiseScale = mix(3.0, 24.0, u.zoom_params.w);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let cloakMask = 1.0 - smoothstep(cloakRadius * 0.7, cloakRadius, dist);
  let rim = smoothstep(cloakRadius * 0.5, cloakRadius * 0.9, dist) * cloakMask;

  let chr1 = noise(uv * noiseScale + vec2<f32>(time * chromatophoreSpeed, -time * 0.6) + audio.x * 2.0);
  let chr2 = noise(uv * (noiseScale * 1.6) - vec2<f32>(time * 0.9, time * chromatophoreSpeed));
  let pigment = (chr1 + chr2 - 1.0) * (0.5 + audio.x);
  let sacScale = smoothstep(0.35, 0.65, chr1) * cloakMask;

  let normal = normalize(centered + vec2<f32>(0.001, 0.0));
  let haze = (0.5 + depth * 0.5) * refractionStrength * cloakMask * (0.4 + pigment);
  let offset = normal * haze;
  let refractedUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

  let chrSep = normal * (0.004 + audio.z * 0.012) * rim * (1.0 + sacScale);
  let rUV = clamp(refractedUV + chrSep, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = refractedUV;
  let bUV = clamp(refractedUV - chrSep, vec2<f32>(0.0), vec2<f32>(1.0));

  var sampleColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );

  let lum = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));
  let heatSource = lum * 0.6 + (1.0 - dist * 1.2) * 0.4 * cloakMask;
  let thermal = thermalMap(clamp(heatSource + audio.y * 0.15, 0.0, 1.0));

  let chromaTint = mix(vec3<f32>(0.08, 0.75, 0.95), vec3<f32>(0.6, 0.9, 0.25), chr1);
  sampleColor = mix(sampleColor, sampleColor * 0.5 + thermal * 0.55 + chromaTint * 0.25, cloakMask * 0.6);
  sampleColor += chromaTint * rim * (0.12 + audio.y * 0.2) + thermal * sacScale * 0.15;

  let bloom = thermal * rim * sacScale * (0.3 + audio.x * 0.3);
  sampleColor += bloom;

  sampleColor = acesToneMap(sampleColor * (1.0 + cloakMask * 0.25));

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, refractedUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.15 + cloakMask * 0.75, 0.35), 0.0, 1.0);

  let thermalContrast = abs(heatSource - 0.5) * 2.0;
  let semantic_alpha = clamp(cloakMask * thermalContrast * (0.4 + depth * 0.6), 0.25, 0.98);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(sampleColor, semantic_alpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(cloakMask, rim, pigment, semantic_alpha));
}
