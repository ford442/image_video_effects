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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Mag, z=Twist, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;

    let radius = u.zoom_params.x * 0.5; // Scale radius
    let magnification = u.zoom_params.y * 3.0 + 0.1; // 0.1 to 3.1
    let twist = (u.zoom_params.z - 0.5) * 20.0; // -10 to 10
    let aberration = u.zoom_params.w * 0.05;

    let aspect = resolution.x / resolution.y;
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    var finalUV = uv;

    // Smooth falloff
    let mask = smoothstep(radius, 0.0, dist);

    if (mask > 0.0) {
        // Twist
        let angle = twist * mask * mask;
        let s = sin(angle);
        let c = cos(angle);
        let rot = mat2x2<f32>(c, -s, s, c);

        let offset = uv - mouse;
        // Correct to square space for rotation
        var p = offset * vec2<f32>(aspect, 1.0);
        p = rot * p;
        // Back to UV space
        p = p / vec2<f32>(aspect, 1.0);

        // Magnification (Spherize)
        // If mag > 1, we want to sample closer to center.
        let zoom_factor = 1.0 / magnification;
        let current_zoom = mix(1.0, zoom_factor, mask);

        p = p * current_zoom;

        finalUV = mouse + p;
    }

    // Chromatic Aberration
    let r_uv = finalUV + (mouse - finalUV) * aberration * mask;
    let b_uv = finalUV - (mouse - finalUV) * aberration * mask;

    let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));

    // Depth pass-through (using center UV for simplicity)
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
