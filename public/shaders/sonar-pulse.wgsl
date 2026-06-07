// ═══════════════════════════════════════════════════════════════════
//  Sonar Pulse
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, chromatic-echo, depth-attenuation, interference, upgraded-rgba
//  Complexity: High
//  Chunks From: sonar-pulse, bass_env, depth-aware-fog
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

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001, 0.001));
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let waveSpeed = mix(1.0, 10.0, u.zoom_params.x) * bass_env(bass, mids);
  let waveFreq = mix(10.0, 100.0, u.zoom_params.y) + mids * 10.0;
  let intensity = clamp(u.zoom_params.z + treble * 0.1, 0.0, 1.0);
  let waveWidth = max(mix(0.1, 0.5, u.zoom_params.w), 0.001);

  let aspect = resolution.x / max(resolution.y, 0.001);
  let mousePos = u.zoom_config.yz;

  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uv_corrected, mouse_corrected);

  // Multi-ring sonar with chromatic separation
  let phase = dist * waveFreq - time * waveSpeed;
  let wave = sin(phase);
  let pulse = smoothstep(1.0 - waveWidth, 1.0, wave);
  let falloff = 1.0 / (1.0 + dist * 2.0);

  // Interference beats from secondary wave
  let phase2 = dist * waveFreq * 1.03 - time * waveSpeed * 0.97;
  let beat = sin(phase) * sin(phase2);
  let beatMask = smoothstep(0.5, 1.0, abs(beat)) * 0.3;

  let audioBoost = bass_env(bass, mids);
  let pulseStrength = pulse * intensity * falloff * audioBoost;

  let safeDist = max(dist, 0.001);
  let offsetDir = (uv_corrected - mouse_corrected) / safeDist;
  let distortAmt = 0.02 * pulse * intensity;
  let distortedUV = clamp(uv - offsetDir * distortAmt, vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic echo: R/G/B sample at different distances
  let chromaOffset = pulseStrength * 0.015;
  let rUV = clamp(distortedUV + offsetDir * chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = distortedUV;
  let bUV = clamp(distortedUV - offsetDir * chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let rCol = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let gCol = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let bCol = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  let pulseColor = vec3<f32>(0.0, 1.0, 0.5);
  var finalColor = vec3<f32>(rCol, gCol, bCol) + pulseColor * pulseStrength;
  finalColor = finalColor + vec3<f32>(0.5, 0.2, 0.8) * beatMask * intensity;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAtten = mix(1.0, 0.5, depth);
  finalColor = finalColor * depthAtten;

  let luminance = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luminance + pulseStrength * 0.3 + beatMask * 0.2, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
