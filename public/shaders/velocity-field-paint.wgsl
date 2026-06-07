// ═══════════════════════════════════════════════════════════════════
//  Velocity Field — Vorticity Confinement
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

fn hash21(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * 1.618033988749895)) * 2.0 - 1.0;
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i).x;
  let b = hash21(i + vec2<f32>(1.0, 0.0)).x;
  let c = hash21(i + vec2<f32>(0.0, 1.0)).x;
  let d = hash21(i + vec2<f32>(1.0, 1.0)).x;
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5; var s = 0.0; var q = p;
  for (var i = 0; i < 5; i = i + 1) {
    s = s + a * valueNoise(q);
    q = q * 2.02; a = a * 0.5;
  }
  return s;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let noiseScale = 0.5 + u.zoom_params.x * 4.0;
  let brushSize = 0.04 + u.zoom_params.y * 0.18;
  let force = clamp(u.zoom_params.z * 0.6 * (1.0 + bass * 0.5), 0.0, 5.0);
  let colorIntensity = mix(0.0, 0.6, u.zoom_params.w) * (1.0 + treble * 0.3);

  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  let brush = smoothstep(brushSize, 0.0, dist);
  let dir = select(normalize(dVec + vec2<f32>(0.0001)), vec2<f32>(0.0), dist < 0.0001);

  // Mouse-driven circular velocity + procedural flow field
  let mouseVel = vec2<f32>(-dir.y, dir.x) * force * brush;
  let flowFreq = 2.0 + noiseScale * 3.0 + mids * 2.0;
  let flowUV = uv * flowFreq + vec2<f32>(time * 0.1, time * 0.15);
  let flowVel = vec2<f32>(
    fbm(flowUV + vec2<f32>(0.0, 1.7)) - 0.5,
    fbm(flowUV + vec2<f32>(5.2, 3.1)) - 0.5
  ) * 0.08 * (1.0 + treble * 0.5);
  let vel = mouseVel + flowVel;

  // Advect image along velocity
  let offsetUV = clamp(uv - vel * 0.05, vec2<f32>(0.0), vec2<f32>(1.0));
  let lod = clamp(length(vel) * 8.0, 0.0, 3.0);
  let sampled = textureSampleLevel(readTexture, u_sampler, offsetUV, lod);

  // Pseudo-vorticity from flow field analytical curl
  let eps = 0.01;
  let dfdx = (fbm(flowUV + vec2<f32>(eps, 0.0)) - fbm(flowUV - vec2<f32>(eps, 0.0))) / max(eps * 2.0, 1e-4);
  let dfdy = (fbm(flowUV + vec2<f32>(0.0, eps)) - fbm(flowUV - vec2<f32>(0.0, eps))) / max(eps * 2.0, 1e-4);
  let omega = dfdx - dfdy;
  let enstrophy = clamp(omega * omega * 6.0, 0.0, 1.0);

  // Positive vorticity (CCW) → cyan, negative (CW) → magenta
  let vortCol = select(
    vec3<f32>(1.0, 0.1, 0.8),
    vec3<f32>(0.1, 0.8, 1.0),
    omega > 0.0
  );
  let color = mix(sampled.rgb, vortCol, enstrophy * colorIntensity);

  let effectStrength = clamp(length(vel) * 10.0 + brush * 0.5, 0.0, 1.0);
  let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(mix(0.5, luminance * 0.7 + 0.4, effectStrength) + enstrophy * 0.2, 0.0, 1.0);
  let finalColor = vec4<f32>(color, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
