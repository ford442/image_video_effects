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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Divine Light (Volumetric Rays)
// Param1: Intensity
// Param2: Decay (Falloff)
// Param3: Density (Step size inv)
// Param4: Threshold (Luminance)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;

    // Default to center if mouse not active
    var center = mousePos;
    if (center.x < 0.0) {
        center = vec2<f32>(0.5, 0.5);
    }

    let intensity = u.zoom_params.x * 2.0; // 0 to 2
    let decay = 0.9 + u.zoom_params.y * 0.095; // 0.9 to 0.995
    let density = u.zoom_params.z; // Used to modulate step count or weight
    let threshold = u.zoom_params.w;

    // Read original color
    let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Radial Blur / Raymarch
    // Direction from pixel to light source (mouse)
    // Note: Usually god rays march *away* from light, but screen-space radial blur
    // marches *towards* the center to sample the occluders.
    // Actually, to simulate light emanating FROM the mouse, we should sample
    // along the line connecting the pixel to the mouse.
    // If we want the pixel to glow if it's on a ray from the mouse through a bright spot:
    // We sample towards the mouse.

    let dVec = center - uv;
    let dist = length(dVec);
    let steps = 32;
    let delta = dVec / f32(steps) * density; // Adjust step size

    var accumulatedColor = vec3<f32>(0.0);
    var currentUV = uv;
    var currentWeight = 1.0;

    for (var i = 0; i < steps; i++) {
        // Sample texture
        let sampleCol = textureSampleLevel(readTexture, u_sampler, currentUV, 0.0).rgb;

        // Luminance
        let luma = dot(sampleCol, vec3<f32>(0.299, 0.587, 0.114));

        // Threshold check
        if (luma > threshold) {
            accumulatedColor += sampleCol * currentWeight * intensity;
        }

        currentWeight *= decay;
        currentUV += delta;

        // Clamp UV? The sampler repeats, which might be cool or bad.
        // Let's rely on repeat or clamp.
    }

    // Average? Or additive?
    // God rays are usually additive.
    // Normalize by steps to prevent blowout?
    accumulatedColor /= f32(steps) * 0.1; // Magic scaler

    // Blend with original
    let finalColor = originalColor + vec4<f32>(accumulatedColor, 0.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
}
