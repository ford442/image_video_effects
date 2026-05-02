// ═══════════════════════════════════════════════════════════════════
//  CRT Magnet (Algorithmist Upgrade)
//  Category: image
//  Features: mouse-driven, depth-aware, temporal, audio-reactive
//  Complexity: High
//  Chunks From: crt-magnet.wgsl
//  Created: 2026-05-02
//  By: Algorithmist
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
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

fn worley2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  var md = 1.0;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let n = i + vec2<f32>(f32(x), f32(y));
      let h = hash22(n + 47.31);
      let d = length(f - (h + vec2<f32>(f32(x), f32(y))));
      md = min(md, d);
    }
  }
  return md;
}

fn barrel(uv: vec2<f32>, k: f32) -> vec2<f32> {
  let d = uv - 0.5;
  let r2 = dot(d, d);
  let f = 1.0 + k * r2 + k * k * r2 * r2;
  return 0.5 + d * f;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let time = u.config.x;
  let uvRaw = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  let magStrength = (u.zoom_params.x - 0.5) * 4.0;
  let radius = u.zoom_params.y * 0.4 + 0.05;
  let aberration = u.zoom_params.z * 0.05;
  let scanlineInt = u.zoom_params.w;

  // SDF barrel distortion for CRT curvature
  let uv = barrel(uvRaw, 0.15);

  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // FBM-perturbed magnetic falloff with temporal drift
  let fbmWarp = fbm(uv * 8.0 + time * 0.3) * 0.3 + 0.7;
  let falloff = exp(-dist * dist / (radius * radius * fbmWarp));

  // Depth-aware field attenuation
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvRaw, 0.0).r;
  let depthAtten = mix(0.7, 1.0, depth);

  // Audio-reactive pulse from plasmaBuffer
  let audioPulse = plasmaBuffer[0].x;

  // Curl-noise magnetic field lines
  let curl = curl2(uv * 6.0 + mousePos * 3.0, time * 0.2);
  let field = magStrength * falloff * depthAtten * (1.0 + audioPulse * 0.3);

  // Divergence-free displacement: radial + curl swirl
  let radial = dVec * field;
  let swirl = curl * field * 0.4;
  let displacement = radial + swirl;

  // Distance-scaled chromatic aberration
  let abrScale = aberration * (1.0 + dist * 3.0);
  let uv_r = uv - displacement * (1.0 - abrScale * 2.0);
  let uv_g = uv - displacement;
  let uv_b = uv - displacement * (1.0 + abrScale * 4.0);

  var r = textureSampleLevel(readTexture, u_sampler, clamp(uv_r, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  var g = textureSampleLevel(readTexture, u_sampler, clamp(uv_g, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, clamp(uv_b, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // Scanlines with Worley phosphor grain and temporal flicker
  let scanFreq = resolution.y * 0.5;
  let scanlineVal = sin(uv_g.y * scanFreq) * 0.5 + 0.5;
  let grain = worley2(uv * resolution * 0.08) * 0.15 + 0.85;
  let flicker = 1.0 + sin(time * 60.0) * 0.02;
  let scanline = mix(1.0, scanlineVal * grain * flicker, scanlineInt);

  // Phosphor glow from field intensity
  let glow = vec3<f32>(0.12, 0.06, 0.18) * abs(field) * 0.25;
  var col = vec3<f32>(r, g, b) + glow;

  // SDF vignette with smooth radial falloff
  let vigUV = uvRaw - 0.5;
  let vigR2 = dot(vigUV, vigUV);
  let vignette = 1.0 - smoothstep(0.25, 0.55, vigR2) * 0.6;

  let finalColor = vec4<f32>(col * scanline * vignette, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
