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
  zoom_params: vec4<f32>,  // x=Sensitivity, y=Scatter, z=Aberration, w=Granularity
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
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currMouse = u.zoom_config.yz;
    let time = u.config.x;

    // Load previous mouse position from history texture (pixel 0,0)
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;

    // Store current mouse position for next frame
    if (global_id.x == 0u && global_id.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(currMouse, 0.0, 0.0));
    }

    // Parameters
    let sensitivity = u.zoom_params.x * 50.0; // 0.0 - 50.0
    let scatter = u.zoom_params.y * 0.1;      // 0.0 - 0.1
    let aberration = u.zoom_params.z * 0.05;  // 0.0 - 0.05
    let granularity = max(1.0, u.zoom_params.w * 50.0); // 1.0 - 50.0

    // Calculate Velocity
    let velocity = distance(currMouse, prevMouse);

    // Intensity is velocity * sensitivity
    let intensity = velocity * sensitivity;

    // Quantize UVs for "digital" scatter look
    let blockUV = floor(uv * resolution / granularity) * granularity / resolution;

    // Random offset based on block + time
    let rnd = hash12(blockUV + vec2<f32>(time * 10.0, time * 20.0));

    // Scatter displacement
    let displacement = (rnd - 0.5) * intensity * scatter;

    // Chromatic Aberration offsets
    let rgbSplit = intensity * aberration;

    // Sample with offsets
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(displacement - rgbSplit, displacement), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(displacement, displacement), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(displacement + rgbSplit, displacement), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Add white noise on top if moving fast
    let noise = hash12(uv * time);
    color = mix(color, vec3<f32>(noise), intensity * 0.2);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
