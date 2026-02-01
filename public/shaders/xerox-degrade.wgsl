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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let contrast = u.zoom_params.x * 4.0 + 1.0; // 1.0 to 5.0
    let grain_amt = u.zoom_params.y;
    let smear_amt = u.zoom_params.z;
    let threshold = u.zoom_params.w;

    // Smear Logic
    // Create horizontal streaks based on Y and noise
    let smear_noise = (hash12(vec2<f32>(uv.y * 150.0, time * 0.1)) - 0.5) * smear_amt * 0.1;
    let smear_uv = vec2<f32>(uv.x + smear_noise, uv.y);

    // Bounds check for smear
    var color: vec4<f32>;
    if (smear_uv.x < 0.0 || smear_uv.x > 1.0) {
        color = vec4<f32>(1.0, 1.0, 1.0, 1.0); // Paper edge
    } else {
        color = textureSampleLevel(readTexture, u_sampler, smear_uv, 0.0);
    }

    // Grayscale
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // High Contrast / Threshold
    // Soft threshold using smoothstep or just linear contrast stretch
    var final_luma = (luma - threshold) * contrast + 0.5;
    final_luma = clamp(final_luma, 0.0, 1.0);

    // Grain
    // Static noise
    let noise = hash12(uv * resolution + time);

    // Toner scatter (dark spots in light areas)
    if (noise < grain_amt * 0.2) {
        final_luma -= 0.4 * grain_amt;
    }

    // Paper noise (light spots in dark areas)
    if (noise > 1.0 - grain_amt * 0.2) {
        final_luma += 0.3 * grain_amt;
    }

    final_luma = clamp(final_luma, 0.0, 1.0);

    // Coloring
    // Deep dark blue-black for toner, off-white for paper
    let paper_white = vec3<f32>(0.96, 0.96, 0.92); // Slightly yellowed
    let toner_black = vec3<f32>(0.05, 0.05, 0.12); // Blueish toner

    let final_color = mix(toner_black, paper_white, final_luma);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, 1.0));
}
