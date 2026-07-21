// Wave Tank — Pass 3: normals, refraction, phase hue, caustics

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

fn computeNormal(uv: vec2<f32>, texelSize: vec2<f32>) -> vec3<f32> {
  let left = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-1.0, 0.0) * texelSize, 0.0).r;
  let right = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(1.0, 0.0) * texelSize, 0.0).r;
  let up = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -1.0) * texelSize, 0.0).r;
  let down = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, 1.0) * texelSize, 0.0).r;
  let dx = (right - left) * 2.0;
  let dy = (down - up) * 2.0;
  return normalize(vec3<f32>(-dx, -dy, 0.1));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  var h = hsv.x * 6.0;
  let s = hsv.y;
  let v = hsv.z;
  let c = v * s;
  let x = c * (1.0 - abs(h % 2.0 - 1.0));
  let m = v - c;
  var rgb: vec3<f32>;
  if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));

  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let height = state.r;
  let velocity = state.g;

  let normal = computeNormal(uv, texelSize);
  let refractOffset = normal.xy * 0.03;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv + refractOffset, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let phase = atan2(velocity, height);
  let hue = phase / 6.283185 + 0.5;
  let amplitude = sqrt(height * height + velocity * velocity);
  let waveColor = hsv2rgb(vec3<f32>(hue, 0.7, amplitude * 2.0 + 0.2));

  let lightDir = normalize(vec3<f32>(0.5, 0.5, 1.0));
  let diffuse = max(dot(normal, lightDir), 0.0);
  let specular = pow(max(dot(reflect(-lightDir, normal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 32.0);

  var finalColor = sourceColor.rgb;
  finalColor = finalColor + waveColor * amplitude * 0.5;
  finalColor = finalColor * (0.5 + diffuse * 0.5);
  finalColor = finalColor + vec3<f32>(specular * 0.3);

  let laplacian = (textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r
    + textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(texelSize.x, 0.0), 0.0).r
    + textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r
    + textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(0.0, texelSize.y), 0.0).r
    - 4.0 * height);
  let caustic = pow(abs(laplacian) * 5.0, 2.0);
  finalColor = finalColor + vec3<f32>(caustic * 0.2);

  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(coord), state);
}
