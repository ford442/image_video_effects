// ═══════════════════════════════════════════════════════════════════
//  alucinate - Reaction-Diffusion Psychedelia
//  Category: image
//  Features: upgraded-rgba, depth-aware, reaction-diffusion, fbm-warping, kaleidoscopic-ifs, conformal-mapping, audio-reactive
//  Complexity: Very High
//  Upgraded by: Visualist Agent
//  Date: 2026-05-03
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
  config: vec4<f32>,      // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for(var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise2D(pos);
    pos = rot * pos * 2.0 + 100.0;
    a = a * 0.5;
  }
  return v;
}

fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, 0.0), 4), fbm(p + vec2<f32>(5.2, 1.3), 4));
  let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15, 4),
                    fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126, 4));
  return p + 4.0 * r;
}

fn kaleidoscopeIFS(p: vec2<f32>, time: f32) -> vec2<f32> {
  var z = p;
  let angle = time * 0.1;
  let rot = mat2x2<f32>(cos(angle), -sin(angle), sin(angle), cos(angle));
  for(var i: i32 = 0; i < 5; i = i + 1) {
    z = abs(z) - vec2<f32>(0.3, 0.2);
    z = rot * z;
    let d = max(dot(z, z), 0.1);
    z = z / d;
  }
  return z;
}

fn conformalMap(z: vec2<f32>, time: f32) -> vec2<f32> {
  let c = vec2<f32>(sin(time * 0.2) * 0.3, cos(time * 0.17) * 0.3);
  let z2 = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y);
  let denom = max(dot(z2 - c, z2 - c), 0.001);
  return (z2 - c) / denom * 0.5;
}

fn grayScott(uv: vec2<f32>, time: f32) -> vec2<f32> {
  let scale = 12.0;
  let p = uv * scale;
  let feed = 0.037 + sin(time * 0.3) * 0.005;
  let kill = 0.06 + cos(time * 0.25) * 0.003;
  let n1 = sin(p.x + time) * cos(p.y);
  let n2 = cos(p.x) * sin(p.y + time * 0.7);
  let a = 0.5 + 0.5 * sin(n1 * n2 * 3.0);
  let b = 0.25 + 0.25 * cos(n1 + n2 + time);
  let reaction = a * b * b;
  let da = (n1 - a) - reaction + feed * (1.0 - a);
  let db = (n2 - b) + reaction - (kill + feed) * b;
  return vec2<f32>(clamp(a + da * 0.1, 0.0, 1.0), clamp(b + db * 0.1, 0.0, 1.0));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(hsv.z - c);
}

fn gammaCorrect(col: vec3<f32>, gamma: f32) -> vec3<f32> {
  return pow(max(col, vec3<f32>(0.0)), vec3<f32>(1.0 / gamma));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x * 0.5;
  let mouse_uv = u.zoom_config.yz;
  let mouse_active = u.zoom_config.w > 0.0;
  let dist_to_mouse = distance(uv, mouse_uv);
  let mouse_effect = smoothstep(0.4, 0.0, dist_to_mouse) * f32(mouse_active);

  let param1 = u.zoom_params.x;
  let param2 = u.zoom_params.y;
  let param3 = u.zoom_params.z;
  let param4 = u.zoom_params.w;

  let audioPulse = plasmaBuffer[0].x * 0.5 + plasmaBuffer[0].y * 0.3;

  let centered = (uv - 0.5) * 2.0;
  let aspect = resolution.x / resolution.y;
  let ca = vec2<f32>(centered.x * aspect, centered.y);

  var warped = domainWarp(ca * (0.5 + param3 * 1.5), time * (0.3 + param2 * 0.7));
  warped = kaleidoscopeIFS(warped, time * (0.1 + param2 * 0.2));
  warped = conformalMap(warped, time);
  warped = warped * (0.5 + mouse_effect * 0.5 + audioPulse * 0.2);

  let rippleCount = u32(u.config.y);
  for(var r: u32 = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let rpos = ripple.xy;
    let rt = time - ripple.z;
    let rdist = distance(uv, rpos);
    let ring = sin(rdist * 40.0 - rt * 6.0) * exp(-rt * 2.0) * exp(-rdist * 3.0);
    warped = warped + vec2<f32>(ring * 0.3, ring * 0.2);
  }

  let gs = grayScott(warped * 0.5 + 0.5, time);
  let patternA = gs.x;
  let patternB = gs.y;

  let sampleUV = clamp(warped * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let mixUV = mix(uv, sampleUV, 0.3 + param1 * 0.7);

  let aberration = 0.02 + param1 * 0.06 + mouse_effect * 0.04;
  let r = textureSampleLevel(readTexture, u_sampler, mixUV + vec2<f32>(patternB * aberration, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, mixUV + vec2<f32>(0.0, patternA * aberration), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, mixUV - vec2<f32>(patternB * aberration * 0.6, patternA * aberration * 0.6), 0.0).b;

  let hue = fract(patternA * 0.7 + patternB * 0.3 + time * 0.05 + param4 * 0.2 + audioPulse * 0.1);
  let sat = 0.6 + mouse_effect * 0.4;
  let val = 0.8 + patternA * 0.2 + audioPulse * 0.15;
  let rainbow = hsv2rgb(vec3<f32>(hue, sat, val));

  var color = mix(vec3<f32>(r, g, b), rainbow, 0.2 + param1 * 0.3);
  color = gammaCorrect(color, 0.85 + param4 * 0.3);

  let gradMag = length(vec2<f32>(patternA, patternB));
  let diffusionRate = 0.5 + 0.5 * sin(time + patternA * 6.28318530718);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  color = mix(color, color * (1.0 + depth * 0.5), 0.35);

  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = mix(0.85, 1.0, luma + mouse_effect * 0.3);
  let finalAlpha = mix(alpha * 0.8, alpha, depth);

  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

  let rgbaData = vec4<f32>(patternA, patternB, gradMag, diffusionRate);
  textureStore(dataTextureA, coord, rgbaData);
}
