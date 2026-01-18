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

// Neon Ripple Split
// A reactive ripple effect that separates RGB channels and adds a neon glow.
//
// Param1: Ripple Speed (Default: 0.5)
// Param2: Color Split Amount (Default: 0.5)
// Param3: Glow Intensity (Default: 0.5)
// Param4: Frequency (Default: 0.5)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let speed = u.zoom_params.x * 4.0 + 1.0;
    let splitAmount = u.zoom_params.y * 0.05 + 0.002;
    let glowIntensity = u.zoom_params.z * 2.0;
    let freq = u.zoom_params.w * 40.0 + 10.0;

    var totalWave = 0.0;
    var totalSlope = 0.0;

    // 1. Mouse interaction (continuous ripple source)
    if (mousePos.x >= 0.0) {
        let aspect = resolution.x / resolution.y;
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        // Circular sine wave from mouse
        let phase = dist * freq - time * speed;
        let attenuation = 1.0 / (1.0 + dist * 10.0);

        let wave = sin(phase) * attenuation;
        totalWave += wave;
        totalSlope += cos(phase) * freq * attenuation;
    }

    // 2. Click Ripples
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rData = u.ripples[i];
        let rPos = rData.xy;
        let rStart = rData.z;
        let t = time - rStart;

        if (t > 0.0 && t < 3.0) {
            let aspect = resolution.x / resolution.y;
            let dVec = uv - rPos;
            let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

            // Expanding ring
            let currentRadius = t * (speed * 0.2);
            let ringDist = dist - currentRadius;
            let ringWidth = 0.1;

            if (abs(ringDist) < ringWidth) {
                let x = ringDist / ringWidth; // -1 to 1
                // Windowed sine
                let wave = sin(x * 3.14159 * 2.0) * (1.0 - abs(x));
                let amp = 1.0 - (t / 3.0); // Fade out

                totalWave += wave * amp * 2.0;
                totalSlope += cos(x * 3.14159 * 2.0) * amp * 2.0;
            }
        }
    }

    // Clamp wave for safety
    totalWave = clamp(totalWave, -2.0, 2.0);

    // RGB Split logic
    // We displace R, G, and B by different amounts based on the wave slope/height
    let offsetR = vec2<f32>(totalWave * splitAmount, 0.0);
    let offsetG = vec2<f32>(0.0, totalWave * splitAmount); // Orthogonal split
    let offsetB = vec2<f32>(-totalWave * splitAmount, -totalWave * splitAmount);

    let r = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Add Neon Glow
    // Boost color where the wave is high
    let glow = abs(totalWave) * glowIntensity;

    // Cyclical color shift for the glow based on time and distance
    let glowColor = vec3<f32>(
        sin(time * 2.0 + totalWave) * 0.5 + 0.5,
        sin(time * 2.0 + totalWave + 2.0) * 0.5 + 0.5,
        sin(time * 2.0 + totalWave + 4.0) * 0.5 + 0.5
    );

    color += glowColor * glow;

    // Store
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
