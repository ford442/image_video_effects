// ═══════════════════════════════════════════════════════════════════
//  Quantum Prism
//  Category: image
//  Features: image, hex-prism, chromatic-aberration, mouse-driven, rotation
//  Complexity: Medium
//  Upgraded: 2026-06-28
//  By: Agent 1a - Alpha Channel Specialist
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// Function to rotate a 2D vector
fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    var s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / dims.y;
    var mouse = u.zoom_config.yz; // Mouse coordinates
    let time = u.config.x;
    let intensity = u.zoom_params.x;
    let motionSpeed = mix(0.15, 3.5, u.zoom_params.y);
    let gridScale = mix(5.0, 32.0, u.zoom_params.z);
    let facetDetail = mix(1.0, 9.0, u.zoom_params.w);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

    // Hex Grid Config
    let scale = gridScale;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    // Find Hex Center and Local Coords (Staggered Grid approach)
    // Normalized to r=1
    var s = vec2<f32>(1.7320508, 1.0);
    let u_scaled = uv_aspect * scale;

    let ga = (fract(u_scaled / s) - 0.5) * s;
    let ida = floor(u_scaled / s);

    let u_off = u_scaled - s * 0.5;
    let gb = (fract(u_off / s) - 0.5) * s;
    let idb = floor(u_off / s);

    let da = dot(ga, ga);
    let db = dot(gb, gb);

    var localUV = ga;
    var cellID = ida;
    var center = (ida + 0.5) * s;

    if (db < da) {
        localUV = gb;
        cellID = idb + 0.5;
        center = (idb + 0.5) * s + s * 0.5;
    }

    // Center in 0..1 space
    let centerUV = vec2<f32>(center.x / scale / aspect, center.y / scale);

    // Interaction
    let mouseVec = (mouse - centerUV) * vec2<f32>(aspect, 1.0);
    let dist = length(mouseVec);

    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.4) * 60.0);
    }
    let influence = smoothstep(0.4, 0.0, dist) * (0.35 + intensity * 0.65) + held * smoothstep(0.32, 0.0, dist) + clickFront * 0.35;

    // Effects
    // 1. Rotation based on mouse distance
    let rotAngle = influence * 3.14159 + time * motionSpeed * 0.18 + sin(dot(cellID, vec2<f32>(1.7, 2.3)) + time * motionSpeed) * 0.12;
    let rotatedLocal = rotate(localUV, rotAngle);

    // 2. Scale/Zoom inside cell
    let zoom = 1.0 - influence * 0.5;

    // Reconstruct UV
    let finalUV_scaled = center + rotatedLocal * zoom;
    let finalUV = vec2<f32>(finalUV_scaled.x / scale / aspect, finalUV_scaled.y / scale);

    // 3. Chromatic Aberration (Prism effect)
    // Split RGB based on rotation/influence
    let ca = (0.002 + intensity * 0.025) * (influence + audio.z * 0.25);

    // To make it look like a prism, we offset R, G, B in different directions relative to the cell center
    let rOffset = rotate(vec2<f32>(ca, 0.0), rotAngle);
    let bOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 2.094); // +120 deg
    let gOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 4.188); // +240 deg

    let r = textureSampleLevel(readTexture, u_sampler, finalUV + rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, finalUV + gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, finalUV + bOffset, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Edges (Simple distance based edge for hex approximation)
    let hexDistance = max(abs(localUV.x) * 0.866025 + abs(localUV.y) * 0.5, abs(localUV.y));
    let edge = smoothstep(0.42, 0.50, hexDistance);
    let bevel = pow(clamp(1.0 - hexDistance * 2.0, 0.0, 1.0), facetDetail * 0.35);
    let spectralBand = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + hexDistance * facetDetail * 8.0 - time * motionSpeed * 2.0);

    // Darken edges
    color = mix(color, vec3<f32>(0.0), edge * influence);

    // Highlight active cells
    color += spectralBand * (bevel * 0.18 + clickFront * 0.25 + audio * 0.12) * intensity;

    // Preserve the input alpha from the unshifted sample location
    let centerSample = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(color, centerSample.a));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(clamp(mix(depth, 0.18 + bevel * 0.72, 0.3 * intensity), 0.0, 1.0), 0.0, 0.0, 0.0));
}
