// ═══════════════════════════════════════════════════════════════════
//  Pinch Sphere
//  Category: distortion
//  Features: mouse-driven, 3d-pinch, bulge, fisheye
//  Complexity: Medium
//  Created: 2026-05-31
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
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    let bulge = u.zoom_params.x * 1.5;
    let radius = u.zoom_params.y * 0.4 + 0.1;
    let curvature = u.zoom_params.z * 2.0;
    let edgeDarken = u.zoom_params.w;

    var mouse = u.zoom_config.yz;

    var centered = uv - mouse;
    centered.x *= aspect;

    let dist = length(centered);
    var finalUV = uv;

    if (dist < radius && dist > 0.0001) {
        let normalizedDist = dist / radius;

        // Sphere projection: map flat UV to spherical surface
        let theta = asin(normalizedDist);
        let sphereDist = theta / (3.14159265 * 0.5);

        // Apply bulge with curvature control
        let bulgeFactor = mix(1.0, sphereDist / normalizedDist, bulge);

        // Pinch toward center based on distance
        let pinchAmount = pow(normalizedDist, curvature + 1.0);
        let pinchFactor = mix(bulgeFactor, 1.0 + (1.0 - bulgeFactor) * pinchAmount, 0.5);

        var displaced = centered * pinchFactor;
        displaced.x /= aspect;
        finalUV = mouse + displaced;
    }

    finalUV = clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

    // Edge darkening for 3D feel
    let edgeDist = length(centered) / radius;
    let darkening = mix(1.0, 1.0 - edgeDarken * 0.5, smoothstep(0.5, 1.0, edgeDist));
    color *= darkening;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
