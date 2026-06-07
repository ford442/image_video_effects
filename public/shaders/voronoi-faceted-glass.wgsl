// ═══════════════════════════════════════════════════════════════════
//  Voronoi Faceted Glass
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: voronoi-faceted-glass
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
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

// Random function
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
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let aspect = resolution.x / resolution.y;
    var uvCorrected = vec2<f32>(uv.x * aspect, uv.y);

    // Grid size
    let density = 8.0 + u.zoom_params.x * 28.0 * (1.0 + bass * 0.2);
    let refraction = 0.015 + u.zoom_params.y * 0.06;
    let shimmer = u.zoom_params.z;
    let edgeSoftness = u.zoom_params.w;
    let gridUV = uvCorrected * density;
    let gridIndex = floor(gridUV);
    let gridFract = fract(gridUV);

    var minDist = 1.0;
    var cellId = vec2<f32>(0.0);
    var cellCenter = vec2<f32>(0.0);

    // Check 3x3 neighbors
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var p = gridIndex + neighbor;

            // Random point in cell, animated
            var point = hash22(p);

            // Animate point
            point = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point);

            // Mouse interaction: push points away or pull them
            var mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
            let worldPoint = (p + point) / density;
            let distToMouse = distance(worldPoint, mousePos);

            // Distortion based on mouse
            if (distToMouse < 0.5) {
                let pushVec = worldPoint - mousePos;
                let pushLen = max(length(pushVec), 0.0001);
                let push = (pushVec / pushLen) * (0.5 - distToMouse) * (0.2 + 0.25 * treble);
                point = point + push * (0.35 + shimmer * 0.35);
            }

            let diff = neighbor + point - gridFract;
            let dist = length(diff);

            if (dist < minDist) {
                minDist = dist;
                cellId = p;
                cellCenter = (p + point) / density;
            }
        }
    }

    // cellCenter is the UV coordinate of the Voronoi cell center (corrected for aspect)
    // Convert back to UV space
    let mouseHighlight = 1.0 - smoothstep(0.08, 0.35, distance(uv, u.zoom_config.yz));
    var sampleUV = cellCenter;
    sampleUV.x = sampleUV.x / aspect;
    sampleUV = clamp(
        mix(sampleUV, uv + (sampleUV - uv) * refraction, 0.6 + mids * 0.2),
        vec2<f32>(0.001, 0.001),
        vec2<f32>(0.999, 0.999)
    );

    // Add some "glass" refraction based on distance to center of cell
    // Edges of cells distort more?
    // Let's just sample the image at the cell center (mosaic effect)
    // And mix it with a slightly distorted version based on local coordinates

    // "Glass" look: the UV used to sample the texture is the original UV,
    // but displaced by the vector to the cell center.
    // vec2 offset = (uv - sampleUV);
    // actually, let's just sample AT the cell center for a faceted look
    // Then add some shading at the edges (minDist is distance to center)

    // To make it look like glass, we might want to sample *around* the center based on normal
    // But simple mosaic is: sample at sampleUV.

    let sampled = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Add cell borders/highlights
    // minDist is distance to the seed point.
    // Border is where minDist of two cells are close? No, that's complex to find here without second pass.
    // But we can darken edges based on minDist (0 at center, 0.5+ at edges)
    // Actually minDist is distance to the *closest* point. It maxes out around 0.5-0.7.

    let shade = 1.0 - smoothstep(0.25 + edgeSoftness * 0.1, 0.6, minDist);
    let spectral = vec3<f32>(0.05 + treble * 0.12, 0.08 + mids * 0.08, 0.15 + bass * 0.1);
    let finalColor = sampled.rgb * (0.82 + 0.22 * shade) + spectral * (mouseHighlight * 0.35 + (1.0 - shade) * 0.1);
    let finalAlpha = clamp(0.28 + shade * 0.25 + mouseHighlight * 0.2 + bass * 0.08, 0.18, 0.92);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + shade * 0.04, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(minDist, shade, mouseHighlight, finalAlpha));
}
