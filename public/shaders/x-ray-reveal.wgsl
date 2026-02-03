// ═══════════════════════════════════════════════════════════════
//  X-Ray Reveal
//  Interactive X-Ray lens that reveals an inverted, edge-enhanced internal structure
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Parameters
    let lensRadius = u.zoom_params.x * 0.5; // 0.0 to 0.5
    let edgeStrength = u.zoom_params.y * 5.0;
    let contrast = u.zoom_params.z + 0.5; // 0.5 to 1.5

    // Calculate Distance to Mouse (Lens)
    // Adjust for aspect ratio so lens is circular
    let uv_aspect = uv * vec2<f32>(aspect, 1.0);
    let mouse_aspect = mouse * vec2<f32>(aspect, 1.0);
    let dist = distance(uv_aspect, mouse_aspect);

    // Read Base Texture
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Create X-Ray Effect (Invert + Tint + Edges)
    // 1. Invert
    var xray = 1.0 - baseColor;

    // 2. Tint Blue/Cyan
    xray = xray * vec3<f32>(0.2, 0.8, 1.0);

    // 3. Edge Detection (Sobel-ish)
    let offset = 1.0 / resolution;
    let left = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-offset.x, 0.0), 0.0).rgb;
    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -offset.y), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).rgb;

    let gx = length(right - left);
    let gy = length(down - up);
    let edges = sqrt(gx*gx + gy*gy);

    // Add glowing edges
    xray += vec3<f32>(edges * edgeStrength);

    // Apply Contrast
    xray = pow(xray, vec3<f32>(contrast));

    // Calculate Lens Mask
    // smoothstep(edge0, edge1, x) -> 0 if x < edge0, 1 if x > edge1
    // We want 1 inside, 0 outside.
    // dist < radius -> 1.
    // dist > radius -> 0.
    // smoothstep(radius, radius - blur, dist)
    // Ensure radius - blur < radius (which it is if blur > 0)

    let blur = 0.05;
    // Note: smoothstep requires edge0 < edge1 for 0->1 transition.
    // To get 1->0 transition (Inverted smoothstep): 1.0 - smoothstep(min, max, val)
    // Or smoothstep(max, min, val) is undefined/implementation dependent in some languages, but in GLSL/WGSL edge0 and edge1 can be anything.
    // Wait, WGSL spec says: "Results are undefined if edge0 == edge1."
    // It usually works like a linear interpolation clamped.
    // Let's use standard:

    let mask = 1.0 - smoothstep(lensRadius, lensRadius + blur, dist);

    // Composite
    // Inside lens: X-Ray
    // Outside lens: Base (maybe dimmed slightly to emphasize lens?)
    let dimmedBase = baseColor * 0.8;

    let finalColor = mix(dimmedBase, xray, mask);

    // Draw lens ring
    let ring = smoothstep(lensRadius + blur, lensRadius, dist) - smoothstep(lensRadius, lensRadius - 0.005, dist);
    // Actually simpler:
    let d = abs(dist - lensRadius);
    let ringColor = vec3<f32>(0.5, 0.9, 1.0) * smoothstep(0.005, 0.0, d);

    // Add ring on top
    let result = finalColor + ringColor;

    textureStore(writeTexture, global_id.xy, vec4<f32>(result, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
