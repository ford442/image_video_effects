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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Folds, y=Mirror, z=Shift, w=Zoom
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let folds = u.zoom_params.x * 5.0 + 1.0;
    let mirror_str = u.zoom_params.y;
    let dim_shift = u.zoom_params.z;
    let zoom = mix(0.5, 2.0, u.zoom_params.w);

    // Center UV on mouse
    var p = (uv - mouse);
    p.x *= aspect;

    // Folding Logic
    // Convert to polar
    var r = length(p);
    var a = atan2(p.y, p.x);

    // Fold angle
    let fold_angle = 3.14159 / folds;
    // Map angle to domain [0, fold_angle]
    // a = abs(mod(a, 2.0 * fold_angle) - fold_angle); // Simple kaleidoscope
    // Let's do Tesseract style: iterating folds

    for (var i = 0; i < 3; i++) {
        p = abs(p);
        p -= vec2<f32>(0.2 * dim_shift);

        // Rotate
        let angle = 0.5 * dim_shift;
        let c = cos(angle);
        let s = sin(angle);
        p = vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
    }

    // Zoom
    p = p / zoom;

    // Map back to screen space (relative to mouse)
    var final_uv = mouse + p / vec2<f32>(aspect, 1.0);

    // Mirroring
    if (mirror_str > 0.5) {
        final_uv = abs(final_uv - 0.5) + 0.5; // Mirror edge wrap
        // Actually, let's mirror around mouse
        // already done by p = abs(p) above
    }

    let col = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);

    // Add some "dimension shift" color aberration
    let r_uv = final_uv + vec2<f32>(0.01 * dim_shift, 0.0);
    let b_uv = final_uv - vec2<f32>(0.01 * dim_shift, 0.0);

    let cr = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let cb = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(cr, col.g, cb, 1.0));
}
