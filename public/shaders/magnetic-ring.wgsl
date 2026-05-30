// ═══════════════════════════════════════════════════════════════════
//  Magnetic Ring
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, magnetic-field, particle-trails, upgraded-rgba
//  Complexity: High
//  Chunks From: magnetic-ring, bass_env, hash21
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let baseRadius = mix(0.02, 0.45, u.zoom_params.x);
    let strength = u.zoom_params.y * bass_env(bass, mids);
    let pulseSpeed = mix(0.5, 8.0, u.zoom_params.z);
    let ringThickness = mix(0.01, 0.18, u.zoom_params.w);

    let dVec = uv - mousePos;
    let dVecAspect = vec2<f32>(dVec.x * aspect, dVec.y);
    let dist = length(dVecAspect);
    let safeDir = dVecAspect / max(dist, 0.001);
    let pulse = sin(time * pulseSpeed * bass_env(bass, mids) - dist * 20.0) * 0.5 + 0.5;

    // Multiple concentric rings for field line effect
    let rings = 3.0;
    var ringMask = 0.0;
    var fieldLines = 0.0;
    for (var i: f32 = 0.0; i < rings; i = i + 1.0) {
      let r = baseRadius * (1.0 + i * 0.6);
      let m = 1.0 - smoothstep(0.0, ringThickness, abs(dist - r));
      ringMask = ringMask + m;
      let fieldAngle = atan2(dVecAspect.y, dVecAspect.x) + i * 1.047;
      let fl = smoothstep(0.0, 0.05, abs(fract(fieldAngle * 8.0 / (i + 1.0)) - 0.5)) * m;
      fieldLines = fieldLines + fl;
    }
    ringMask = clamp(ringMask, 0.0, 1.0);

    let displacement = safeDir * ringMask * strength * (0.03 + pulse * 0.04);
    let offsetUV = vec2<f32>(displacement.x / aspect, displacement.y);

    let baseUV = clamp(uv + offsetUV, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let rgbOffset = offsetUV * (0.35 + strength * 0.85);
    let rUV = clamp(uv + rgbOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let gUV = baseUV;
    let bUV = clamp(uv - rgbOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let gColor = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let ringGlow = vec3<f32>(0.2 + treble * 0.1, 0.4 + mids * 0.1, 0.7) * ringMask * (0.3 + pulse * 0.7);
    let fieldGlow = vec3<f32>(0.1, 0.8, 1.0) * fieldLines * pulse * 0.5;
    let finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        gColor.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    ) + ringGlow + fieldGlow;

    let alpha = clamp(gColor.a * 0.45 + ringMask * 0.3 + bass * 0.05 + fieldLines * 0.1, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + ringMask * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
