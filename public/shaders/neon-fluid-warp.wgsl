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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Helper to get luminance
fn get_luma(color: vec3<f32>) -> f32 {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let warpStrength = u.zoom_params.x * 0.2; // Scaling down for sane defaults
    let radius = u.zoom_params.y * 0.5;
    let glowIntensity = u.zoom_params.z;
    let liquidity = u.zoom_params.w;

    // Mouse
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Vector to mouse
    var distVec = (uv - mousePos);
    distVec.x *= aspect;
    let dist = length(distVec);

    // Warp calculation
    // "Liquidity" adds some sine wave ripples to the direction
    let angle = atan2(distVec.y, distVec.x);
    let ripple = sin(dist * 20.0 - time * 5.0) * liquidity * 0.05;

    // Repulsion force
    // smoothstep creates a soft boundary. The closer to mouse, the stronger the push.
    let force = smoothstep(radius, 0.0, dist);

    // Calculate displacement
    // We displace the UV lookup. To simulate "pushing away", we look "towards" the mouse.
    // wait, if I am at pixel P, and I want to see what was pushed here from P_orig,
    // and P_orig was closer to the mouse, it means the content moved OUTWARD.
    // So at P, I should look INWARD (towards mouse) to find the content that arrived here.
    let displaceDir = normalize(distVec); // Pointing away from mouse
    // If I look away from mouse, I see content that is further out -> shrinking effect.
    // If I look towards mouse, I see content that is closer in -> expanding/repelling effect.

    let offset = -displaceDir * force * warpStrength * (1.0 + ripple);

    let sampleUV = uv + offset;

    // Sample the texture
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgba;

    // Edge/Stress detection for Neon Glow
    // If the displacement is high, or changing rapidly, we add glow.
    // Let's use the magnitude of the force derivative or just the force itself at the edge.
    // A ring at the edge of the radius:
    let edge = smoothstep(0.0, 0.1, abs(dist - radius * 0.8)); // 1.0 away from edge, 0.0 at edge
    // Actually simpler:
    let glowFactor = force * (1.0 - force) * 4.0; // Peak at force=0.5

    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(time + uv.x * 10.0),
        0.5 + 0.5 * sin(time + uv.y * 10.0 + 2.0),
        0.5 + 0.5 * sin(time + 4.0)
    );

    // Add glow based on intensity and image luminance (so it looks like the image is glowing)
    let luma = get_luma(color.rgb);
    color = vec4<f32>(mix(color.rgb, neonColor, glowFactor * glowIntensity * luma), color.a);

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
