// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, 
  zoom_params: vec4<f32>,  // x=Curvature, y=ScanlineOpacity, z=Aberration, w=Vignette
  ripples: array<vec4<f32>, 50>,
};

fn curve_uv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
    var centered = uv * 2.0 - 1.0;
    let offset = abs(centered.yx) / vec2<f32>(curvature, curvature);
    centered = centered + centered * offset * offset;
    return centered * 0.5 + 0.5;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let curve_str = mix(20.0, 3.0, u.zoom_params.x); // Slider 0.0->Flat, 1.0->Curved
    let scan_str = u.zoom_params.y;
    let abb_str = u.zoom_params.z * 0.01;
    let vig_str = u.zoom_params.w + 0.5;

    // 1. Curvature
    var crt_uv = uv;
    if (u.zoom_params.x > 0.05) {
        crt_uv = curve_uv(uv, curve_str);
    }

    var color = vec3<f32>(0.0);

    // Bounds check after curvature
    if (crt_uv.x < 0.0 || crt_uv.x > 1.0 || crt_uv.y < 0.0 || crt_uv.y > 1.0) {
        color = vec3<f32>(0.0);
    } else {
        // 2. Chromatic Aberration
        let r = textureSampleLevel(readTexture, u_sampler, crt_uv + vec2<f32>(abb_str, 0.0), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, crt_uv, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, crt_uv - vec2<f32>(abb_str, 0.0), 0.0).b;
        color = vec3<f32>(r, g, b);

        // 3. Scanlines
        let scanline = sin(crt_uv.y * resolution.y * 0.5 + time * 10.0);
        let scan_darken = 1.0 - (scan_str * 0.5 * (1.0 + scanline));
        color *= scan_darken;

        // 4. Vignette
        let vig = uv * (1.0 - uv.yx);
        let v_val = vig.x * vig.y * 15.0; // strength
        let v_final = pow(v_val, vig_str);
        color *= v_final;
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Pass through original depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
