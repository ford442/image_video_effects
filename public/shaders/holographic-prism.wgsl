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

fn rotate(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let facetDensity = mix(3.0, 12.0, u.zoom_params.x);
    let dispersionStr = mix(0.00, 0.05, u.zoom_params.y);
    let rotationSpeed = mix(-1.0, 1.0, u.zoom_params.z);
    let glitchInt = u.zoom_params.w;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let center = vec2<f32>(0.5, 0.5);
    // If mouse is at 0,0 (uninitialized often), use center.
    // Actually renderer sends -1 if invalid? Renderer sends mousePosition.x >= 0 check.
    var effectiveCenter = center;
    if (mouse.x >= 0.0) {
        effectiveCenter = mouse;
    }

    // Coordinate relative to center
    var p = uv - effectiveCenter;
    p.x = p.x * aspect;

    let dist = length(p);
    let angle = atan2(p.y, p.x);

    // Quantize angle to create shards/facets
    let pi = 3.14159;
    let shards = facetDensity;
    let quantizedAngle = floor(angle / (2.0 * pi) * shards) * (2.0 * pi) / shards;

    // Calculate rotation for this shard
    // Rotate based on distance and time
    let rot = quantizedAngle + time * rotationSpeed + dist * 2.0;

    // Rotate the original UV offset around the effective center
    // We want the shards to sample from rotated positions
    let rotatedOffset = rotate(p, rot * 0.2);

    // Un-aspect correct
    var finalOffset = rotatedOffset;
    finalOffset.x = finalOffset.x / aspect;

    let baseUV = effectiveCenter + finalOffset;

    // Chromatic Abberation / Dispersion
    // Sample R, G, B at slightly different zoom/positions
    let rOffset = vec2<f32>(dispersionStr * cos(rot), dispersionStr * sin(rot));
    let bOffset = vec2<f32>(-dispersionStr * cos(rot), -dispersionStr * sin(rot));

    let r = textureSampleLevel(readTexture, u_sampler, baseUV + rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, baseUV + bOffset, 0.0).b;

    // Holographic Glitch (scanlines + flicker)
    let scanline = sin(uv.y * 600.0 + time * 20.0) * 0.1 * glitchInt;
    let flicker = sin(time * 45.0) * 0.05 * glitchInt;

    var finalColor = vec3<f32>(r, g, b) + scanline + flicker;

    // Edge glow for facets
    let angleResidual = abs(angle - (quantizedAngle + pi/shards));
    // Simple edge highlight? Maybe too complex for now.

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
