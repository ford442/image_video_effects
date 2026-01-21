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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    let mouse = u.zoom_config.yz;
    let radius = 0.25;
    let mag_strength = 0.5;

    // Distance to mouse (corrected for aspect)
    let d = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    var final_uv = uv;
    var chromatic_shift = vec2<f32>(0.0);

    if (d < radius) {
        // Spherical distortion
        // Map d from 0..radius to 0..1..0
        let x = d / radius;
        // Distortion curve: stronger at center, tapers to edges.
        // Simple magnification: pull uv towards mouse
        let distort = (1.0 - x * x) * mag_strength;

        let dir = uv - mouse;
        final_uv = mouse + dir * (1.0 - distort);

        // Add chromatic aberration at edges of lens
        let chrom_amt = smoothstep(0.5, 1.0, x) * 0.02;
        chromatic_shift = normalize(dir) * chrom_amt;
    }

    // Sample with chromatic aberration
    let r = textureSampleLevel(readTexture, u_sampler, final_uv + chromatic_shift, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, final_uv - chromatic_shift, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Glass edge highlight
    if (d < radius && d > radius * 0.95) {
        color += vec3<f32>(0.3); // specular ring
    }

    // Slight shadow outside
    if (d >= radius && d < radius * 1.05) {
        color *= 0.8;
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
