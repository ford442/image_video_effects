@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;



@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let rate = 0.5;
    let time = u.config.x * rate;
    let strength = 0.02;
    let frequency = 15.0;
    
    // Mouse position as attractor center
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let to_mouse = mouse_pos - uv;
    let dist_to_mouse = length(to_mouse);
    let mouse_influence = exp(-dist_to_mouse * 5.0) * 0.015;
    
    var d1 = sin(uv.x * frequency + time) * strength;
    var d2 = cos(uv.y * frequency * 0.7 + time) * strength;
    
    // Add mouse attractor influence
    d1 += to_mouse.x * mouse_influence;
    d2 += to_mouse.y * mouse_influence;
    
    // Add ripple-based eddies
    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let ripple_pos = ripple.xy;
            let ripple_age = time - ripple.z;
            if (ripple_age > 0.0 && ripple_age < 4.0) {
                let to_ripple = uv - ripple_pos;
                let ripple_dist = length(to_ripple);
                let ripple_strength = sin(ripple_dist * 20.0 - ripple_age * 5.0) * exp(-ripple_age * 0.5) * 0.01;
                d1 += to_ripple.y * ripple_strength;
                d2 -= to_ripple.x * ripple_strength;
            }
        }
    }
    
    var displacedUV = uv + vec2<f32>(d1, d2);
    
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

    // This is the unique logic for this shader that makes it different.
    if (((color.r + color.g + color.b) / 3.0) > 0.75) {
        let bright_time = u.config.x * 0.65;
        let bd1 = sin(uv.x * frequency + bright_time) * strength;
        let bd2 = cos(uv.y * frequency * 0.7 + bright_time) * strength;
        let brightDisplacedUV = uv + vec2<f32>(bd1, bd2);
        color = mix(color, textureSampleLevel(readTexture, u_sampler, brightDisplacedUV, 0.0), 0.25);
    }

    if (((color.r + color.g + color.b) / 3.0) < 0.25) {
        let dark_time = u.config.x * 0.45;
        let dd1 = sin(uv.x * frequency + dark_time) * strength;
        let dd2 = cos(uv.y * frequency * 0.7 + dark_time) * strength;
        let darkDisplacedUV = uv + vec2<f32>(dd1, dd2);
        color = mix(color, textureSampleLevel(readTexture, u_sampler, darkDisplacedUV, 0.0), 0.75);
    }

    textureStore(writeTexture, global_id.xy, color);
}
