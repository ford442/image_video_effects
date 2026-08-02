// ═══════════════════════════════════════════════════════════════
//  X-Ray Reveal
//  Interactive X-Ray lens that reveals an inverted, edge-enhanced internal structure
//  Upgraded: 2026-08-02 (Batch 30)
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

fn soft_ceiling(color: vec3<f32>) -> vec3<f32> {
    let positive = max(color, vec3<f32>(0.0));
    let peak = max(positive.x, max(positive.y, positive.z));
    return positive / (1.0 + max(peak - 1.0, 0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        mouse = rawMouse;
        mouseVelocity = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 10.0;
    mouseVelocity += ((rawMouse - mouse) * (omega * omega) - mouseVelocity * (2.0 * omega)) * dt;
    mouse += mouseVelocity * dt;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = mouse.x;
        extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x;
        extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }

    // Audio: bass widens the lens, mids boosts edges, treble raises contrast
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let lensRadius = u.zoom_params.x * 0.5 * (1.0 + bass * 0.3); // 0.0 to 0.5
    let edgeStrength = u.zoom_params.y * 5.0 * (1.0 + mids * 0.6);
    let contrast = u.zoom_params.z + 0.5 + treble * 0.3; // 0.5 to 1.5

    // Calculate Distance to Mouse (Lens)
    // Adjust for aspect ratio so lens is circular
    let uv_aspect = uv * vec2<f32>(aspect, 1.0);
    let mouse_aspect = mouse * vec2<f32>(aspect, 1.0);
    let dist = distance(uv_aspect, mouse_aspect);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Create X-Ray Effect (Invert + Tint + Edges)
    // 1. Invert
    var xray = max(vec3<f32>(1.0) - baseColor, vec3<f32>(0.0));

    // 2. Tint Blue/Cyan
    xray = xray * mix(vec3<f32>(0.2, 0.8, 1.0), vec3<f32>(0.45, 0.95, 1.0), depth * 0.35);

    // 3. Edge Detection (Sobel-ish)
    let offset = 1.0 / resolution;
    let left = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let right = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    let gx = length(right - left);
    let gy = length(down - up);
    let edges = sqrt(gx*gx + gy*gy);

    let edgeBin = (u32(clamp(uv.x, 0.0, 0.999) * 8.0) % 8u) + 1u;
    let edgeVoice = clamp(plasmaBuffer[edgeBin].x, 0.0, 1.0);
    xray += vec3<f32>(edges * edgeStrength * (0.8 + edgeVoice * 0.4));

    // Apply Contrast
    xray = pow(max(xray, vec3<f32>(0.0)), vec3<f32>(max(contrast, 0.05)));

    // Calculate Lens Mask
    // smoothstep(edge0, edge1, x) -> 0 if x < edge0, 1 if x > edge1
    // We want 1 inside, 0 outside.
    // dist < radius -> 1.
    // dist > radius -> 0.
    // smoothstep(radius, radius - blur, dist)
    // Ensure radius - blur < radius (which it is if blur > 0)

    let blur = max(u.zoom_params.w, 0.001);
    // Note: smoothstep requires edge0 < edge1 for 0->1 transition.
    // To get 1->0 transition (Inverted smoothstep): 1.0 - smoothstep(min, max, val)
    // Or smoothstep(max, min, val) is undefined/implementation dependent in some languages, but in GLSL/WGSL edge0 and edge1 can be anything.
    // Wait, WGSL spec says: "Results are undefined if edge0 == edge1."
    // It usually works like a linear interpolation clamped.
    // Let's use standard:

    let lensMask = 1.0 - smoothstep(lensRadius, lensRadius + blur, dist);

    var clickMask = 0.0;
    var clickRing = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let radius = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let waveRadius = age * 0.20;
            let ringPulse = exp(-abs(radius - waveRadius) * 75.0) * exp(-age * 1.4);
            clickRing = max(clickRing, ringPulse);
            clickMask = max(clickMask, (1.0 - smoothstep(0.0, max(waveRadius, 0.015), radius)) * exp(-age * 0.8));
        }
    }
    let mask = clamp(max(lensMask, clickMask * 0.8), 0.0, 1.0);

    // Composite
    // Inside lens: X-Ray
    // Outside lens: Base (maybe dimmed slightly to emphasize lens?)
    let dimmedBase = baseColor * 0.8;

    let finalColor = mix(dimmedBase, xray, mask);
    let d = abs(dist - lensRadius);
    let ringMag = (1.0 - smoothstep(0.0, 0.005, d)) + clickRing;
    let ringColor = vec3<f32>(0.5, 0.9, 1.0) * ringMag;

    // Add ring on top
    let result = soft_ceiling(finalColor + ringColor);

    // Reveal-mask alpha: lens interior and ring opaque, dimmed surround recedes
    let alpha = clamp(mask * 0.7 + ringMag + dot(result, vec3<f32>(0.299, 0.587, 0.114)) * 0.3 + 0.1, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(result, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(result, alpha));

    let reliefDepth = clamp(depth + mask * min(edges * 0.08, 0.12) + min(ringMag * 0.04, 0.08), 0.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(reliefDepth, 0.0, 0.0, 0.0));
}
