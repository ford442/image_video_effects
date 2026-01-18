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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2(0.0,0.0)), hash12(i + vec2(1.0,0.0)), u.x),
               mix(hash12(i + vec2(0.0,1.0)), hash12(i + vec2(1.0,1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let slice_height = mix(0.01, 0.3, u.zoom_params.x);
    let shift_amt = u.zoom_params.y * 0.5;
    let speed = u.zoom_params.z * 10.0;
    let rgb_split = u.zoom_params.w * 0.1;

    // Determine if we are in the slice band
    // Slice is centered on mouse.y
    let distY = abs(uv.y - mouse.y);

    var offset = 0.0;
    var split = 0.0;

    if (distY < slice_height) {
        // Falloff
        let strength = smoothstep(slice_height, 0.0, distY);

        // Generate noise for shift
        // Quantize Y for blocky look?
        let quantY = floor(uv.y * 50.0) / 50.0;
        let n = noise(vec2(quantY * 10.0, time * speed));

        offset = (n - 0.5) * shift_amt * strength;
        split = rgb_split * strength;
    }

    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset + split, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset - split, 0.0), 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
