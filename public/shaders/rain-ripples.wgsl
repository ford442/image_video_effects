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
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;

    // Accumulate displacement from all active ripples
    var totalDisplacement = vec2<f32>(0.0);

    // Iterate through ripples provided by the engine
    // u.config.y contains the active ripple count if the engine sets it there?
    // Wait, AGENTS.md example says: let rippleCount = u32(u.config.y);
    // But config.y is often MouseClickCount.
    // Usually standard engines just iterate a fixed number or use a count.
    // The example says: "let rippleCount = u32(u.config.y);"
    // I will assume this is correct for this engine based on the example.

    let rippleCount = u32(u.config.y); // Assuming this is where count is stored or I should iterate all 50?
    // Actually, usually 0-value ripples are just inactive.
    // Let's iterate all 50 and check startTime.
    // But checking u.config.y is safer if the engine maintains it.
    // If it's 0, maybe the engine doesn't update it?
    // I'll stick to a max loop but break if startTime is 0 and it's not the first one?
    // No, slots might be reused. The safe bet is to iterate all 50 or use the count from config.y as per docs.

    // Let's rely on the count from config.y as per AGENTS.md
    // "let rippleCount = u32(u.config.y);"

    for (var i: u32 = 0u; i < 50u; i = i + 1u) {
        let ripple = u.ripples[i];
        let ripplePos = ripple.xy; // Normalized coordinates 0-1
        let startTime = ripple.z;

        // If start time is 0 (or very old), ignore?
        // Or if ripplePos is 0,0 (unless clicked there).
        // Let's check if it's active by seeing if time > startTime
        if (startTime <= 0.0) { continue; }

        let elapsed = currentTime - startTime;
        if (elapsed < 0.0 || elapsed > 2.0) { continue; } // Ripples last 2 seconds

        // Aspect ratio correction for circular ripples
        let aspect = resolution.x / resolution.y;
        let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
        let posCorrected = vec2<f32>(ripplePos.x * aspect, ripplePos.y);

        let dist = distance(uvCorrected, posCorrected);

        // Ripple logic
        // Wave expands: radius = speed * elapsed
        let speed = 0.5;
        let radius = speed * elapsed;

        // Distance from wave front
        let distFromWave = dist - radius;

        // Create a sine wave that decays with distance from center and time
        let waveWidth = 0.05;
        var amplitude = 0.0;

        if (abs(distFromWave) < waveWidth) {
            // Gaussian profile for the wave packet
            let profile = cos(distFromWave / waveWidth * 3.14159 * 2.0);

            // Decay over time and distance
            let decay = max(0.0, 1.0 - elapsed / 2.0); // Time decay
            let distDecay = max(0.0, 1.0 - dist * 2.0); // spatial decay

            amplitude = profile * decay * distDecay * 0.03;
        }

        // Direction of displacement (outward)
        let dir = normalize(uvCorrected - posCorrected);

        totalDisplacement = totalDisplacement - dir * amplitude; // Drag pixels *into* the wave or push out?
    }

    // Also add a subtle "rain" effect that is continuous if mouse is not moving?
    // Or just let the user click. The prompt says "responsive to ... mouse input".
    // Ripples are click based usually.
    // Let's add continuous rain if desired, but the instruction is "responsive shaders".
    // I'll stick to the ripples from clicks/movement if the engine generates them on move.
    // The engine `addRipplePoint` is usually called on mouse move or click.

    let displacedUV = uv + totalDisplacement;

    // Sample texture
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

    // Add specular highlight for water effect
    if (length(totalDisplacement) > 0.001) {
        color = color + vec4<f32>(0.1, 0.1, 0.15, 0.0); // lighten the ripples
    }

    textureStore(writeTexture, global_id.xy, color);
}
