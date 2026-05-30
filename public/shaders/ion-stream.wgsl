// ═══════════════════════════════════════════════════════════════════
//  Ion Stream
//  Category: distortion
//  Features: animated, curl-turbulence, magnetic-bending, audio-reactive, upgraded-rgba
//  Complexity: High
//  Chunks From: ion-stream, curl2D, fbm, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = fbm(p + vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n2 = fbm(p - vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n3 = fbm(p + vec2<f32>(0.0, eps) + t * 0.1, 3);
  let n4 = fbm(p - vec2<f32>(0.0, eps) + t * 0.1, 3);
  let dy = (n1 - n2) / (2.0 * eps);
  let dx = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dx, -dy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let speed = u.zoom_params.x;
    let curlStrength = u.zoom_params.y;
    let streamDensity = u.zoom_params.z;
    let colorIntensity = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFade = mix(1.0, 0.5, depth);

    let flow = curl2D(uv * 2.0 + time * 0.05, time * speed) * curlStrength * bass_env(bass, mids);
    let advectedUV = clamp(uv + flow * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, advectedUV, 0.0);

    // Magnetic bending from mouse
    let aspect = resolution.x / resolution.y;
    let diff = uv - mouse;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    let magnetic = 1.0 / (1.0 + dist * 5.0) * (1.0 + bass * 0.5);
    let bendDir = vec2<f32>(-diff.y, diff.x) * magnetic * 0.01;
    let bentUV = clamp(advectedUV + bendDir, vec2<f32>(0.0), vec2<f32>(1.0));
    let bentColor = textureSampleLevel(readTexture, u_sampler, bentUV, 0.0);

    // Ion glow
    let streamSeed = floor(uv.x * 50.0 * streamDensity) / (50.0 * streamDensity);
    let streamPhase = streamSeed * 6.28 + time * 2.0;
    let streamY = sin(streamPhase) * 0.1 + 0.5;
    let streamDist = abs(uv.y - streamY);
    let ionGlow = exp(-streamDist * 20.0 * (1.0 + treble * 2.0)) * colorIntensity * 0.5;

    let ionColor = vec3<f32>(0.3, 0.7, 1.0) * ionGlow * bass_env(bass, mids);
    let blended = mix(bentColor, color, 0.5);
    let finalRGB = blended.rgb + ionColor * depthFade;
    let alpha = clamp(blended.a + ionGlow + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
