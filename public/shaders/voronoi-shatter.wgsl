// ═══════════════════════════════════════════════════════════════════
//  Voronoi Shatter
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: voronoi-shatter
//  Created: 2026-05-30
//  By: Copilot CLI
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

// Simple Hash
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Params
    let density = (u.zoom_params.x * 50.0 + 5.0) * (1.0 + bass * 0.15);
    let shatterForce = u.zoom_params.y * (1.0 + bass * 0.25);
    let rotationStr = clamp(u.zoom_params.z + mids * 0.15, 0.0, 1.0);
    let gapSize = u.zoom_params.w * 0.2; // 0 to 0.2

    var mouse = u.zoom_config.yz;

    // Scale UV
    let uvScaled = vec2<f32>(uv.x * aspect, uv.y) * density;
    let i_st = floor(uvScaled);
    let f_st = fract(uvScaled);

    var m_dist: f32 = 10.0; // Min distance
    var m_point: vec2<f32>; // Closest point (cell center relative to grid)
    var m_id: vec2<f32>;    // ID of the cell

    // Check 3x3 neighbor grids
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var p = hash22(i_st + neighbor); // Random point in cell
            let pointPos = neighbor + p;
            let diff = pointPos - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                m_point = pointPos;
                m_id = i_st + neighbor;
            }
        }
    }

    // Global Cell Center
    let globalCellCenter = (m_id + hash22(m_id)) / density;
    let globalCellCenterUV = vec2<f32>(globalCellCenter.x / aspect, globalCellCenter.y);

    // Interaction
    let vecToMouse = globalCellCenterUV - mouse;
    // Aspect correct distance
    let distMouse = length(vec2<f32>(vecToMouse.x * aspect, vecToMouse.y));

    // Force field
    let interactionRadius = 0.4;
    let influence = smoothstep(interactionRadius, 0.0, distMouse) * shatterForce; // 1 at mouse, 0 far away

    // Displacement: Move shard AWAY from mouse
    let vecLen = max(length(vecToMouse), 0.0001);
    let displace = (vecToMouse / vecLen) * influence * (0.2 + treble * 0.05);

    // Rotation
    let rotAngle = influence * rotationStr * 3.14; // Rotate up to 180 deg

    // Local coords relative to cell center
    let pixelPosAspect = vec2<f32>(uv.x * aspect, uv.y);
    let centerPosAspect = vec2<f32>(globalCellCenterUV.x * aspect, globalCellCenterUV.y);
    let localPos = pixelPosAspect - centerPosAspect;

    let s = sin(-rotAngle);
    let c = cos(-rotAngle);
    let rotatedLocal = vec2<f32>(
        localPos.x * c - localPos.y * s,
        localPos.x * s + localPos.y * c
    );

    // Final Sample Pos (Aspect Corrected)
    let samplePosAspect = centerPosAspect + rotatedLocal - vec2<f32>(displace.x * aspect, displace.y);

    // Back to UV
    let sampleUV = clamp(
        vec2<f32>(samplePosAspect.x / aspect, samplePosAspect.y),
        vec2<f32>(0.001, 0.001),
        vec2<f32>(0.999, 0.999)
    );

    let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Add shading for 3D effect based on m_dist (distance to center)
    let edge = smoothstep(0.18 + gapSize * 0.25, 0.55, m_dist);
    let shardLight = (1.0 - edge) * (0.2 + bass * 0.1);
    let seamGlow = smoothstep(0.3 - gapSize, 0.55, m_dist) * (0.08 + treble * 0.12);
    let finalColor = baseColor.rgb * (1.0 + shardLight) + vec3<f32>(0.05, 0.09, 0.16) * seamGlow;
    let finalAlpha = clamp(0.26 + (1.0 - edge) * 0.28 + influence * 0.35 + bass * 0.08, 0.18, 0.95);
    let depth = clamp(
        textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + influence * 0.06,
        0.0,
        1.0
    );

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(m_dist, influence, rotAngle / 3.14, finalAlpha));
}
