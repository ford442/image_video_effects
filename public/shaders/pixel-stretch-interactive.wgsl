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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let mouse = u.zoom_config.yz; // Normalized mouse pos

    // Params
    // x: Direction Mode (0.0-0.33: Right, 0.33-0.66: Left, 0.66-1.0: Cross)
    // y: Jitter/Noise strength
    // z: RGB Shift strength

    let modeParam = u.zoom_params.x;
    let jitterStr = u.zoom_params.y;
    let rgbShift = u.zoom_params.z;

    var sample_uv = uv;
    var is_stretched = false;

    // Determine Stretch Direction
    if (modeParam < 0.33) {
        // Stretch Right: If pixel is to the right of mouse, use mouse X
        if (uv.x > mouse.x) {
            sample_uv.x = mouse.x;
            is_stretched = true;
        }
    } else if (modeParam < 0.66) {
        // Stretch Left: If pixel is to the left of mouse, use mouse X
        if (uv.x < mouse.x) {
            sample_uv.x = mouse.x;
            is_stretched = true;
        }
    } else {
        // Cross Stretch: Stretch outwards from mouse
        if (uv.x > mouse.x) { sample_uv.x = mouse.x; is_stretched = true; }
        if (uv.y > mouse.y) { sample_uv.y = mouse.y; is_stretched = true; }
        // Note: Quadrants might overlap, simple logic here gives a "corner" stretch
    }

    // Apply effects only to stretched area
    var color: vec4<f32>;

    if (is_stretched) {
        // Jitter
        if (jitterStr > 0.0) {
            let noise = fract(sin(dot(uv * time, vec2(12.9898, 78.233))) * 43758.5453);
            if (noise > 0.5) {
                sample_uv += (noise - 0.5) * 0.1 * jitterStr;
            }
        }

        // RGB Split
        if (rgbShift > 0.0) {
             let shift = rgbShift * 0.02;
             let r = textureSampleLevel(readTexture, u_sampler, sample_uv + vec2(shift, 0.0), 0.0).r;
             let g = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).g;
             let b = textureSampleLevel(readTexture, u_sampler, sample_uv - vec2(shift, 0.0), 0.0).b;
             color = vec4(r, g, b, 1.0);
        } else {
             color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
        }
    } else {
        color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
    }

    textureStore(writeTexture, global_id.xy, color);
}
