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

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv_orig = vec2<f32>(global_id.xy) / resolution;
    var uv = uv_orig;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Parameters
    let warp_strength = u.zoom_params.x * 2.0; // 0.0 to 2.0
    let layers = 4;
    let turbulence = u.zoom_params.y; // Frequency scaling

    // Mouse Interaction: Rotate the domain around the mouse
    let aspect = resolution.x / resolution.y;
    let mouse_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(mouse_vec);

    // Swirl near mouse
    let swirl = (1.0 - smoothstep(0.0, 0.5, dist)) * 5.0 * sin(time * 0.5);
    if (dist < 0.5) {
        uv = mouse + (uv - mouse) * rot(swirl);
    }

    // Domain Warping (FBM style)
    var p = uv * 3.0; // Scale up for noise details
    var amp = 1.0;

    for (var i = 0; i < layers; i++) {
        p = p + vec2<f32>(
            sin(p.y * 2.0 + time * 0.2) * 1.0,
            cos(p.x * 2.0 - time * 0.3) * 1.0
        ) * warp_strength * amp;

        // Rotate and scale for next octave
        p = p * rot(1.0);
        p = p * (1.5 + turbulence);
        amp = amp * 0.5;
    }

    // Remap p back to UV space roughly
    // The warping moves coordinates far, so we just use the result 'p' relative to start
    // or wrap it.

    // Marble strategy: Use the warped 'p' to determine color,
    // BUT we want to distort the *image*.

    // So 'p' is our lookup coordinate.
    // We need to normalize it back to 0..1 range or just wrap.
    // Let's interpret the distortion as an offset to original UV.

    let distortion = (p * 0.1) - (uv * 3.0 * 0.1);

    // Dampen distortion based on distance from center/edges to avoid tiling artifacts if desired
    // Or just let it flow.

    let final_uv = uv + distortion * 0.2; // Scale down the total displacement

    // Mirror wrap to avoid ugly edges
    let wrapped_uv = abs(fract(final_uv * 0.5) * 2.0 - 1.0); // Wait, standard wrapping
    // Simple repeat:
    let repeat_uv = fract(final_uv);

    // Mirror repeat is better for fluids
    // let mirror_uv = 1.0 - abs(1.0 - 2.0 * fract(final_uv)); // Something like that

    let color = textureSampleLevel(readTexture, u_sampler, repeat_uv, 0.0);

    // Add some lighting/shading based on the warp gradient?
    // Let's keep it simple: the image just flows.

    textureStore(writeTexture, global_id.xy, color);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
