// ────────────────────────────────────────────────────────────────────────────────
//  Dimension Slicer – Geometric Space Distortion
//  - Opens a "dimensional slice" around the mouse position.
//  - Inside the slice, space is warped, zoomed, and chromatically aberrated.
//  - The slice orientation and width are controllable.
// ────────────────────────────────────────────────────────────────────────────────

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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=SliceWidth, y=Distortion, z=Angle, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / dims;
    let center = vec2<f32>(0.5);
    let aspect = dims.x / dims.y;

    // Parameters
    let sliceWidth = mix(0.05, 0.4, u.zoom_params.x);
    let distortion = mix(0.0, 2.0, u.zoom_params.y);
    let angle = u.zoom_params.z * 3.14159 * 2.0; // 0 to 360
    let aberration = u.zoom_params.w * 0.05;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;

    // Coordinate relative to mouse
    let p = uv - mouse;
    p.x *= aspect;

    // Rotate space to align with slice angle
    let pRot = rotate(p, angle);

    // Distance from the "slice line" (vertical in rotated space)
    let dist = abs(pRot.x);

    // Mask for the slice
    let inSlice = 1.0 - smoothstep(sliceWidth - 0.01, sliceWidth, dist);

    var finalUV = uv;
    var finalColor = vec3<f32>(0.0);

    if (inSlice > 0.0) {
        // Warp UVs inside slice
        // e.g. a magnifying glass effect or directional stretch
        let zoom = 1.0 - distortion * 0.5 * cos(dist / sliceWidth * 3.14159);

        // Offset relative to mouse
        let offset = (uv - mouse) * (1.0/zoom - 1.0);

        let warpedUV = uv + offset * inSlice;

        // Chromatic Aberration
        let r = textureSampleLevel(readTexture, u_sampler, warpedUV + vec2<f32>(aberration, 0.0) * inSlice, 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, warpedUV - vec2<f32>(aberration, 0.0) * inSlice, 0.0).b;

        finalColor = vec3<f32>(r, g, b);

        // Add a glowing edge to the slice
        let edge = smoothstep(sliceWidth - 0.02, sliceWidth, dist) * (1.0 - smoothstep(sliceWidth, sliceWidth + 0.01, dist));
        finalColor += vec3<f32>(0.5, 0.8, 1.0) * edge * 2.0;

    } else {
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    }

    // Soft shadow/darkening outside slice to emphasize it
    if (inSlice < 1.0) {
        let shadow = smoothstep(sliceWidth, sliceWidth + 0.1, dist);
        finalColor *= (0.5 + 0.5 * shadow);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
