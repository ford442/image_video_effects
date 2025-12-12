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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2 (w=isMouseDown)
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

    // Parameters
    let facetScale = u.zoom_params.x; // 0.1 to 2.0
    let dispersion = u.zoom_params.y; // 0.0 to 0.1
    let strength = u.zoom_params.z;   // 0.0 to 1.0
    let smoothness = u.zoom_params.w; // 0.0 to 1.0

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Calculate distance to mouse for lens effect
    // Default to center if mouse not active? No, Renderer injects valid mouse or center (farthestPoint)

    let toCenter = uv - mousePos;
    let dist = length(toCenter);

    // Lens Radius
    let lensRadius = 0.4;
    let falloff = smoothstep(lensRadius, 0.0, dist);

    // Facet Logic
    // Create angular stepping for facets
    let angle = atan2(toCenter.y, toCenter.x);
    let numFacets = floor(10.0 * facetScale + 3.0);
    let steppedAngle = floor(angle / (6.28318 / numFacets) + 0.5) * (6.28318 / numFacets);

    // Mix angular stepping based on smoothness
    let finalAngle = mix(steppedAngle, angle, smoothness);

    // Calculate displacement vector
    // We want to pull pixels from the "facet" direction
    let displacementDir = vec2<f32>(cos(finalAngle), sin(finalAngle));

    // Refraction strength falls off with distance from center
    // And acts inwards or outwards? Let's say it magnifies (pulls from center)
    let displaceAmount = displacementDir * dist * strength * falloff;

    // Chromatic Aberration (Dispersion)
    let rOffset = displaceAmount * (1.0 + dispersion * 10.0);
    let gOffset = displaceAmount;
    let bOffset = displaceAmount * (1.0 - dispersion * 10.0);

    let r = textureSampleLevel(readTexture, u_sampler, uv - rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv - gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - bOffset, 0.0).b;

    // Add a specular highlight on the edges of facets?
    // Derivative of angle?
    let angleDiff = abs(angle - steppedAngle);
    let highlight = (1.0 - smoothstep(0.0, 0.1, angleDiff)) * (1.0 - smoothness) * falloff * 0.5;

    let finalColor = vec4<f32>(r + highlight, g + highlight, b + highlight, 1.0);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Update Depth (Pass-through)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
