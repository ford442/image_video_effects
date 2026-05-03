// ═══ PAGE CURL INTERACTIVE ═══
// Category: image
// Features: mouse-driven, audio-reactive, temporal, depth-aware
// Complexity: Medium
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

fn sampleRGBSplit(uv: vec2<f32>, shift: f32) -> vec4<f32> {
  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  return vec4<f32>(r, g, b, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthMul = 1.0 - depth * p4 * 0.5;

  let audioPulse = 1.0 + bass * 0.5 * exp(-fract(time * 2.0) * 4.0);
  let audioShift = mids * 0.03;

  // Click shockwaves from ripples
  var shock = 0.0;
  let rippleCount = min(u32(u.config.y), 10u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let d = length(uv - r.xy);
    let age = time - r.z;
    let w = exp(-age * 3.0) * sin(d * 40.0 - age * 15.0);
    shock = shock + w * 0.02;
  }

  let rollX = clamp(mouse.x + shock + sin(time * 0.4 + bass * 2.0) * 0.015, 0.0, 1.0);
  let radius = max(0.03, (p1 * 0.2 + mouse.y * 0.1) * audioPulse * depthMul);
  let shadowStrength = p2;

  let dx = uv.x - rollX;
  var col = vec4<f32>(0.05, 0.05, 0.05, 1.0);

  if (dx < 0.0) {
    let shadow = smoothstep(radius, 0.0, -dx) * 0.4 * shadowStrength * (1.0 + depth * 0.5);
    let distortedUV = uv + vec2<f32>(shock, 0.0);
    col = textureSampleLevel(readTexture, u_sampler, clamp(distortedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    col = col * (1.0 - shadow);
  } else if (dx < radius) {
    let theta = asin(clamp(dx / radius, -1.0, 1.0));
    let arcLen = radius * theta;
    let srcX = rollX + arcLen;
    if (srcX <= 1.0) {
      let srcUV = vec2<f32>(srcX, uv.y);
      col = sampleRGBSplit(srcUV, audioShift) * 0.6;
      let normalZ = cos(theta);
      let highlight = pow(normalZ, 4.0) * (0.3 + treble * 0.3);
      col += vec4<f32>(highlight);
    } else {
      col = vec4<f32>(0.1, 0.1, 0.1, 1.0);
    }
  }

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let feedback = p3 * 0.4;
  let trailAge = prev.a * 0.96 + select(0.0, 0.5, dx > 0.0 && dx < radius);
  col = mix(col, prev, feedback * 0.25);
  col.a = mix(1.0, trailAge, feedback);

  let flash = select(0.0, 0.1, mouseDown > 0.5) * (0.5 + bass * 0.5);
  col += vec4<f32>(flash);

  textureStore(writeTexture, vec2<i32>(global_id.xy), col);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
