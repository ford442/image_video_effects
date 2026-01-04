// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>;       // x=time, y=cycleSpeed, z=segments, w=rotationSpeed
  zoom_config: vec4<f32>;  // x=unused, y=centerX, z=centerY, w=unused
  zoom_params: vec4<f32>;  // x=blendSmoothness, y=maxRotationPercent, z=unused, w=unused
  ripples: array<vec4<f32>, 50>;
};

// Notes:
// - Maps `center` to `u.zoom_config.yz`
// - `params.y` (maxRotationPercent) maps to `u.zoom_params.y`
// - `params.x` (blendSmoothness) maps to `u.zoom_params.x`

fn ping_pong(t: f32) -> f32 {
    return 1.0 - abs(fract(t * 0.5) * 2.0 - 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let cycleSpeed = u.zoom_params.x;      // From JSON param[0]
    let segments = max(1.0, u.zoom_params.y); // From JSON param[1]
    let rotationSpeed = u.zoom_params.z;   // From JSON param[2]
    let maxRotationPercent = clamp(u.zoom_params.w, 0.0, 1.0); // From JSON param[3]
    let blendSmoothness = 2.0; // Fixed value

    // Mouse-driven center and ripple distortion
    let mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);
    let center = mousePos; // Make center follow mouse

    // Add ripple distortion
    let rippleCount = u32(u.config.y);
    var mouseDisplacement = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let timeSinceClick = time - ripple.z;
        if (timeSinceClick > 0.0 && timeSinceClick < 2.0) {
            let direction = uv - ripple.xy;
            let dist = length(direction);
            if (dist > 0.001) {
                let wave = sin(dist * 30.0 - timeSinceClick * 5.0);
                let falloff = exp(-timeSinceClick * 2.0) / (dist * 10.0 + 1.0);
                mouseDisplacement += (direction / dist) * wave * falloff * 0.05;
            }
        }
    }

    // Strength cycles 0->1->0 (!wrap)
    let strength = ping_pong(time * cycleSpeed);

    // Segment angle and limited rotation
    let segmentAngle = 6.28318530718 / segments;
    let maxRotation = segmentAngle * maxRotationPercent;
    let rotation = ping_pong(time * rotationSpeed) * maxRotation;

    // Convert to polar coords from center
    let delta = (uv + mouseDisplacement) - center;
    let angle = atan2(delta.y, delta.x);
    let radius = length(delta);

    // Normalize angle to segment space
    let normalizedAngle = angle / segmentAngle;
    // Mirror within segment
    let mirroredAngle = abs(fract(normalizedAngle) * 2.0 - 1.0);
    // Apply limited rotation
    let kaleidoAngle = (mirroredAngle * segmentAngle) + rotation;
    // Convert back to Cartesian
    let kaleidoUV = center + vec2<f32>(cos(kaleidoAngle), sin(kaleidoAngle)) * radius;

    // Smooth blending (use smoothstep with blendSmoothness)
    let blend = smoothstep(0.0, 1.0, strength);
    // Optionally apply a softness factor using blendSmoothness
    let softBlend = smoothstep(0.0, 1.0, pow(blend, 1.0 / blendSmoothness));
    let finalUV = mix(uv, kaleidoUV, softBlend);

    // Sample color and depth
    let color = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;

    textureStore(writeTexture, vec2<u32>(global_id.xy), color);
    // Write depth as-is so downstream shaders can be depth-aware
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}