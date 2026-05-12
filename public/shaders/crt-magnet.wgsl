// ═══════════════════════════════════════════════════════════════════
//  CRT Magnet (Batch D Upgrade)
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgrades: color bloom with Gaussian blur, degaussing radial field,
//            luminance-key alpha, bass-driven magnet pulse
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * 0.1031;
  let d = fract(pp.x * pp.y * 23.4517 + pp.y * 37.2314);
  let s = vec2<f32>(d + 0.113, d + 0.257);
  return fract(s * s * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    v = v + a * noise2(pp);
    pp = pp * 2.03;
    a = a * 0.5;
  }
  return v;
}

fn curl2(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.02;
  let n1 = fbm(p + vec2<f32>(e, 0.0) + t);
  let n2 = fbm(p - vec2<f32>(e, 0.0) + t);
  let n3 = fbm(p + vec2<f32>(0.0, e) + t);
  let n4 = fbm(p - vec2<f32>(0.0, e) + t);
  let dx = (n1 - n2) / (2.0 * e);
  let dy = (n3 - n4) / (2.0 * e);
  return vec2<f32>(dy, -dx);
}

fn barrel(uv: vec2<f32>, k: f32) -> vec2<f32> {
  let d = uv - 0.5;
  let r2 = dot(d, d);
  let f = 1.0 + k * r2 + k * k * r2 * r2;
  return 0.5 + d * f;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let time = u.config.x;
  let uvRaw = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  let magnetStrength = u.zoom_params.x;
  let bloomIntensity = u.zoom_params.y;
  let colorShift = u.zoom_params.z;
  let distortionRadius = u.zoom_params.w;

  // SDF barrel distortion for CRT curvature
  let uv = barrel(uvRaw, 0.15);

  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // FBM-perturbed magnetic falloff with temporal drift
  let fbmWarp = fbm(uv * 8.0 + time * 0.3) * 0.3 + 0.7;
  let radius = distortionRadius * 0.4 + 0.05;
  let falloff = exp(-dist * dist / (radius * radius * fbmWarp));

  // Depth-aware field attenuation
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvRaw, 0.0).r;
  let depthAtten = mix(0.7, 1.0, depth);

  // Audio-reactive pulse: bass drives magnet strength
  let bass = plasmaBuffer[0].x;
  let audioPulse = bass * 2.0;

  // Degaussing radial magnetic field
  let field = magnetStrength * falloff * depthAtten * (1.0 + audioPulse);

  // Curl-noise magnetic field lines
  let curl = curl2(uv * 6.0 + mousePos * 3.0, time * 0.2);

  // Divergence-free displacement: radial + curl swirl
  let radial = dVec * field * 4.0;
  let swirl = curl * field * 0.4;
  let displacement = radial + swirl;

  // Distance-scaled chromatic aberration with color shift
  let abrScale = colorShift * 0.05 * (1.0 + dist * 3.0);
  let uv_r = uv - displacement * (1.0 - abrScale * 2.0);
  let uv_g = uv - displacement;
  let uv_b = uv - displacement * (1.0 + abrScale * 4.0);

  var r = textureSampleLevel(readTexture, u_sampler, clamp(uv_r, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  var g = textureSampleLevel(readTexture, u_sampler, clamp(uv_g, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, clamp(uv_b, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  var col = vec3<f32>(r, g, b);

  // Color bloom: extract high-luma pixels, blur with cross-sample kernel, add back
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let bloomThreshold = smoothstep(0.6, 1.0, luma);
  let bloomSize = 0.008 * bloomIntensity;
  var bloom = vec3(0.0);
  bloom += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2(bloomSize, 0.0), vec2(0.0), vec2(1.0)), 0.0).rgb * 0.25;
  bloom += textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2(bloomSize, 0.0), vec2(0.0), vec2(1.0)), 0.0).rgb * 0.25;
  bloom += textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2(0.0, bloomSize), vec2(0.0), vec2(1.0)), 0.0).rgb * 0.25;
  bloom += textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2(0.0, bloomSize), vec2(0.0), vec2(1.0)), 0.0).rgb * 0.25;
  col = col + bloom * bloomThreshold * bloomIntensity * 2.0;

  // SDF vignette with smooth radial falloff
  let vigUV = uvRaw - 0.5;
  let vigR2 = dot(vigUV, vigUV);
  let vignette = 1.0 - smoothstep(0.25, 0.55, vigR2) * 0.6;

  // Luminance-key alpha
  let alpha = dot(col, vec3(0.299, 0.587, 0.114));
  let finalColor = vec4<f32>(col * vignette, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
