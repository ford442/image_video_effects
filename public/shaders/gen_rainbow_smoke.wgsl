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

// Wild Rainbow Smoke
// Turbulent fluid simulation with psychedelic colors and explosive mouse interaction

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);

    // State: RG = velocity, B = smoke density, A = color phase
    let state = textureLoad(dataTextureC, px, 0);
    var vel = state.rg;
    var density = state.b;
    var phase = state.a;

    // Initialize random seeds on first frame
    if (length(vel) < 0.001 && density < 0.001) {
        vel = vec2<f32>(0.0);
        density = 0.0;
        phase = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    }

    // Multi-octave curl noise for turbulent flow
    var noise = vec2<f32>(0.0);
    var amp = 1.0;
    var freq = 1.0;

    for (var i = 0; i < 4; i++) {
        let angle = sin(uv.x * freq + time * 0.3) * cos(uv.y * freq - time * 0.2);
        noise += vec2<f32>(cos(angle), sin(angle)) * amp * freq;
        amp *= 0.5;
        freq *= 2.0;
    }
    noise *= 0.01;

    // Vorticity from neighboring velocities for swirling motion
    let n = textureLoad(dataTextureC, px + vec2<i32>(0, 1), 0).rg;
    let s = textureLoad(dataTextureC, px + vec2<i32>(0, -1), 0).rg;
    let e = textureLoad(dataTextureC, px + vec2<i32>(1, 0), 0).rg;
    let w = textureLoad(dataTextureC, px + vec2<i32>(-1, 0), 0).rg;

    let vorticity = (length(e) - length(w) + length(n) - length(s)) * 0.5;
    let curl = normalize(vec2<f32>(-vel.y, vel.x)) * vorticity * 0.15;

    // Update velocity: damping + turbulence + vorticity
    vel = vel * 0.96 + noise + curl;

    // Buoyancy - smoke rises
    vel.y += density * 0.001;

    // Mouse creates colorful explosions
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouse_dist = distance(uv, mouse);

    // FIX: Inverted smoothstep
    // Original: smoothstep(0.4, 0.0, mouse_dist)
    let mouse_impact = (1.0 - smoothstep(0.0, 0.4, mouse_dist)) * u.zoom_config.w;

    if (mouse_impact > 0.0) {
        density = max(density, mouse_impact);
        let blast_dir = normalize(uv - mouse);
        vel += blast_dir * mouse_impact * 2.0;
        phase = fract(time * 2.0 + mouse_dist * 8.0);
    }

    // Advect density and phase along velocity field
    let advect_uv = uv - vel * 0.6;
    let advected = textureSampleLevel(dataTextureC, u_sampler, advect_uv, 0.0);

    // Diffuse and fade
    density = mix(advected.b, density, 0.08) * 0.992;
    phase = mix(advected.a, phase, 0.05);

    // Wild rainbow palette
    let rainbow_phase = phase + time * 0.3 + density * 2.0;
    let rainbow = vec3<f32>(
        sin(rainbow_phase * 6.28318),
        sin(rainbow_phase * 6.28318 + 2.094),
        sin(rainbow_phase * 6.28318 + 4.188)
    ) * 0.5 + 0.5;

    // White-hot core for dense smoke
    let core = smoothstep(0.7, 1.0, density);
    let color = mix(rainbow, vec3<f32>(1.0, 1.0, 1.0), core);

    // Brightness from velocity and density
    let brightness = 1.0 + length(vel) * 3.0 + density;
    let final_color = color * brightness * density;

    // Dark, smoky background
    let background = vec3<f32>(0.02, 0.02, 0.05) * (1.0 - density * 0.3);

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color + background, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(vel, density, phase));
}
