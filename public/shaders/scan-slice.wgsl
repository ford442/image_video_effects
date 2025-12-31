// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let sliceWidth = u.zoom_params.x * 0.2 + 0.01;
    let offsetParam = u.zoom_params.y; // 0-1
    let aberration = u.zoom_params.z * 0.03;
    let dimming = u.zoom_params.w;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Define slice bounds centered on mouse X
    let sliceMin = mouse.x - sliceWidth;
    let sliceMax = mouse.x + sliceWidth;

    var finalColor = vec4<f32>(0.0);

    if (uv.x > sliceMin && uv.x < sliceMax) {
        // Inside slice
        // Map mouse Y to an offset (-1 to 1 range approx)
        // Let's make the offset relative to the center 0.5
        let yOffset = (mouse.y - 0.5) * (offsetParam * 2.0);

        let sampleUV = uv + vec2<f32>(0.0, yOffset);

        // Chromatic Aberration
        let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

        finalColor = vec4<f32>(r, g, b, 1.0);

        // Highlight edges of slice
        let distToEdge = min(abs(uv.x - sliceMin), abs(uv.x - sliceMax));
        let edgeGlow = smoothstep(0.005, 0.0, distToEdge);
        finalColor += vec4<f32>(1.0) * edgeGlow;

    } else {
        // Outside slice
        let col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        let gray = dot(col.rgb, vec3<f32>(0.299, 0.587, 0.114));
        // Desaturate based on dimming
        finalColor = mix(col, vec4<f32>(vec3<f32>(gray), 1.0), dimming);
        // Darken based on dimming
        finalColor = finalColor * (1.0 - dimming * 0.6);
    }

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
