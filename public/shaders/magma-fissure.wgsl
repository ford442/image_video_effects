// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Simple noise function
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Params
    let decay = u.zoom_params.x; // e.g., 0.98
    let fissureWidth = u.zoom_params.y * 0.1;
    let distortionStrength = u.zoom_params.z;
    let brushRadius = 0.02 + u.zoom_params.w * 0.05;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Update Heat Map
    // Read previous heat from dataTextureC
    let oldHeat = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Mouse Interaction
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let brush = smoothstep(brushRadius, 0.0, dist); // Sharp point

    // Heat accumulates and decays
    let newHeat = max(oldHeat * decay, brush);

    textureStore(dataTextureA, global_id.xy, vec4<f32>(newHeat, 0.0, 0.0, 1.0));

    // Rendering
    var finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    if (newHeat > 0.01) {
        // Heat distortion (haze)
        // Use noise offset by time and heat
        let n = noise(uv * 20.0 + vec2<f32>(0.0, time * 5.0));
        let offset = vec2<f32>(n - 0.5, n - 0.5) * newHeat * distortionStrength * 0.1;

        let distortedUV = uv + offset;
        let distortedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

        // Magma Gradient
        // Black -> Red -> Orange -> Yellow -> White
        var magmaColor = vec3<f32>(0.0);
        if (newHeat < 0.33) {
            magmaColor = mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), newHeat * 3.0);
        } else if (newHeat < 0.66) {
            magmaColor = mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 0.5, 0.0), (newHeat - 0.33) * 3.0);
        } else {
            magmaColor = mix(vec3<f32>(1.0, 0.5, 0.0), vec3<f32>(1.0, 1.0, 1.0), (newHeat - 0.66) * 3.0);
        }

        // Apply to image
        // We burn through the image.
        // If heat is high, show magma. If heat is low, show distorted image.
        // Actually, let's mix aggressively.

        // Let's make it look like a crack.
        // "Fissure Width" controls how wide the full-burn is.
        // But since `newHeat` is already a gradient from the brush (0 to 1), we can just step it.

        // Let's assume the brush creates a trail of heat 1.0.
        // As it decays, it goes 1.0 -> 0.0.

        // Core of the fissure (hottest)
        let coreThreshold = max(0.5, 1.0 - fissureWidth);
        let core = smoothstep(coreThreshold, 1.0, newHeat);

        // Edge of the fissure (glowing)
        let glow = smoothstep(0.0, 1.0, newHeat);

        // Composite
        // Start with distorted image
        var result = distortedColor.rgb;

        // Add glow
        result = mix(result, magmaColor, glow * 0.7); // Blend glow

        // Add core (pure magma)
        result = mix(result, magmaColor, core);

        finalColor = vec4<f32>(result, 1.0);
    }

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
