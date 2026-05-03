// ═══════════════════════════════════════════════════════════════════
//  Echo Ripple (Upgraded)
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, depth-aware
//  Upgrades: gravity wells, bass pulse, click shockwaves, FFT tint,
//            multi-source echoes, depth parallax, semantic alpha
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let aspect = res.x / res.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let beat = bass * exp(-3.0 * fract(time * 3.0));

  // Params
  let frequency = u.zoom_params.x * 30.0 + 2.0;
  let speed = u.zoom_params.y * 8.0 + 0.5;
  let decay = u.zoom_params.z * 0.97 + 0.02;
  let strength = u.zoom_params.w * 0.15 + 0.01;

  // Aspect-correct mouse distance
  let d = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(d);
  let dist2 = dot(d, d) + 0.001;

  // Gravity well (branchless UV pull toward mouse)
  let grav = d * strength * 0.02 / dist2;

  // Ripple wave: bass-driven amplitude + mids-driven phase precession
  let wave = sin(dist * frequency - time * speed + mids * 2.0) * (1.0 + beat * 3.0);
  let atten = smoothstep(0.6, 0.0, dist);

  // Multi-source ripple echoes from click history
  let rippleCount = u32(u.config.y);
  let hasR1 = f32(rippleCount > 1u);
  let hasR2 = f32(rippleCount > 2u);
  let r1 = u.ripples[1];
  let r2 = u.ripples[2];
  let d1 = (uv - r1.xy) * vec2<f32>(aspect, 1.0);
  let d2 = (uv - r2.xy) * vec2<f32>(aspect, 1.0);
  let distR1 = length(d1);
  let distR2 = length(d2);
  let t1 = time - r1.z;
  let t2 = time - r2.z;
  let wave1 = sin(distR1 * frequency - t1 * speed + mids) * smoothstep(0.7, 0.0, distR1) * step(0.0, t1) * hasR1;
  let wave2 = sin(distR2 * frequency - t2 * speed - mids) * smoothstep(0.7, 0.0, distR2) * step(0.0, t2) * hasR2;
  let totalWave = wave + wave1 + wave2;

  // Click shockwave burst
  let clickWave = sin(dist * 50.0 - time * 20.0) * mouseDown * smoothstep(0.25, 0.0, dist);

  // Branchless direction
  let rawDir = uv - mouse;
  let rawDist = length(rawDir) + 0.0001;
  let dir = rawDir / rawDist;

  // Depth-aware parallax: stronger distortion on foreground
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthMod = mix(0.6, 1.2, depth);

  // Total UV distortion
  let distort = (totalWave + clickWave) * strength * atten * depthMod;
  let sampleUV = uv - dir * distort + grav;

  // Sample video input
  var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  // FFT multi-band color tinting at ripple edges
  let fftTint = vec3<f32>(bass * 0.5, mids * 0.3, treble * 0.6) * totalWave * atten * strength * 10.0;
  color = color + fftTint;

  // Treble sparkle on ripple crests
  let hash = fract(sin(dot(uv * 1000.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let sparkle = treble * step(0.92, hash) * atten * 0.5;
  color = color + vec3<f32>(sparkle);

  // Temporal feedback loop (exponential smoothing via history)
  let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let mixed = mix(color, history.rgb, decay * (1.0 - atten * 0.25));

  // Alpha encodes trail age modulated by interaction intensity and beat pulse
  let alpha = mix(decay * history.a, 1.0, atten * (0.4 + beat));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(mixed, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(mixed, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
