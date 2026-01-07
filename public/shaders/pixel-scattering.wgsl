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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ScatterRadius, y=ScatterStrength, z=ParticleSize, w=Randomness
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let radius = u.zoom_params.x * 0.5 + 0.05;
    let strength = u.zoom_params.y * 0.2; // Max displacement
    let randomness = u.zoom_params.w;

    // Mouse
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let to_mouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(to_mouse);

    var offset = vec2<f32>(0.0);

    if (dist < radius) {
        // Calculate interaction
        // 0 at radius, 1 at center
        let interact = pow(1.0 - dist / radius, 2.0);

        // Direction away from mouse
        var dir = normalize(to_mouse);
        if (dist < 0.001) { dir = vec2<f32>(1.0, 0.0); }

        // Add randomness to direction
        let noise = hash12(uv * 50.0 + u.config.x) - 0.5;
        let angle_jitter = noise * randomness * 3.0; // Radians jitter

        let c = cos(angle_jitter);
        let s = sin(angle_jitter);
        let rot_dir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);

        // Push pixels: we want to sample from closer to the mouse (implosion?)
        // If we want pixels to look like they are flying AWAY, we need to sample from "where they came from".
        // If pixels at P move to P', then P' samples from P.
        // P' is further from mouse. So P is closer to mouse.
        // So at current UV (P'), we sample from (UV - offset_towards_mouse).
        // offset should be positive towards mouse.

        offset = -rot_dir * interact * strength;
    }

    // Standard sampling
    let color = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);

    textureStore(writeTexture, global_id.xy, color);
}
