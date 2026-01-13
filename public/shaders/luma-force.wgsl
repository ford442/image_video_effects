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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
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
    let mouse = u.zoom_config.yz;

    // Params
    let strength = u.zoom_params.x; // Force Strength
    let radius = u.zoom_params.y;   // Radius
    let mode = u.zoom_params.z;     // 0 = Repel, 1 = Attract
    let lumaWeight = u.zoom_params.w; // How much luma affects the force

    // Correct coords for distance
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = distance(uvCorrected, mouseCorrected);

    // Calculate force falloff
    let falloff = smoothstep(radius, 0.0, dist);

    // Direction from pixel to mouse (for attraction)
    // We want the inverse for sampling: to simulate attraction, we sample from FURTHER away in that direction?
    // If we want pixels to move TOWARDS mouse, the sample coord must be OFFSET towards the OPPOSITE direction.
    // e.g. To see pixel P at P', we sample P.
    // If P moves to P_new, then at P_new we sample P.

    // Let's think in terms of "where does this pixel look for its color".
    // If we want "Repel" (pixels pushed away from mouse), then at pixel P (near mouse), we should see content that WAS at P_closer.
    // So we sample closer to the mouse.

    let dir = normalize(uv - mouse); // Pointing away from mouse

    // Repel: Sample closer to mouse. Offset = -dir * force
    // Attract: Sample further from mouse. Offset = dir * force

    var forceDir = -dir; // Default to repel logic (sample closer)
    if (mode > 0.5) {
        forceDir = dir; // Attract logic (sample further)
    }

    // Read luma of current position to weigh the force
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let effectiveStrength = strength * (1.0 - lumaWeight * (1.0 - luma)); // Lighter pixels might be heavier?
    // If lumaWeight is high, dark pixels have effectiveStrength near strength*(1-1) = 0?
    // Let's make it: lumaWeight blends between constant force and luma-dependent force.
    // weight = mix(1.0, luma, lumaWeight) ?
    // Let's just say: offset amount depends on luma.

    let offsetAmt = falloff * effectiveStrength * 0.2; // 0.2 scale
    let offset = forceDir * offsetAmt;

    let sampleUV = uv + offset;

    // Boundary check handled by sampler (clamp or repeat usually)
    let finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor.rgb, 1.0));
}
