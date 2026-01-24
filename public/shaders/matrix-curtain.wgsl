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
	var p3  = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x; // Use global time for rain
    let mouse = u.zoom_config.yz;

    // Params
    let speed = mix(0.5, 5.0, u.zoom_params.x);
    let density = mix(10.0, 100.0, u.zoom_params.y); // Columns
    let curtainWidth = u.zoom_params.z;
    let glitch = u.zoom_params.w;

    // Curtain Interaction
    // Displace UV.x based on Mouse X
    // We want the columns to "part" around the mouse X
    // abs(uv.x - mouse.x)

    let distX = uv.x - mouse.x;
    let push = smoothstep(curtainWidth, 0.0, abs(distX)) * sign(distX);
    // If to the right of mouse, push right (positive). If left, push left.

    // Apply push to the UV used for generating the rain pattern
    // We modify the coordinate we are looking up in the noise function
    var rainUV = uv;
    rainUV.x -= push * 0.2; // The visual columns move away

    // Grid for rain
    let colId = floor(rainUV.x * density);
    let colHash = hash12(vec2(colId, 42.0));

    // Speed variation per column
    let colSpeed = speed * (0.5 + colHash);

    // Y position for rain drops
    let yPos = rainUV.y + time * colSpeed * 0.1;
    let rowId = floor(yPos * density * 0.5); // Rows are taller?

    // Character/Drop logic
    let charHash = hash12(vec2(colId, rowId));

    // Brightness trail
    let dropPos = fract(yPos);
    let trail = 1.0 - dropPos;
    let bright = pow(trail, 3.0);

    // Sample original image
    // We sample at distorted UV to see the image "through" the rain?
    // Or we just overlay the rain on the image?
    // Let's overlay "digital" version of image.

    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let lum = dot(imgColor.rgb, vec3(0.299, 0.587, 0.114));

    // Rain color
    var rainColor = vec3(0.0, 1.0, 0.2) * bright;

    // Glitch: flicker based on random
    if (glitch > 0.0 && hash12(vec2(time, rowId)) < glitch * 0.1) {
        rainColor = vec3(1.0);
    }

    // Mask rain by image luminance?
    // So dark areas have less rain, or rain reveals image?
    rainColor *= (lum + 0.2);

    // Mix: Image is background, Rain is overlay
    // But let's make the image itself look digitized

    let digitized = vec3(0.0, lum, 0.0); // Green phosphor look

    // Final composite
    let finalColor = mix(imgColor.rgb, rainColor + digitized * 0.5, 0.8);

    textureStore(writeTexture, global_id.xy, vec4(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
