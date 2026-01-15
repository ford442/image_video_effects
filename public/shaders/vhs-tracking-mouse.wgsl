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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=IsMouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// VHS Tracking Mouse
// Param1: Bar Height
// Param2: Distortion Strength
// Param3: Noise Amount
// Param4: Color Shift

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = u.zoom_config.yz;
    if (mousePos.y < 0.0) { mousePos.y = 0.5; }

    let barHeight = u.zoom_params.x * 0.3 + 0.05;
    let strength = u.zoom_params.y * 0.1; // Horizontal smear
    let noiseAmt = u.zoom_params.z;
    let colorShift = u.zoom_params.w * 0.02;

    var finalUV = uv;
    var isInBar = false;

    // Calculate distance to bar (vertical)
    let distY = abs(uv.y - mousePos.y);

    if (distY < barHeight) {
        isInBar = true;
        // Fade out at edges of bar
        let intensity = smoothstep(barHeight, 0.0, distY); // 1.0 at center, 0 at edge

        // Horizontal Shear / Displacement
        // Use noise or sin wave
        let shift = sin(uv.y * 50.0 + time * 20.0) * strength * intensity;
        let noiseShift = (rand(vec2<f32>(uv.y, time)) - 0.5) * strength * 2.0 * intensity;

        finalUV.x += shift + noiseShift;
    }

    // Sample
    var color = vec3<f32>(0.0);

    if (isInBar) {
        // RGB Split inside bar
        color.r = textureSampleLevel(readTexture, u_sampler, finalUV + vec2<f32>(colorShift, 0.0), 0.0).r;
        color.g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
        color.b = textureSampleLevel(readTexture, u_sampler, finalUV - vec2<f32>(colorShift, 0.0), 0.0).b;

        // Static Noise
        if (noiseAmt > 0.0) {
            let n = rand(uv + vec2<f32>(time, time));
            color += (n - 0.5) * noiseAmt;
        }
    } else {
        // Normal outside
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    }

    // Scanline effect (global) - Optional faint one
    // let scanline = sin(uv.y * 800.0) * 0.05;
    // color -= scanline;

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Passthrough depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
