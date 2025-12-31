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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;

    // Params
    // x: axis angle (0 = vertical, 1 = horizontal/spin) -- simplifying to just vertical first
    // y: offset (from mouse)
    // z: side (0 = left reflected to right, 1 = right reflected to left)
    // w: kaleidoscope mode (0 = off, 1 = on)

    // Simplified Mirror Drag
    // Axis is vertical at Mouse X.
    let axisX = mousePos.x;
    let side = u.zoom_params.x > 0.5; // Switch which side is the "source"
    let flipY = u.zoom_params.y > 0.5; // Also mirror Y at Mouse Y?
    let smooth_edge = u.zoom_params.z;

    var finalUV = uv;

    // Horizontal Mirror
    if (side) {
        // Source is Right (uv.x > axisX)
        // If we are on Left (uv.x < axisX), we want to sample from Right
        if (finalUV.x < axisX) {
            finalUV.x = axisX + (axisX - finalUV.x);
        }
    } else {
        // Source is Left (uv.x < axisX)
        // If we are on Right (uv.x > axisX), sample from Left
        if (finalUV.x > axisX) {
            finalUV.x = axisX - (finalUV.x - axisX);
        }
    }

    // Vertical Mirror
    if (flipY) {
        let axisY = mousePos.y;
        if (finalUV.y > axisY) {
             finalUV.y = axisY - (finalUV.y - axisY);
        }
    }

    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

    // Draw a thin line at axis?
    let distToAxis = abs(uv.x - axisX);
    if (distToAxis < 0.002) {
       // color = vec3(1.0) - color; // Invert color at axis
    }

    textureStore(writeTexture, global_id.xy, vec4(color, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
