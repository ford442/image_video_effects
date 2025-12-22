// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Growth buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // Normal buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,         // x=Scale, y=Thickness, z=Radius, w=Chaos
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let baseScale = max(0.005, u.zoom_params.x * 0.1); // 0.005 to 0.1
    let thickness = max(0.05, u.zoom_params.y);
    let mouseRadius = u.zoom_params.z;
    let chaosAmt = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;
    let d = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));

    // Mouse Interaction: Unravel / Distort Scale
    var influence = smoothstep(mouseRadius, 0.0, d);

    var gridUV = uv;
    if (influence > 0.0) {
       // Add noise to UV based on chaos
       let noise = (hash22(uv * 10.0 + u.config.x) - 0.5) * chaosAmt * 0.1 * influence;
       gridUV += noise;
    }

    // Grid Logic
    // We want 'scale' to be constant for quantization, so we don't vary it per pixel for the grid calculation itself
    // unless we want warped grid cells.
    // If we want the grid lines to bend, we distort gridUV.

    let gridID = floor(gridUV / baseScale);
    let gridCenter = (gridID + 0.5) * baseScale;
    let localUV = (gridUV - gridID * baseScale) / baseScale; // 0 to 1

    // Sample image at grid center to get the thread color
    let color = textureSampleLevel(readTexture, u_sampler, gridCenter, 0.0).rgb;

    // Draw X Shape
    // Diagonal 1: y = x  => abs(x - y)
    // Diagonal 2: y = 1-x => abs(x + y - 1)

    let d1 = abs(localUV.x - localUV.y);
    let d2 = abs(localUV.x + localUV.y - 1.0);

    let lineDist = min(d1, d2);

    // Mask for the thread
    let mask = 1.0 - smoothstep(thickness * 0.5, thickness * 0.5 + 0.1, lineDist);

    // Add some thread texture/shading
    let thread = sin(localUV.x * 30.0) * sin(localUV.y * 30.0) * 0.2 + 0.8;

    // Shadow under the thread
    let shadow = smoothstep(thickness + 0.1, thickness + 0.3, lineDist);

    // Background cloth (dark fabric)
    let cloth = vec3<f32>(0.1, 0.1, 0.15);

    // Final Mix
    var finalColor = mix(cloth * shadow, color * thread, mask);

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
