// ═══════════════════════════════════════════════════════════════════
//  Luma Glass v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-thickness,
//            sellmeier-dispersion, caustic-trace, fresnel, aces-tone-map
//  Complexity: High
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let refractBase = u.zoom_params.x * (1.0 + bass * 0.25);
  let smoothness = u.zoom_params.y;
  let specularShine = u.zoom_params.z * (1.0 + treble * 0.3);
  let lightDistance = u.zoom_params.w;

  let mouseDeform = (mousePos - uv) * 0.15;
  let deformUV = uv + mouseDeform * smoothness;

  let uvT = clamp(deformUV + vec2<f32>(0.0, -texel.y), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
  let uvB = clamp(deformUV + vec2<f32>(0.0,  texel.y), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
  let uvL = clamp(deformUV + vec2<f32>(-texel.x, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
  let uvR = clamp(deformUV + vec2<f32>( texel.x, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

  let sT = textureSampleLevel(readTexture, u_sampler, uvT, 0.0);
  let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
  let sL = textureSampleLevel(readTexture, u_sampler, uvL, 0.0);
  let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);

  let lumaT = luminance(sT.rgb);
  let lumaB = luminance(sB.rgb);
  let lumaL = luminance(sL.rgb);
  let lumaR = luminance(sR.rgb);

  let dX = lumaR - lumaL;
  let dY = lumaB - lumaT;
  let surfaceNormal = normalize(vec3<f32>(-dX * mix(50.0, 10.0, smoothness), -dY * mix(50.0, 10.0, smoothness), 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let glassThickness = depth * (0.5 + refractBase);
  let nGlass = 1.45 + lumaT * 0.35 + bass * 0.1;
  let nAir = 1.0;
  let eta = nAir / nGlass;

  var spectralColor = vec3<f32>(0.0);
  let wavelengths = array<f32, 7>(650.0, 610.0, 570.0, 530.0, 470.0, 440.0, 400.0);
  let spectralWeights = array<f32, 7>(0.10, 0.13, 0.16, 0.18, 0.16, 0.15, 0.12);

  for (var i: i32 = 0; i < 7; i = i + 1) {
    let wl = wavelengths[i];
    let nDisp = nGlass + 0.02 * (1.0 - wl / 550.0);
    let etaDisp = nAir / nDisp;
    let refractDir = refract(vec3<f32>(0.0, 0.0, -1.0), surfaceNormal, etaDisp);
    let offset = refractDir.xy * refractBase * 0.06 * glassThickness;
    let sampleUV = clamp(deformUV + offset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let samp = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    spectralColor = spectralColor + samp * spectralWeights[i];
  }

  let pixelPos = vec3<f32>(uv.x * aspect, uv.y, 0.0);
  let lightPos = vec3<f32>(mousePos.x * aspect, mousePos.y, 0.25 + lightDistance * 1.2);
  let lightDir = normalize(lightPos - pixelPos);
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfDir = normalize(lightDir + viewDir);
  let specular = pow(max(dot(surfaceNormal, halfDir), 0.0), mix(12.0, 96.0, specularShine));
  let fresnel = pow(1.0 - max(dot(surfaceNormal, viewDir), 0.0), 3.0);

  let caustic = pow(max(dot(surfaceNormal, lightDir), 0.0), 4.0) * glassThickness * (0.3 + bass * 0.3);
  let sss = vec3<f32>(0.15, 0.35, 0.65) * glassThickness * lumaT * 0.25;

  let lumaBase = luminance(spectralColor);
  let tint = mix(
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(lumaBase, lumaBase * (0.82 + mids * 0.08), 1.0 - lumaBase * 0.3 + treble * 0.1),
    0.3 + specularShine * 0.5
  );
  let shimmer = vec3<f32>(0.2, 0.5 + treble * 0.1, 0.8) * specular * (0.5 + bass * 0.5);
  var finalColor = spectralColor * tint + shimmer + fresnel * 0.18 + caustic + sss;
  finalColor = aces_tonemap(finalColor);

  let alpha = clamp(glassThickness * fresnel * depth * 0.8 + specular * 0.2 + bass * 0.05, 0.08, 1.0);
  let depthOut = clamp(depth + fresnel * 0.05, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
}
