// ═══════════════════════════════════════════════════════════════
//  Aerogel Smoke
//  Simulates the ethereal "frozen smoke" look of aerogel
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pp);
        pp = rot * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let densityMult = u.zoom_params.x * 2.0;
    let scattering = u.zoom_params.y; // Blue tint intensity
    let glow = u.zoom_params.z;       // Light intensity
    let bgMix = u.zoom_params.w;      // 0 = Full Aerogel, 1 = Show Background

    // Base Image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Generate Volume Density (Smoke)
    // Moving slowly
    let p = uv * 3.0 + vec2<f32>(time * 0.05, time * 0.02);
    var density = fbm(p);

    // Add detail
    density += fbm(p * 4.0) * 0.5;
    density = smoothstep(0.2, 0.8, density) * densityMult;

    // Lighting (Point Light at Mouse)
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let lightFalloff = 1.0 / (1.0 + dist * dist * 10.0);

    // Volumetric Shadow (Approximation)
    // Darker where density is high, but lit by mouse
    let lightColor = vec3<f32>(0.9, 0.95, 1.0) * glow * lightFalloff;

    // Rayleigh Scattering tint (Aerogel Blue)
    let scatterColor = vec3<f32>(0.0, 0.5, 1.0) * scattering * lightFalloff * density;

    // Composite
    // Aerogel Appearance:
    // - High density = White/Foggy
    // - Edges/Thin = Blue Scattering
    // - Absorbs background light

    let aerogelColor = vec3<f32>(density) * lightColor + scatterColor;
    let opacity = clamp(density, 0.0, 1.0);

    // Mix with background
    // Aerogel obscures background
    var finalColor = mix(baseColor, aerogelColor, opacity);

    // Allow fading out the effect
    finalColor = mix(aerogelColor, finalColor, bgMix);

    // Tone map
    finalColor = pow(finalColor, vec3<f32>(1.0/1.2)); // Gamma correction

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
