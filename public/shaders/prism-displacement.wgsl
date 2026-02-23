// Prism Lens - Creates a prismatic lens effect with chromatic dispersion
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let size = max(u.zoom_params.x * 0.5, 0.05);
    let refraction = u.zoom_params.y * 0.3;
    let rotation = u.zoom_params.z;
    let edgeShine = u.zoom_params.w;

    // Distance from mouse (aspect corrected)
    let aspect = resolution.x / resolution.y;
    let dVec = uv - mousePos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Create lens shape
    let lensMask = 1.0 - smoothstep(size * 0.8, size, dist);

    // Rotate coordinates for the prism effect
    let angle = rotation + time * 0.2;
    let cosA = cos(angle);
    let sinA = sin(angle);
    let rotatedUV = vec2<f32>(
        dVec.x * cosA - dVec.y * sinA,
        dVec.x * sinA + dVec.y * cosA
    );

    // Prism displacement (RGB separation)
    let prismOffset = vec2<f32>(
        sin(rotatedUV.y * 10.0) * refraction * 0.1,
        cos(rotatedUV.x * 10.0) * refraction * 0.1
    );

    // Chromatic aberration - different offsets for each channel
    let rUV = clamp(uv + (prismOffset + vec2<f32>(refraction * 0.02, 0.0)) * lensMask, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + prismOffset * lensMask, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + (prismOffset - vec2<f32>(refraction * 0.02, 0.0)) * lensMask, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Add edge shine
    let edge = smoothstep(size * 0.9, size, dist) - smoothstep(size, size * 1.1, dist);
    color += vec3<f32>(1.0, 0.9, 0.7) * edge * edgeShine;

    // Slight magnification inside lens
    let magnifyUV = clamp(mousePos + dVec * (1.0 - lensMask * 0.2), vec2<f32>(0.0), vec2<f32>(1.0));
    let bgColor = textureSampleLevel(readTexture, u_sampler, magnifyUV, 0.0).rgb;

    // Blend lens effect with background
    let finalColor = mix(bgColor, color, lensMask * 0.8 + 0.2);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
