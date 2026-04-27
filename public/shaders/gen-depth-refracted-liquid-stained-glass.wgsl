// ----------------------------------------------------------------
// Depth-Refracted Liquid Stained Glass
// Category: generative
// ----------------------------------------------------------------

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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=FacetCount, y=BevelWidth, z=Unused, w=Unused
    ripples: array<vec4<f32>, 50>,
};

// 2D Rotation Matrix
fn rot2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(u.config.z, u.config.w);

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let aspect = f32(res.x) / f32(res.y);
    var uv = vec2<f32>(coords) / vec2<f32>(res);
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    // Center point from mouse
    let center = u.zoom_config.yz * 2.0 - 1.0;
    var centered_p = p - vec2<f32>(center.x * aspect, center.y);

    // Polar Folding
    let facetCount = max(3.0, floor(u.zoom_params.x)); // default 6
    let angleStep = 3.14159 * 2.0 / facetCount;

    var a = atan2(centered_p.y, centered_p.x);
    let r = length(centered_p);

    // Rotation over time and audio
    a += u.config.x * 0.2 + u.config.y * 0.5;

    // Fold
    a = (a / angleStep % 1.0 + 1.0) % 1.0;
    a = abs(a - 0.5) * angleStep;

    var folded_p = vec2<f32>(cos(a), sin(a)) * r;

    // Un-aspect
    folded_p.x /= aspect;
    var sample_uv = folded_p * 0.5 + 0.5;

    // Clamp for safety
    sample_uv = clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    // Get depth for refraction
    let depth_val = textureSampleLevel(readDepthTexture, u_sampler, sample_uv, 0.0).r;

    // Edge detection for bevels
    let texSize = vec2<f32>(textureDimensions(readDepthTexture));
    let eps = vec2<f32>(1.0 / texSize.x, 1.0 / texSize.y) * u.zoom_params.y; // Bevel width

    let d_dx = textureSampleLevel(readDepthTexture, u_sampler, sample_uv + vec2<f32>(eps.x, 0.0), 0.0).r - depth_val;
    let d_dy = textureSampleLevel(readDepthTexture, u_sampler, sample_uv + vec2<f32>(0.0, eps.y), 0.0).r - depth_val;
    let normal = normalize(vec3<f32>(d_dx, d_dy, 0.1));

    // Refraction and depth modulation
    let depth_mod = sin(u.config.x * 2.0 + u.config.y * 3.0) * 0.5 + 0.5;
    let ref_str = 0.1 * depth_mod; // Refraction strength based on depth mod

    let offset = normal.xy * ref_str * (1.0 - depth_val);

    // Chromatic Aberration using plasmaBuffer (small offset table)
    let r_offset = plasmaBuffer[0].xy * 0.02;
    let g_offset = plasmaBuffer[1].xy * 0.02;
    let b_offset = plasmaBuffer[2].xy * 0.02;

    var col = vec3<f32>(0.0);
    col.r = textureSampleLevel(readTexture, u_sampler, sample_uv + offset + r_offset, 0.0).r;
    col.g = textureSampleLevel(readTexture, u_sampler, sample_uv + offset + g_offset, 0.0).g;
    col.b = textureSampleLevel(readTexture, u_sampler, sample_uv + offset + b_offset, 0.0).b;

    // Facet Tint curve using plasmaBuffer
    let tint = plasmaBuffer[3].rgb;
    col *= (vec3<f32>(1.0) + tint * 0.5);

    // Bevel highlights
    let edge = length(vec2<f32>(d_dx, d_dy)) * 50.0;
    col += vec3<f32>(smoothstep(0.1, 0.5, edge)) * 0.5;

    // Depth output pseudo
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    textureStore(writeDepthTexture, coords, vec4<f32>(luma, 0.0, 0.0, 1.0));

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
