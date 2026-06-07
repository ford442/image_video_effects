// ═══════════════════════════════════════════════════════════════════
//  CRT Clear Zone v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: High
//  Chunks From: crt-clear-zone, electron-beam, shadow-mask
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
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn barrel_distort(uv: vec2<f32>, amt: f32) -> vec2<f32> {
  let centered = uv - 0.5;
  let r2 = dot(centered, centered);
  let r4 = r2 * r2;
  let f = 1.0 + r2 * amt * 0.5 + r4 * amt * amt * 0.15;
  return centered * f + 0.5;
}

fn gaussian_spread(uv: vec2<f32>, res: vec2<f32>, spread: f32) -> vec3<f32> {
  let e = spread / res;
  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let c1 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(e.x, 0.0), 0.0).rgb;
  let c2 = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(e.x, 0.0), 0.0).rgb;
  let c3 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, e.y), 0.0).rgb;
  let c4 = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, e.y), 0.0).rgb;
  return c0 * 0.4 + (c1 + c2 + c3 + c4) * 0.15;
}

fn shadow_mask(uv: vec2<f32>, res: vec2<f32>) -> vec3<f32> {
  let maskUV = uv * res * 0.5;
  let slotX = fract(maskUV.x * 0.5);
  let slotY = fract(maskUV.y);
  let r = smoothstep(0.33, 0.0, abs(slotX - 0.17)) * smoothstep(0.5, 0.0, abs(slotY - 0.25));
  let g = smoothstep(0.33, 0.0, abs(slotX - 0.5)) * smoothstep(0.5, 0.0, abs(slotY - 0.75));
  let b = smoothstep(0.33, 0.0, abs(slotX - 0.83)) * smoothstep(0.5, 0.0, abs(slotY - 0.25));
  return vec3<f32>(r, g, b) * 1.6;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let distortion = mix(0.05, 1.8, clamp(u.zoom_params.x, 0.0, 1.0)) * (1.0 + bass * 0.15);
  let aberration = mix(0.001, 0.022, clamp(u.zoom_params.y, 0.0, 1.0));
  let clearRadius = mix(0.08, 0.45, clamp(u.zoom_params.z, 0.0, 1.0));
  let scanlineInt = mix(0.08, 0.75, clamp(u.zoom_params.w, 0.0, 1.0)) * (1.0 + bass * 0.25 + mids * 0.12);

  let crtUV = barrel_distort(uv, distortion);
  let in_bounds = crtUV.x >= 0.0 && crtUV.x <= 1.0 && crtUV.y >= 0.0 && crtUV.y <= 1.0;
  let clampedCrt = clamp(crtUV, vec2<f32>(0.0), vec2<f32>(1.0));

  let spread = 0.8 + depth * 1.5;
  let blurred = gaussian_spread(clampedCrt, resolution, spread);

  let rOff = vec2<f32>(aberration * (1.0 + distortion * 0.3), 0.0);
  let bOff = vec2<f32>(-aberration * (1.0 + distortion * 0.2), 0.0);
  let crtR = blurred.r * 0.65 + textureSampleLevel(readTexture, u_sampler, clamp(clampedCrt + rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r * 0.35;
  let crtG = blurred.g;
  let crtB = blurred.b * 0.65 + textureSampleLevel(readTexture, u_sampler, clamp(clampedCrt + bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b * 0.35;
  var crtColor = vec3<f32>(crtR, crtG, crtB);

  let mask = shadow_mask(clampedCrt, resolution);
  crtColor = crtColor * mask;

  let moire = sin(clampedCrt.x * resolution.x * 0.35) * sin(clampedCrt.y * resolution.y * 0.35) * 0.04 + 0.96;
  crtColor = crtColor * moire;

  let scanline = sin(clampedCrt.y * resolution.y * 0.5 + time * 10.0 + bass * 5.0) * 0.5 + 0.5;
  crtColor = crtColor * (1.0 - scanline * scanlineInt);

  let corner = clampedCrt.x * clampedCrt.y * (1.0 - clampedCrt.x) * (1.0 - clampedCrt.y);
  crtColor = crtColor * pow(max(corner * 16.0, 0.001), 0.18 + distortion * 0.08);
  crtColor = select(vec3<f32>(0.0), crtColor, in_bounds);

  let prevUV = clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
  let prev = textureSampleLevel(dataTextureC, u_sampler, prevUV, 0.0);
  let phosphorDecay = prev.rgb * 0.78;
  crtColor = max(crtColor, phosphorDecay * vec3<f32>(0.9, 0.7, 0.5));

  let cleanColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let dist = distance(uv, mouse);
  let clearMask = smoothstep(clearRadius, max(clearRadius - 0.06, 0.001), dist);
  let edge = smoothstep(clearRadius + 0.025, clearRadius, dist) - smoothstep(clearRadius, max(clearRadius - 0.025, 0.001), dist);
  let glowColor = vec3<f32>(0.25, 0.85, 1.0) * edge * 2.5;

  var finalColor = mix(crtColor, cleanColor, clearMask) + glowColor;
  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(clearMask * 0.95 + (1.0 - clearMask) * (luma * 0.45 + f32(in_bounds) * 0.2) + edge * 0.35 + treble * 0.04, 0.0, 1.0);

  let finalPixel = vec4<f32>(aces_tonemap(finalColor), alpha);
  let outDepth = depth + (1.0 - clearMask) * 0.05;

  textureStore(writeTexture, coords, finalPixel);
  textureStore(dataTextureA, global_id.xy, finalPixel);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
