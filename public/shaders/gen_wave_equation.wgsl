// ═══════════════════════════════════════════════════════════════════
//  Wave Equation Simulation v2 - Audio-reactive fluid ripple solver
//  Category: generative
//  Features: upgraded-rgba, depth-aware, mouse-driven, audio-reactive, temporal
//  Complexity: Medium
//  Upgraded: 2026-05-10 (Phase A Upgrade Swarm)
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);

    // ═══ Audio reactivity from plasmaBuffer ═══
    let bass = plasmaBuffer[0].x;

    // ═══ Sample input from previous layer ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ═══ Domain-specific parameters with guards ═══
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speedParam = clamp(u.zoom_params.y, 0.0, 1.0);
    let scaleParam = clamp(u.zoom_params.z, 0.0, 1.0);
    let detailParam = clamp(u.zoom_params.w, 0.0, 1.0);

    // Wave physics parameters
    let damping = mix(0.96, 0.999, detailParam);
    let wave_speed = max(mix(0.1, 1.0, speedParam), 0.001);
    let tension = max(mix(0.001, 0.05, scaleParam), 0.0001);

    // Read height (R) and velocity (G) from feedback texture
    let current = textureLoad(dataTextureC, px, 0).rg;
    var height = current.r;
    var velocity = current.g;

    // Initialize flat surface
    if (abs(height) < 0.001 && abs(velocity) < 0.001) {
        height = 0.0;
        velocity = 0.0;
    }

    // Sample neighbors for Laplacian
    let n = textureLoad(dataTextureC, px + vec2<i32>(0, 1), 0).r;
    let s = textureLoad(dataTextureC, px + vec2<i32>(0, -1), 0).r;
    let e = textureLoad(dataTextureC, px + vec2<i32>(1, 0), 0).r;
    let w = textureLoad(dataTextureC, px + vec2<i32>(-1, 0), 0).r;

    let laplacian = (n + s + e + w - 4.0 * height) * 0.25;

    // Mouse creates wave pulses
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouse_impact = (1.0 - smoothstep(0.0, 0.15, distance(uv, mouse)))
                       * u.zoom_config.w
                       * intensity
                       * 2.0;

    // Audio reactivity: bass amplifies wave energy and mouse impact
    let audioBoost = 1.0 + bass * detailParam * 2.0;

    // Wave equation integration
    let acceleration = laplacian * wave_speed * wave_speed - height * tension;
    velocity = velocity * damping + acceleration;
    height = height + velocity + mouse_impact * audioBoost;

    // Visualize: deep water to foamy crests
    let t = height * 0.5 + 0.5;
    let waterColor = mix(
        vec3<f32>(0.05, 0.15, 0.3),
        vec3<f32>(0.9, 0.95, 1.0),
        smoothstep(0.0, 1.0, t)
    );
    let generatedColor = waterColor + vec3<f32>(0.3, 0.6, 1.0)
                         * smoothstep(0.05, 0.15, abs(velocity))
                         * 0.5
                         * (1.0 + bass * 0.5);

    // ═══ Meaningful alpha based on wave intensity ═══
    let waveIntensity = clamp(abs(height) + abs(velocity) * 2.0, 0.0, 1.0);
    let opacity = mix(0.5, 0.95, intensity);
    let finalColor = mix(inputColor.rgb, generatedColor, opacity);
    let finalAlpha = mix(inputColor.a, 1.0, waveIntensity * opacity);

    textureStore(writeTexture, px, vec4<f32>(finalColor, finalAlpha));
    textureStore(dataTextureA, px, vec4<f32>(height, velocity, 0.0, waveIntensity));
    textureStore(writeDepthTexture, px, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
