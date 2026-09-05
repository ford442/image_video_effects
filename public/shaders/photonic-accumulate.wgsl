// Photonic Caustics — temporal accumulation + iridescent present (graph node 3)

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let dispersion = mix(0.0, 0.1, u.zoom_params.z);
  let treble = plasmaBuffer[0].z;

  let thisTrace = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let lightPos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let lightHeight = 1.0;

  // Recompute surface normal from depth for refraction
  let hL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).r;
  let hR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
  let hU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).r;
  let hD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;
  let surfaceNormal = normalize(vec3<f32>((hL - hR) * 2.0, (hU - hD) * 2.0, 0.3));

  var causticAccum = thisTrace.rgb;
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 3.0) {
        let toRipple = uv - ripple.xy;
        let dist = length(toRipple);
        let rippleStrength = (1.0 - rippleAge / 3.0) * 0.5;
        let wave = sin(dist * 30.0 - rippleAge * 5.0) * 0.5 + 0.5;
        let causticRing = wave * rippleStrength / (1.0 + dist * 10.0);
        causticAccum = causticAccum + vec3<f32>(causticRing * 0.5, causticRing * 0.7, causticRing * 1.0);
      }
    }
  }

  let intensity = mix(0.5, 3.0, u.zoom_params.w);
  let displayCaustic = causticAccum * (0.85 + intensity * 0.25);

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let refractDisplace = surfaceNormal.xy * 0.025 * (1.0 + treble * 0.25);
  let chromaOffset = dispersion * 0.015;
  let colorR = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace + vec2<f32>(chromaOffset, 0.0), 0.0).r;
  let colorG = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace, 0.0).g;
  let colorB = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace - vec2<f32>(chromaOffset, 0.0), 0.0).b;
  let refractedChromatic = vec3<f32>(colorR, colorG, colorB);

  var finalColor = mix(sourceColor, refractedChromatic, 0.35) + displayCaustic;

  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let reflectDir = reflect(-viewDir, surfaceNormal);
  let lightDir = normalize(vec3<f32>(lightPos - uv, lightHeight));
  let specular = pow(max(dot(reflectDir, lightDir), 0.0), 48.0);
  finalColor = finalColor + vec3<f32>(specular * 0.65);

  let rim = pow(1.0 - abs(dot(surfaceNormal, viewDir)), 3.0);
  finalColor = finalColor + vec3<f32>(0.3, 0.7, 1.0) * rim * dispersion * 2.0;

  let alpha = clamp(0.7 + length(displayCaustic) * 0.3, 0.0, 1.0);
  let result = vec4<f32>(aces(max(finalColor, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, vec2<i32>(coord), result);
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(causticAccum, alpha));
}
