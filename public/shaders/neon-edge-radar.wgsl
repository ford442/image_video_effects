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
    let time = u.config.x;

    // Parameters
    let beamSpeed = u.zoom_params.x;     // 0.0 to 5.0
    let beamWidth = u.zoom_params.y;     // 0.0 to 1.0
    let edgeThreshold = u.zoom_params.z; // 0.0 to 1.0 (inverted, so 1.0 is low threshold)
    let neonIntensity = u.zoom_params.w; // 0.0 to 5.0

    // Mouse position (y, z in zoom_config)
    let mousePos = u.zoom_config.yz;
    // Aspect ratio correction for distance/angle
    let aspect = resolution.x / resolution.y;
    let aspectCorrection = vec2<f32>(aspect, 1.0);

    // --- Edge Detection (Sobel-like) ---
    let texel = 1.0 / resolution;
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;

    // Calculate gradients
    let gradX = length(r - l);
    let gradY = length(b - t);
    let edgeStrength = sqrt(gradX * gradX + gradY * gradY);

    // Apply threshold (params.z = 0.5 default)
    // We want high value to mean strict threshold
    let threshold = 0.05 + (1.0 - edgeThreshold) * 0.5;
    let isEdge = smoothstep(threshold, threshold + 0.1, edgeStrength);

    // --- Radar Beam Logic ---
    let diff = (uv - mousePos) * aspectCorrection;
    let dist = length(diff);
    let angle = atan2(diff.y, diff.x); // -PI to PI

    // Rotating beam angle
    // Normalize time so speed is consistent
    let beamAngle = (time * beamSpeed * 2.0) % 6.28318;
    // Map beamAngle to -PI to PI range if needed, or just map angle to 0..2PI
    // Let's use 0..2PI for both
    var currentAngle = angle;
    if (currentAngle < 0.0) { currentAngle = currentAngle + 6.28318; }

    var targetAngle = beamAngle;
    if (targetAngle < 0.0) { targetAngle = targetAngle + 6.28318; }

    // Calculate angular distance
    // Shortest distance on circle
    var angleDiff = abs(currentAngle - targetAngle);
    if (angleDiff > 3.14159) { angleDiff = 6.28318 - angleDiff; }

    // Beam intensity based on angle difference
    // Beam width parameter controls sharpness
    let width = 0.1 + beamWidth * 0.5;
    let beam = 1.0 - smoothstep(0.0, width, angleDiff);

    // Add a "scanline" pulse effect radiating out
    let ring = fract(dist * 5.0 - time * beamSpeed);
    let ringIntensity = smoothstep(0.8, 1.0, ring) * 0.5;

    // --- Compose Final Color ---
    let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    // Darken the background
    var finalColor = originalColor.rgb * 0.2;

    // Neon edge color (cyan/magenta mix based on angle)
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(angle + time),
        0.8,
        0.5 + 0.5 * cos(angle - time)
    );

    // Apply beam to edges
    let totalLight = beam + ringIntensity;
    if (isEdge > 0.1) {
        finalColor = mix(finalColor, neonColor * neonIntensity, isEdge * totalLight);
    }

    // Also light up the beam itself slightly
    finalColor = finalColor + neonColor * beam * 0.1;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // No history or depth update needed for this effect, but good practice to clear depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
