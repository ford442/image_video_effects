// ═══════════════════════════════════════════════════════════════════
//  Crumpled Paper
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-06
//  Ideas: fibre grain along crease tangent; ironing memory via exact C
//  A packing: display RGB + height in alpha
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm5(p: vec2<f32>) -> f32 {
  var sum = 0.0;
  var amp = 1.0;
  var freq = 1.0;
  var maxAmp = 0.0;
  for (var i: i32 = 0; i < 5; i = i + 1) {
    sum = sum + amp * valueNoise2D(p * freq);
    maxAmp = maxAmp + amp;
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum / maxAmp;
}

fn paperHeight(uv: vec2<f32>, scale: f32, depthAmt: f32) -> vec2<f32> {
  let noiseVal = fbm5(uv * scale + vec2<f32>(12.3, 45.6));
  let ridge = pow(1.0 - abs(noiseVal - 0.5) * 2.0, 2.0);
  let h = mix(noiseVal, ridge, 0.6) * depthAmt;
  return vec2<f32>(h, ridge);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  var uv = vec2<f32>(gid.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let treble = plasmaBuffer[0].z;

  let scale = mix(2.0, 10.0, u.zoom_params.x);
  let depthAmt = u.zoom_params.y;
  let smoothRadius = u.zoom_params.z * 0.5;
  let lightStrength = u.zoom_params.w;
  let sr = max(0.001, smoothRadius);

  let hr = paperHeight(uv, scale, depthAmt);
  var height = hr.x;
  let ridge = hr.y;

  let dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let smoothFactor = 1.0 - smoothstep(0.0, sr, dist);
  height = height * (1.0 - smoothFactor);

  let prev = textureLoad(dataTextureC, coord, 0);
  let ironed = mix(height, prev.a * 0.88, 0.45 * smoothFactor + 0.12);
  height = ironed;

  let eps = 0.005;
  let hR = paperHeight(uv + vec2<f32>(eps, 0.0), scale, depthAmt).x;
  let distR = length(((uv + vec2<f32>(eps, 0.0)) - mouse) * vec2<f32>(aspect, 1.0));
  let finalHR = hR * (1.0 - (1.0 - smoothstep(0.0, sr, distR)));
  let hU = paperHeight(uv + vec2<f32>(0.0, eps), scale, depthAmt).x;
  let distU = length(((uv + vec2<f32>(0.0, eps)) - mouse) * vec2<f32>(aspect, 1.0));
  let finalHU = hU * (1.0 - (1.0 - smoothstep(0.0, sr, distU)));

  let dX = (finalHR - height) / eps;
  let dY = (finalHU - height) / eps;
  let normal = normalize(vec3<f32>(-dX, -dY, 1.0));

  let lightDir = normalize(vec3<f32>(0.5, -0.5, 1.0));
  let diffuse = max(dot(normal, lightDir), 0.0);
  let ao = mix(0.55, 1.0, clamp(height * 1.4 + 0.3, 0.0, 1.0));
  let ambient = (0.5 + 0.5 * height) * ao;
  let lighting = ambient * 0.5 + diffuse * 0.8;

  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfDir = normalize(lightDir + viewDir);
  let creaseSteep = clamp(length(normal.xy) * 2.2, 0.0, 1.0);
  let specular = pow(max(dot(normal, halfDir), 0.0), 48.0) * creaseSteep * 0.6;
  let creaseWear = pow(ridge, 3.0) * smoothstep(0.25, 0.6, depthAmt);

  let tangent = normalize(vec2<f32>(-normal.y, normal.x) + vec2<f32>(1e-4, 0.0));
  let fibre = (hash21(uv * 420.0 + tangent * 90.0) - 0.5) * creaseSteep * (0.10 + treble * 0.08);

  let distortStr = 0.02 * depthAmt;
  let finalUV = clamp(uv + normal.xy * distortStr, vec2<f32>(0.0), vec2<f32>(1.0));
  let texColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

  var finalColor = texColor * mix(1.0, lighting, lightStrength);
  finalColor = finalColor + vec3<f32>(specular) * lightStrength;
  finalColor = mix(finalColor, vec3<f32>(0.96, 0.96, 0.93), creaseWear * 0.5 * lightStrength);
  finalColor += vec3<f32>(fibre) * lightStrength;

  let display = acesToneMap(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.6)));
  let alpha = clamp(0.55 + creaseSteep * 0.35 + (1.0 - smoothFactor) * 0.1, 0.0, 1.0);
  let packed = vec4<f32>(display, clamp(height, 0.0, 1.0));

  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(dataTextureA, coord, packed);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depthVal + height * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
