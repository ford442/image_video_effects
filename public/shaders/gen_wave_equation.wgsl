// ═══════════════════════════════════════════════════════════════════
//  Wave Equation Simulation v2 - Audio-reactive fluid ripple solver
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware, temporal
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-06
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sample input from previous layer
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Domain-specific parameters with guards
    let intensity = clamp(u.zoom_params.x * (1.0 + bass * 0.2), 0.0, 1.0);
    let speedParam = clamp(u.zoom_params.y * (1.0 + mids * 0.15), 0.0, 1.0);
    let scaleParam = clamp(u.zoom_params.z * (1.0 + treble * 0.1), 0.0, 1.0);
    let detailParam = clamp(u.zoom_params.w, 0.0, 1.0);

    // Wave physics parameters
    let damping = mix(0.96, 0.999, detailParam);
    let wave_speed = max(mix(0.1, 1.0, speedParam), 0.001);
    let tension = max(mix(0.001, 0.05, scaleParam), 0.0001);

    // Read height (R) and velocity (G) from feedback texture
    let current = textureLoad(dataTextureC, px, 0).rg;
    var height = current.r;
    var velocity = current.g;

    // Initialize flat surface (branchless)
    let flatMask = f32(abs(height) < 0.001 && abs(velocity) < 0.001);
    height = mix(height, 0.0, flatMask);
    velocity = mix(velocity, 0.0, flatMask);

    // Sample neighbors for Laplacian with clamped coords
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let n = textureLoad(dataTextureC, clamp(px + vec2<i32>(0, 1), vec2<i32>(0), maxCoord), 0).r;
    let s = textureLoad(dataTextureC, clamp(px + vec2<i32>(0, -1), vec2<i32>(0), maxCoord), 0).r;
    let e = textureLoad(dataTextureC, clamp(px + vec2<i32>(1, 0), vec2<i32>(0), maxCoord), 0).r;
    let w = textureLoad(dataTextureC, clamp(px + vec2<i32>(-1, 0), vec2<i32>(0), maxCoord), 0).r;

    let laplacian = (n + s + e + w - 4.0 * height) * 0.25;

    // Mouse creates wave pulses
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouse_impact = (1.0 - smoothstep(0.0, 0.15, distance(uv, mouse)))
                       * u.zoom_config.w
                       * intensity
                       * 2.0;

    // Sine-Gordon / Klein-Gordon nonlinear term
    let nonlinear = clamp(detailParam, 0.0, 1.0);
    let massKG    = tension * 0.5;
    let massSG    = nonlinear * tension * sin(height * 3.14159);
    let nonlinTerm = mix(-massKG * height, -massSG, nonlinear);

    // Audio reactivity: bass amplifies wave energy and mouse impact
    let audioBoost = 1.0 + bass * detailParam * 2.0;

    // Wave equation integration with nonlinear term
    let acceleration = laplacian * wave_speed * wave_speed + nonlinTerm;
    velocity = velocity * damping + acceleration;
    height   = height + velocity + mouse_impact * audioBoost;

    // Colour by topological charge and energy density
    let kinetic   = velocity * velocity;
    let potential_e = 1.0 - cos(height);
    let energy    = clamp((kinetic + potential_e) * 0.5, 0.0, 1.0);

    let topoCharge = clamp(laplacian * 10.0, -1.0, 1.0);

    let kinkPhase = fract(height / (2.0 * 3.14159));
    let kinkColor = vec3<f32>(
        0.5 + 0.5 * sin(kinkPhase * 6.28318),
        0.5 + 0.5 * sin(kinkPhase * 6.28318 + 2.09440),
        0.5 + 0.5 * sin(kinkPhase * 6.28318 + 4.18879)
    );

    let wallGlow  = abs(topoCharge);
    let energyBright = energy * (1.0 + bass * 0.5);

    let t = height * 0.5 + 0.5;
    let waterColor = mix(
        vec3<f32>(0.03, 0.08, 0.25),
        vec3<f32>(0.85, 0.95, 1.0),
        smoothstep(0.0, 1.0, t)
    );
    let generatedColor = mix(waterColor, kinkColor, wallGlow * nonlinear)
                       + vec3<f32>(1.0, 0.8, 0.4) * energyBright * 0.4;

    // Alpha derived from wave intensity and energy (no hardcoded 1.0)
    let waveIntensity = clamp(abs(height) + abs(velocity) * 2.0 + energy, 0.0, 1.0);
    let opacity       = mix(0.5, 0.95, intensity);
    let finalRGB      = mix(inputColor.rgb, generatedColor, opacity);
    let finalAlpha    = clamp(waveIntensity * opacity + energy * 0.3 + inputColor.a * 0.2, 0.0, 1.0);

    let finalColor = vec4<f32>(acesToneMap(finalRGB * 1.1), finalAlpha);

    // Depth
    let depth = clamp(energy + inputDepth * 0.5, 0.0, 1.0);

    // Mandatory writes
    textureStore(writeTexture, px, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
