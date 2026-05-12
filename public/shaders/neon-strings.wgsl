// ═══════════════════════════════════════════════════════════════════
//  Neon Strings
//  Category: glow/light-effects
//  Features: pluckable-strings, mouse-velocity, harmonics, audio-reactive, persistent-vibration
//  Complexity: Medium
//  Phase B / Interactivist
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
  zoom_params: vec4<f32>,  // x=StringCount, y=Vibration, z=Intensity, w=Tension
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let stringCount = u.zoom_params.x * 20.0 + 5.0;
    let vibration   = u.zoom_params.y * 0.025;
    let intensity   = u.zoom_params.z * 3.0;
    let tension     = clamp(u.zoom_params.w, 0.05, 1.0);

    // Mouse pluck — proximity to a string sends a localized wave
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseString = floor(mouse.y * stringCount);
    let stringIndex = floor(uv.y * stringCount);
    let sameString = step(abs(stringIndex - mouseString), 0.5);
    // Distance along string from pluck point
    let pluckX = mouse.x;
    let dx = abs(uv.x - pluckX);
    // Pluck wave envelope: exp decay from pluck point, oscillation at fundamental
    let pluckEnv = exp(-dx * 5.0 / max(tension, 0.05)) * sameString * (mouseDown * 0.5 + 0.4);

    let stringY    = fract(uv.y * stringCount);
    // Fundamental + first harmonic + bass-driven vibrato per string (golden offset to avoid sync)
    let fundFreq = 8.0 / max(tension, 0.05);
    let harmonic = sin((time * fundFreq + stringIndex * PHI) * TAU * 0.05) * 0.5
                 + sin((time * fundFreq * 2.0 + stringIndex * PHI) * TAU * 0.05) * 0.25;
    let pluckOsc = sin((time * fundFreq * 1.5 + dx * 30.0) * TAU * 0.1) * pluckEnv;
    let vibrate  = (harmonic + pluckOsc) * vibration * (1.0 + bass * 0.6);

    // Distance to string centerline; bell-curve glow
    let stringDist = abs(stringY - 0.5 + vibrate);
    let stringGlow = exp(-stringDist * stringDist * 1500.0);

    // Per-string neon hue (golden-ratio palette walk)
    let hueSeed = stringIndex * (PHI - 1.0);
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(hueSeed * TAU + time * 0.4),
        0.5 + 0.5 * sin(hueSeed * TAU + time * 0.4 + 2.094),
        0.5 + 0.5 * sin(hueSeed * TAU + time * 0.4 + 4.188)
    );

    // Pluck halo — extra emission near pluck point
    let pluckHalo = pluckEnv * (1.0 + bass * 0.5);

    let emission = neonColor * (stringGlow * intensity + pluckHalo * 0.6);

    // Background image bleed-through (subtle) for context
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let composite = emission + bg * (1.0 - clamp(stringGlow + pluckHalo, 0.0, 1.0)) * 0.25;

    // Alpha: luma-keyed glow + pluck pulse (additive compositing weight)
    let lumaKey = luminanceKeyAlpha(emission, 0.05, 0.05);
    let alpha = clamp(stringGlow * 0.6 + pluckHalo * 0.5 + lumaKey * 0.2 + 0.05, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(composite, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
