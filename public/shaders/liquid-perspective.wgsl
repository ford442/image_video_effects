// ═══════════════════════════════════════════════════════════════════
//  Liquid Perspective
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-07-21
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
struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };

fn minDepth3x3(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
  var result = 1.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let sampleUV = clamp(uv + vec2<f32>(f32(x), f32(y)) * texel, vec2<f32>(0.0), vec2<f32>(1.0));
      result = min(result, textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r);
    }
  }
  return result;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy); let uv = vec2<f32>(gid.xy) / resolution; let texel = 1.0 / resolution; let time = u.config.x;
  let speed = mix(0.15, 1.25, u.zoom_params.x); let density = mix(1.5, 8.0, u.zoom_params.y);
  let intensity = mix(0.002, 0.045, u.zoom_params.z); let colorShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0); let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let nearestDepth = minDepth3x3(uv, texel); let foreground = 1.0 - smoothstep(0.42, 0.62, nearestDepth);
  let edgeMask = smoothstep(0.004, 0.08, abs(depth - nearestDepth));
  let aspect = resolution.x / max(resolution.y, 1.0); let mouse = u.zoom_config.yz;
  let mouseDelta = (uv - mouse) * vec2<f32>(aspect, 1.0); let mouseDist = max(length(mouseDelta), 0.0001);
  let mousePull = exp(-mouseDist * 5.0) * u.zoom_config.w;
  var geometryDisp = vec2<f32>(mouseDelta.x / aspect, mouseDelta.y) / mouseDist * mousePull * intensity * (1.0 + audio.x * 0.5);
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age > 0.0 && age < 3.0) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0); let dist = max(length(delta), 0.0001); let dir = delta / dist;
      let wave = sin(dist * (20.0 + density * 2.0) - age * (3.0 + speed * 3.0)); let envelope = exp(-dist * 7.0) * (1.0 - smoothstep(0.0, 3.0, age));
      geometryDisp += vec2<f32>(dir.x / aspect, dir.y) * wave * envelope * intensity * (1.0 + audio.x * 0.45);
    }
  }
  let parallax = vec2<f32>(sin(uv.y * density + time * speed), cos(uv.x * density - time * speed * 0.8)) * intensity * mix(1.0, 0.25, depth);
  let colorDisp = geometryDisp * foreground + parallax * (1.0 - foreground);
  let warpedUV = clamp(uv + colorDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let warped = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  let split = colorDisp * (0.4 + colorShift * 2.5 + audio.y * 0.5);
  let red = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let blue = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let biolume = mix(vec3<f32>(0.0, 0.8, 0.65), vec3<f32>(0.55, 0.1, 1.0), colorShift) * edgeMask * (0.25 + audio.z * 0.75);
  let warpedRGB = vec3<f32>(red.r, warped.g, blue.b) + biolume;
  let rgb = mix(base.rgb, warpedRGB, clamp(0.25 + foreground * 0.75 + length(colorDisp) * 4.0, 0.0, 1.0));
  let sourceAlpha = max(base.a, max(red.a, blue.a)); let alpha = clamp(sourceAlpha + edgeMask * 0.18 + length(colorDisp) * 3.0, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);
  textureStore(writeTexture, coord, outputColor); textureStore(dataTextureA, coord, outputColor);
  let depthUV = clamp(uv + geometryDisp * foreground, vec2<f32>(0.0), vec2<f32>(1.0));
  let outDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
