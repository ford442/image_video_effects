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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Mouse Config
    let mouse = u.zoom_config.yz;
    let hasMouse = u.zoom_config.y >= 0.0;

    // Params
    let mass = u.zoom_params.x; // 0..1 Strength of distortion
    let horizonRadius = u.zoom_params.y * 0.2; // 0..0.2 Black hole size
    let diskIntensity = u.zoom_params.z; // 0..1 Glow at edge
    let aberration = u.zoom_params.w; // 0..1 Chromatic aberration

    // Default center if no mouse
    let center = select(vec2<f32>(0.5, 0.5), mouse, hasMouse);

    // Calculate vector from pixel to center
    let dVec = uv - center;
    // Correct distance for aspect ratio (physical distance on screen)
    let dVecAspect = vec2<f32>(dVec.x * aspect, dVec.y);
    let dist = length(dVecAspect);

    // Avoid division by zero
    let safeDist = max(dist, 0.001);

    // Lens Equation Approximation
    // Light is bent towards the mass.
    // The observer sees light coming from an angle further OUT than the source.
    // So we sample from a position closer IN to the mass.
    // Offset magnitude scales with 1/r (approx for weak field) or 1/r^2 closer?
    // Einstein radius logic implies offset ~ 1/r.

    // Effect Strength
    let strength = mass * 0.08; // Increased from 0.05

    // Calculate Offset Factor (scalar)
    // We apply this to dVec (UV space vector) to maintain circularity on screen.
    // Factor = Strength / PhysicalDistance^2 (for 1/r^2 falloff force)
    // Or Strength / PhysicalDistance (for 1/r deflection angle)
    // Let's use 1/r for smoother, wider reaching distortion.

    let factor = strength / (safeDist + 0.01); // Add epsilon to prevent explosion at 0

    // Apply distortion
    let offset = dVec * factor;

    // Chromatic Aberration: Different wavelengths bend differently
    let abr = 1.0 + aberration * 0.5;

    // Sample Coordinates
    // Red bends least? Blue most?
    // Usually blue (short wavelength) refracts more.
    // Gravity is achromatic (equivalence principle), but we are making ART.

    let uvR = uv - offset * 1.0;
    let uvG = uv - offset * (1.0 + aberration * 0.1);
    let uvB = uv - offset * (1.0 + aberration * 0.2);

    var color = vec4<f32>(0.0);

    // Event Horizon (Black Hole)
    if (dist < horizonRadius) {
        color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    } else {
        // Sample texture with clamping to avoid edge streaks
        let r = textureSampleLevel(readTexture, u_sampler, clamp(uvR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, clamp(uvG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, clamp(uvB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
        color = vec4<f32>(r, g, b, 1.0);

        // Accretion Disk / Photon Ring (Glow at the edge of horizon)
        // Only visible just outside the horizon
        let edgeWidth = 0.02 + horizonRadius * 0.1;
        if (dist > horizonRadius && dist < horizonRadius + edgeWidth) {
            let t = (dist - horizonRadius) / edgeWidth; // 0 at horizon, 1 at outer edge
            // Intensity decay
            let glow = exp(-t * 5.0) * diskIntensity * 3.0;

            // Fire colors (Orange/Red/Blue)
            let glowColor = vec3<f32>(1.0, 0.5, 0.1) * glow;

            // Additive blending
            color = vec4<f32>(color.rgb + glowColor, 1.0);
        }
    }

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
