// ═══════════════════════════════════════════════════════════════════
//  Origami Fold
//  Category: geometric
//  Features: mouse-driven, audio-reactive, paper-fold, depth-shadow, chromatic-edge, upgraded-rgba
//  Complexity: High
//  Chunks From: origami-fold, bass_env
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthShadow = mix(0.6, 1.2, depth);

    let radius = u.zoom_params.x;
    let shadowStrength = u.zoom_params.y * depthShadow;
    let angle = u.zoom_params.z * bass_env(bass, mids);
    let transparency = u.zoom_params.w;

    let foldDir = vec2<f32>(cos(angle), sin(angle));
    let dist = dot(uv - mousePos, foldDir);

    var finalColor = vec4<f32>(0.0);
    if (dist > 0.0) {
        finalColor = vec4<f32>(0.0);
    } else {
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

        let sourceUV = uv - 2.0 * dist * foldDir;
        if (sourceUV.x >= 0.0 && sourceUV.x <= 1.0 && sourceUV.y >= 0.0 && sourceUV.y <= 1.0) {
            let shadow = 1.0 - smoothstep(0.0, 0.1 + radius, abs(dist)) * shadowStrength;
            let flapColor = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
            let darkened = vec4<f32>(flapColor.rgb * 0.9, flapColor.a);

            // Chromatic edge: treble adds RGB separation near crease
            let edge = smoothstep(0.0, 0.05, abs(dist));
            let chroma = treble * 0.02 * edge;
            let r = textureSampleLevel(readTexture, u_sampler, clamp(sourceUV + vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
            let b = textureSampleLevel(readTexture, u_sampler, clamp(sourceUV - vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
            let chromaFlap = vec4<f32>(r, darkened.g, b, darkened.a);

            finalColor = mix(chromaFlap, finalColor, transparency);
            finalColor = vec4<f32>(finalColor.rgb * shadow, finalColor.a);

            // Bass adds warm glow to crease
            let creaseGlow = bass * 0.1 * smoothstep(0.05, 0.0, abs(dist));
            finalColor = finalColor + vec4<f32>(creaseGlow, creaseGlow * 0.5, 0.0, 0.0);
        }
    }

    let alpha = clamp(finalColor.a + (1.0 - smoothstep(0.0, 0.1, abs(dist))) * 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor.rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor.rgb, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
