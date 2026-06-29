// ═══════════════════════════════════════════════════════════════════
//  hyb-kaleidoscope-pulse
//  Category: hybrid
//  Features: kaleidoscope, radial-pulse, image-remix, alpha-passthrough, depth-passthrough
//  Chunks: kaleidoscope + rdPulse (with glow)
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

// ── Chunk: glow (from anamorphic-flare.wgsl) ──
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    let safeRadius = max(radius, 0.001);
    return exp(-dist * dist / (safeRadius * safeRadius)) * intensity;
}

// ── Chunk: kaleidoscope (from kaleidoscope.wgsl) ──
fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
    let safeSegments = max(segments, 1.0);
    let angle = atan2(uv.y, uv.x);
    let radius = length(uv);
    let segmentAngle = 6.28318 / safeSegments;
    let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
    return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}

// ── Chunk: rdPulse (from gen-bioelectric-pulse.wgsl) ──
fn rdPulse(p: vec2<f32>, center: vec2<f32>, time: f32, speed: f32, width: f32) -> f32 {
    let d = length(p - center);
    let phase = d * 8.0 - time * speed * 4.0;
    let wave = sin(phase) * 0.5 + 0.5;
    let envelope = exp(-d * d * 2.0) * (1.0 - smoothstep(0.0, 1.5, d));
    return wave * envelope * glow(d, width, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    let dimsI = vec2<i32>(dims);

    if (any(coord >= dimsI)) {
        return;
    }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Normalize zoom_params
    let time = u.config.x;
    let segments = mix(3.0, 16.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let pulseSpeed = mix(0.2, 3.0, clamp(u.zoom_params.y, 0.0, 1.0));
    let pulseWidth = mix(0.05, 0.6, clamp(u.zoom_params.z, 0.0, 1.0));
    let effectMix = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

    // Kaleidoscope in centered coordinates
    let centered = uv - 0.5;
    let kUV = kaleidoscope(centered, segments);
    let sampleUV = clamp(kUV + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let kaleido = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Organic radial pulse overlaid at the kaleidoscope center
    let pulse = rdPulse(centered, vec2<f32>(0.0), time, pulseSpeed, pulseWidth);
    let pulseColor = pulse * vec3<f32>(0.5, 0.85, 1.0);

    let outRGB = mix(kaleido.rgb, kaleido.rgb + pulseColor, effectMix);

    textureStore(writeTexture, coord, vec4<f32>(outRGB, src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
