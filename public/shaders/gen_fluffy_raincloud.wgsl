@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Fluffy Raincloud with Rain
// Move mouse to position cloud, click for heavier rain

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);

    // State: RG = rain velocity, B = rain density, A = cloud density
    let state = textureLoad(dataTextureC, px, 0);
    var rain_vel = state.rg;
    var rain_density = state.b;
    var cloud_density = state.a;

    // Mouse position
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouse_down = u.zoom_config.w;

    // Cloud shape - fluffy with animated puffs
    let dist = distance(uv, mouse);
    let cloud_size = 0.15;

    // Main cloud body
    // Inverted smoothstep for safety
    let main_cloud = 1.0 - smoothstep(cloud_size * 0.7, cloud_size, dist);

    // Animated puffs for fluffiness
    let puff1_d = distance(uv, mouse + vec2<f32>(sin(time * 0.5) * 0.04, cos(time * 0.7) * 0.02));
    let puff1 = 1.0 - smoothstep(cloud_size * 0.3, cloud_size * 0.6, puff1_d);

    let puff2_d = distance(uv, mouse + vec2<f32>(cos(time * 0.3) * 0.03, sin(time * 0.4) * 0.03));
    let puff2 = 1.0 - smoothstep(cloud_size * 0.2, cloud_size * 0.5, puff2_d);

    let puff3_d = distance(uv, mouse + vec2<f32>(sin(time * 0.6) * 0.02, cos(time * 0.5) * 0.04));
    let puff3 = 1.0 - smoothstep(cloud_size * 0.4, cloud_size * 0.7, puff3_d);

    cloud_density = max(main_cloud, max(puff1, max(puff2, puff3))) * (0.5 + mouse_down * 0.5);

    // Rain emission from cloud
    if (dist < cloud_size * 0.7 && uv.y > mouse.y) {
        let emission = 0.01 + mouse_down * 0.02;
        rain_density = max(rain_density, emission);
        rain_vel.y = -0.5; // Fall speed
        rain_vel.x = (uv.x - mouse.x) * 0.1 + sin(time + uv.x * 8.0) * 0.003;
    }

    // Simulate rain
    if (rain_density > 0.001) {
        // Apply gravity and wind
        rain_vel.y -= 0.008;
        rain_vel.x += sin(time * 0.3 + uv.y * 4.0) * 0.002;

        // Advect from above
        let above = textureLoad(dataTextureC, px + vec2<i32>(0, -2), 0);
        rain_density = above.b * 0.999;

        // Bottom splash and fade
        if (uv.y > 0.92) {
            rain_density *= 0.3;
            rain_vel.y *= -0.1;
        }
    }

    // Visualize
    var color = vec3<f32>(0.0);

    // Sky gradient (light blue to white)
    color = mix(vec3<f32>(0.5, 0.7, 0.95), vec3<f32>(0.9, 0.95, 1.0), uv.y);

    // Rain (bright blue-white)
    let rain_intensity = rain_density * (1.0 + abs(rain_vel.y) * 2.0);
    let rain_color = vec3<f32>(0.8, 0.9, 1.0) * rain_intensity * 2.0;
    color = mix(color, rain_color, min(1.0, rain_intensity));

    // Cloud (white with gray shadow)
    let cloud_brightness = smoothstep(0.0, 0.4, cloud_density);
    let cloud_color = mix(vec3<f32>(0.4, 0.4, 0.45), vec3<f32>(1.0, 1.0, 1.0), cloud_brightness);
    color = mix(color, cloud_color, cloud_density);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(rain_vel, rain_density, cloud_density));
}
