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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let speed = u.zoom_params.x; // Flow Speed
    let density = u.zoom_params.y; // Strip Density
    let turbulence = u.zoom_params.z; // Mouse turbulence
    let glow = u.zoom_params.w; // Digital Glow

    let time = u.config.x;

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let dist = distance(uv, mousePos);
    let interactRadius = 0.3;
    let interact = smoothstep(interactRadius, 0.0, dist) * turbulence;

    // Create Strips
    let numStrips = 20.0 + density * 100.0;
    let stripIdx = floor(uv.x * numStrips);

    // Random per strip
    let rand = fract(sin(stripIdx * 12.9898) * 43758.5453);

    // Vertical Flow
    let flowSpeed = (rand * 0.5 + 0.5) * speed * 0.5;
    // Mouse slows down or speeds up flow? Or deflects?
    // Let's make mouse create a "wake" that pushes pixels sideways

    let xOffset = interact * sin(uv.y * 10.0 + time * 5.0) * 0.05;

    var sampleUV = uv;
    sampleUV.x = sampleUV.x + xOffset;
    sampleUV.y = sampleUV.y - time * flowSpeed; // Flow down

    // Wrap Y
    sampleUV.y = fract(sampleUV.y);

    // Glitch effect on strips
    if (rand > 0.8) {
        sampleUV.y = sampleUV.y + sin(time * 10.0) * 0.01;
    }

    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Digital artifacts
    let blockY = floor(uv.y * 50.0);
    let noise = fract(sin(dot(vec2<f32>(stripIdx, blockY), vec2<f32>(12.9898, 78.233))) * 43758.5453);

    // Green tint / glow
    let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let digitalColor = vec3<f32>(0.0, lum * 1.5, lum * 0.2); // Green matrix style

    // Random "bright" characters
    let bright = step(0.98, noise * (sin(time * 2.0 + stripIdx)*0.5 + 0.5));

    let finalRGB = mix(color.rgb, digitalColor, glow);
    let outputColor = finalRGB + vec3<f32>(0.0, bright * glow, 0.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(outputColor, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
