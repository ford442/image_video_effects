// ================================================================
//  Glass Brick Wall
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            caustic-refraction, depth-layers, chromatic-dispersion, fbm-texture
//  Complexity: Very High
//  Chunks From: glass-brick-wall
//  Created: 2026-05-31
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=BrickSize, y=Distortion, z=MortarSize, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

fn safeNormalize3(v: vec3<f32>) -> vec3<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
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

fn voronoiF2F1(p: vec2<f32>, time: f32) -> vec2<f32> {
  let n = floor(p);
  let f = fract(p);
  var minDist1 = 100.0;
  var minDist2 = 100.0;
  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let g = vec2<f32>(f32(i), f32(j));
      let h = hash22(n + g);
      let o = vec2<f32>(sin(h.x * TAU + time * 0.15), cos(h.y * TAU + time * 0.12)) * 0.25 + 0.5;
      let r = g + o - f;
      let d = dot(r, r);
      if (d < minDist1) {
        minDist2 = minDist1;
        minDist1 = d;
      } else if (d < minDist2) {
        minDist2 = d;
      }
    }
  }
  return vec2<f32>(sqrt(minDist1), sqrt(minDist2));
}

fn causticPattern(p: vec2<f32>, time: f32, freq: f32) -> f32 {
  // Multi-frequency caustic simulation
  let c1 = sin(p.x * freq + time * 1.5) * cos(p.y * freq * 0.7 + time * 1.2);
  let c2 = sin(p.x * freq * 1.3 - time * 2.0) * cos(p.y * freq * 1.1 + time * 0.8);
  let c3 = sin(p.x * freq * 0.8 + time * 0.7) * cos(p.y * freq * 1.5 - time * 1.1);
  let vor = voronoiF2F1(p * freq * 0.3, time);
  let voroCaustic = pow(vor.y - vor.x, 2.0) * 2.0;
  return max(0.0, (c1 + c2 + c3) / 3.0 * 0.5 + 0.5 + voroCaustic * 0.3);
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn chromaticRefraction(uv: vec2<f32>, normal: vec3<f32>, distortion: f32, offsetScale: f32, time: f32) -> vec3<f32> {
  // Wavelength-dependent refraction (simplified chromatic dispersion)
  let n_r = 1.0 / 1.50;
  let n_g = 1.0 / 1.52;
  let n_b = 1.0 / 1.54;

  let lightDir = vec3<f32>(0.0, 0.0, 1.0);
  let refractR = refract(-lightDir, normal, n_r);
  let refractG = refract(-lightDir, normal, n_g);
  let refractB = refract(-lightDir, normal, n_b);

  let offsetR = refractR.xy * distortion * offsetScale + fbm(uv * 5.0 + time * 0.1, 4) * 0.01;
  let offsetG = refractG.xy * distortion * offsetScale + fbm(uv * 5.0 + vec2<f32>(10.0) + time * 0.12, 4) * 0.008;
  let offsetB = refractB.xy * distortion * offsetScale + fbm(uv * 5.0 + vec2<f32>(20.0) + time * 0.08, 4) * 0.012;

  let sampleR = clamp(uv + offsetR, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleG = clamp(uv + offsetG, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleB = clamp(uv + offsetB, vec2<f32>(0.0), vec2<f32>(1.0));

  return vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, sampleR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, sampleG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, sampleB, 0.0).b
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / dims.y;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let brickSize = mix(10.0, 54.0, u.zoom_params.x);
  let distortion = mix(0.0, 0.12, u.zoom_params.y);
  let mortarSize = mix(0.01, 0.12, u.zoom_params.z);
  let glassDensity = mix(0.6, 2.6, u.zoom_params.w);

  let gridUV = uv * vec2<f32>(brickSize * aspect, brickSize);
  let cellId = floor(gridUV);
  let cell = fract(gridUV) - 0.5;
  let r2 = dot(cell, cell) * 4.0;

  // FBM-perturbed normal for organic glass surface
  let normalNoise = fbm(cell * 4.0 + cellId * 0.5 + time * 0.05, 5) * 0.15;
  let normalXY = cell * -2.0 + vec2<f32>(normalNoise, normalNoise * 0.7);
  let normalZ = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
  let normal = safeNormalize3(vec3<f32>(normalXY, normalZ));
  let mortarMask = smoothstep(0.48 - mortarSize, 0.5, max(abs(cell.x), abs(cell.y)));

  // Depth layers: front and back refraction
  let refractOffset = normal.xy * distortion * (1.0 - mortarMask) * (1.0 + bass * 0.35);
  let frontUV = clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  // Secondary bounce (depth layer)
  let bounceNormal = safeNormalize3(vec3<f32>(normal.xy * 0.5, normal.z));
  let bounceOffset = bounceNormal.xy * distortion * 0.5 * (1.0 - mortarMask);
  let backUV = clamp(frontUV + bounceOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  var color = textureSampleLevel(readTexture, u_sampler, frontUV, 0.0);
  let backColor = textureSampleLevel(readTexture, u_sampler, backUV, 0.0);

  // Blend front and back for depth
  let depthBlend = fbm(cell * 3.0 + time * 0.08, 4) * 0.3 + 0.2;
  color = mix(color, backColor, depthBlend * (1.0 - mortarMask));

  let lightPos = vec3<f32>(mouse * vec2<f32>(aspect, 1.0), 0.55);
  let pixelPos = vec3<f32>(uv * vec2<f32>(aspect, 1.0), 0.0);
  let lightDir = safeNormalize3(lightPos - pixelPos);
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfDir = safeNormalize3(lightDir + viewDir);

  var transmission = 0.45;
  if (mortarMask < 0.5) {
    let cosTheta = max(dot(viewDir, normal), 0.0);
    let fresnel = fresnelSchlick(cosTheta, 0.04);
    let thickness = 0.08 + r2 * 0.16 + fbm(cell * 6.0 + time * 0.1, 5) * 0.05;
    let glassTint = mix(
      vec3<f32>(0.94, 0.97, 1.0),
      vec3<f32>(0.98, 0.85, 1.0),
      0.5 + 0.5 * sin(time * 0.35 + cellId.x * 0.4 + fbm(cellId * 0.5 + time * 0.1, 4) * PI)
    );
    let absorption = exp(-(1.0 - glassTint) * thickness * glassDensity);
    transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;

    // Enhanced specular with FBM roughness
    let roughness = fbm(cell * 3.0 + time * 0.05, 4) * 0.5 + 0.5;
    let specular = pow(max(dot(normal, halfDir), 0.0), 18.0 * roughness + 4.0) * (0.22 + mids * 0.45);

    // Caustic refraction patterns
    let causticUV = uv * 6.0 + cellId * 0.3;
    let caustic1 = causticPattern(causticUV, time * 0.5 + bass * 2.0, 3.0 + bass * 2.0);
    let caustic2 = causticPattern(causticUV * 1.5 + vec2<f32>(5.0), time * 0.3 + mids * 1.5, 2.0 + mids * 2.0);
    let caustic3 = causticPattern(causticUV * 0.7, time * 0.7 + treble, 4.0 + treble * 3.0);
    let totalCaustic = caustic1 * 0.5 + caustic2 * 0.3 + caustic3 * 0.2;

    let curvature = smoothstep(0.0, 0.6, r2);
    let causticIntensity = totalCaustic * (0.35 + curvature * 0.85) * (1.0 + treble * 0.5);
    let causticColor = vec3<f32>(1.0, 0.9, 0.7) + vec3<f32>(-0.2, 0.1, 0.4) * sin(time * 0.5 + cellId.x);

    // Chromatic dispersion through the brick
    let chromatic = chromaticRefraction(uv, normal, distortion, 1.0 - mortarMask, time);
    let chromaticMix = treble * 0.3 * (1.0 - fresnel);
    color = vec4<f32>(mix(color.rgb, chromatic, chromaticMix), color.a);

    color = vec4<f32>(color.rgb * glassTint * transmission + specular + causticColor * causticIntensity * 1.2, transmission);

    // Internal reflections (depth layers)
    let internalReflect = fbm(cell * 8.0 + time * 0.2, 4) * 0.1 * (1.0 - fresnel);
    color = vec4<f32>(color.rgb + glassTint * internalReflect, color.a);
  } else {
    color = vec4<f32>(color.rgb * 0.42, 0.42);
  }

  let finalAlpha = clamp(color.a + (1.0 - mortarMask) * 0.10, 0.15, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, frontUV, 0.0).r;
  let outDepth = clamp(mix(baseDepth, baseDepth * 0.45 + (1.0 - mortarMask) * 0.45, 0.25), 0.0, 1.0);

  // Premultiplied alpha
  let premultColor = color.rgb * finalAlpha;
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(premultColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(1.0 - mortarMask, transmission, abs(refractOffset.x) + abs(refractOffset.y), finalAlpha));
}
