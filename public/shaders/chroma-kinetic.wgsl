// ═══════════════════════════════════════════════════════════════════
//  Chroma Kinetic
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, velocity-chromatic, directional-smear, upgraded-rgba
//  Complexity: High
//  Chunks From: chroma-kinetic, bass_env, temporal-feedback
//  Created: 2026-05-10
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
  return 1.0 + bass * 0.4 + mids * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = mix(0.5, 1.5, depth);

    let strength = u.zoom_params.x * 0.1 * bass_env(bass, mids) * depthMod;
    let radius = u.zoom_params.y;
    let lumaInf = u.zoom_params.z;
    let rotation = u.zoom_params.w * 6.28318;

    let diff = uv - mousePos;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);
    let dir = select(vec2<f32>(0.0), normalize(diffAspect), dist > 0.001);

    let c = cos(rotation);
    let s = sin(rotation);
    let rotDir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
    let uvOffsetDir = vec2<f32>(rotDir.x / max(aspect, 0.001), rotDir.y);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let falloff = smoothstep(max(radius, 0.001), 0.0, dist);
    let modFactor = max(0.0, 1.0 + (luma - 0.5) * lumaInf * 2.0);

    // Velocity chromatic aberration: R leads, B lags based on motion direction
    let velocity = uvOffsetDir * strength * falloff * modFactor;
    let leadAmount = velocity * (1.0 + bass * 0.5);
    let lagAmount = velocity * (1.0 + mids * 0.3);

    let uvR = clamp(uv - leadAmount, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv - velocity * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + lagAmount, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Directional smear: sample along velocity vector for motion trails
    let smearSamples = 3;
    var smearR = 0.0;
    var smearG = 0.0;
    var smearB = 0.0;
    for (var i = 1; i <= smearSamples; i = i + 1) {
        let t = f32(i) / f32(smearSamples);
        let smearUV = clamp(uv + velocity * t * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
        let smearColor = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
        smearR = smearR + smearColor.r * (1.0 - t);
        smearG = smearG + smearColor.g * (1.0 - t);
        smearB = smearB + smearColor.b * (1.0 - t);
    }
    smearR = smearR / f32(smearSamples);
    smearG = smearG / f32(smearSamples);
    smearB = smearB / f32(smearSamples);

    let finalR = mix(r, smearR, bass * 0.3);
    let finalG = mix(g, smearG, mids * 0.2);
    let finalB = mix(b, smearB, treble * 0.2);
    let color = vec3<f32>(finalR, finalG, finalB);

    // Audio split: bass shifts hue globally, mids add glow
    let dispersion = length(velocity) / max(strength, 0.001);
    let alpha = clamp(falloff * modFactor * 0.6 + dispersion * 0.3 + 0.1 + treble * 0.05, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalRGBA);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalRGBA);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
