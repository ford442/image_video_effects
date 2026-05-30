// ═══════════════════════════════════════════════════════════════════
//  Mouse Pixel Sort
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Chunks From: mouse-pixel-sort
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

fn get_luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let isMouseDown = u.zoom_config.w;
    let aspect = resolution.x / resolution.y;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let sortThreshold = u.zoom_params.x;
    let sortLength = u.zoom_params.y * (0.2 + bass * 0.06);
    let direction = u.zoom_params.z;
    let mode = u.zoom_params.w;

    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let influence = smoothstep(0.35, 0.0, dist);
    var localThreshold = mix(sortThreshold, sortThreshold * 0.35, influence * (0.55 + isMouseDown * 0.45));

    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = get_luma(base.rgb);

    var offset = 0.0;
    if (luma > localThreshold) {
        offset = (luma - localThreshold) * sortLength;
    }
    if (mode > 0.5 && luma < (1.0 - localThreshold)) {
        offset = ((1.0 - localThreshold) - luma) * sortLength;
    }

    let audioJitter = vec2<f32>(
        sin(uv.y * 40.0 + u.config.x * (3.0 + treble * 8.0)),
        cos(uv.x * 36.0 + u.config.x * (2.5 + mids * 5.0))
    ) * 0.003 * influence;
    var sourceUV = uv + audioJitter;
    if (direction > 0.5) {
        sourceUV.x -= offset;
    } else {
        sourceUV.y -= offset;
    }
    sourceUV = clamp(sourceUV, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let sorted = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
    let trailTint = mix(
        vec3<f32>(0.1, 0.95, 1.0),
        vec3<f32>(1.0, 0.5 + treble * 0.2, 0.18),
        select(0.0, 1.0, mode > 0.5)
    );
    let streak = smoothstep(localThreshold, 1.0, luma);
    let finalColor = sorted.rgb + trailTint * streak * influence * (0.15 + bass * 0.12);
    let alpha = clamp(sorted.a * 0.4 + offset * 5.0 + influence * 0.12 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sourceUV, 0.0).r + offset * 0.25, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(offset, influence, streak, alpha));
}
