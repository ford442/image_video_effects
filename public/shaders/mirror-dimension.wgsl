// ═══════════════════════════════════════════════════════════════════
//  Mirror Dimension
//  Category: kaleidoscope
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let segments  = floor(mix(2.0, 12.0, u.zoom_params.x));
    let baseRotSpeed = mix(-1.0, 1.0, u.zoom_params.y);
    // Bass modulates rotation speed
    let rotSpeed  = baseRotSpeed * (1.0 + bass * 0.5);
    let offsetVal = u.zoom_params.z;
    // Mids modulate zoom intensity
    let zoom      = mix(0.5, 2.0, u.zoom_params.w) * (1.0 + mids * 0.15);

    // Center UV and correct aspect
    var p = uv - 0.5;
    let aspect = resolution.x / max(resolution.y, 0.001);
    p.x *= aspect;

    // Branchless mouse offset: apply when zoom_config.y > 0
    let mouseActive = step(0.001, u.zoom_config.y);
    let m = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    p -= m * mouseActive;

    // Polar coords
    let r = length(p);
    var a = atan2(p.y, p.x);

    // Animate rotation
    a += u.config.x * rotSpeed;

    // Segment angle
    let segmentAngle = 3.14159265 * 2.0 / max(segments, 1.0);

    // Branchless modulo into [0, segmentAngle] using fract — handles negatives
    a = fract(a / segmentAngle) * segmentAngle;

    // Triangle fold (mirror half of the segment)
    a = abs(a - segmentAngle * 0.5);

    // Convert back to cartesian
    var uv_new = vec2<f32>(cos(a), sin(a)) * r;

    // Offset and zoom
    uv_new += vec2<f32>(offsetVal * 0.1);
    uv_new *= zoom;

    // Un-correct aspect and un-center
    uv_new.x /= aspect;
    uv_new += 0.5;

    // Clamp displaced UV before sampling
    let uv_clamped = clamp(uv_new, vec2<f32>(0.0), vec2<f32>(1.0));

    let sampled = textureSampleLevel(readTexture, u_sampler, uv_clamped, 0.0);

    // Meaningful alpha: encodes radial position + fold angle closeness + bass energy
    let foldCloseness = 1.0 - clamp(a / max(segmentAngle * 0.5, 0.001), 0.0, 1.0);
    let radialFactor  = clamp(1.0 - r * 0.8, 0.0, 1.0);
    let alpha = clamp(radialFactor * 0.5 + foldCloseness * 0.3 + bass * 0.2, 0.0, 1.0);

    let finalColor = vec4<f32>(sampled.rgb, alpha);

    textureStore(writeTexture, coord, finalColor);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
