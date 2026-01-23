// --- VENETIAN BLINDS ---
// Simulates venetian blinds covering the image.
// Mouse Y controls the openness of the blinds.

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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let slatCount = mix(10.0, 100.0, u.zoom_params.x); // Slider 1: Slat Density
    let baseOpenness = u.zoom_params.y;               // Slider 2: Base Openness
    let slatColorMix = u.zoom_params.z;               // Slider 3: Slat Color (Dark <-> Light)
    let phaseShift = u.zoom_params.w;                 // Slider 4: Phase

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    // Mouse Y influences openness. Center = neutral.
    // Maps mouse Y (0-1) to influence (-0.5 to 0.5)
    let mouseInfluence = (mouse.y - 0.5);

    // Effective Openness: 1.0 = Fully Open (See image), 0.0 = Fully Closed (See blinds)
    var openness = clamp(baseOpenness + mouseInfluence, 0.0, 1.0);

    // Calculation
    let y = uv.y * slatCount + phaseShift;
    let slatUV = fract(y); // 0.0 to 1.0 within the slat

    // Thickness of the slat when fully horizontal (seen edge-on)
    // We want a small sliver to remain even when fully open
    let minThickness = 0.05;

    // The visual height of the slat mask.
    // When Openness = 1.0, height = minThickness.
    // When Openness = 0.0, height = 1.0 (Full overlap).
    let visibleSlatSize = mix(1.0, minThickness, openness);

    let centeredSlatUV = abs(slatUV - 0.5); // 0 to 0.5

    var finalColor: vec4<f32>;

    // Check if we hit the slat
    if (centeredSlatUV < (visibleSlatSize * 0.5)) {
        // We hit the slat.
        // Calculate shading to make it look cylindrical or curved.
        // Normalize Y within the slat (-1 to 1)
        let normY = (slatUV - 0.5) / (visibleSlatSize * 0.5);

        // Simple lighting based on normal
        // Assume light comes from top-left or viewer
        let light = 0.5 + 0.5 * sqrt(max(0.0, 1.0 - normY*normY));

        // Base Slat Color (Off-White or Dark Grey based on param)
        let baseSlat = mix(vec3<f32>(0.1, 0.1, 0.1), vec3<f32>(0.9, 0.9, 0.9), slatColorMix);

        finalColor = vec4<f32>(baseSlat * light, 1.0);
    } else {
        // We hit the gap. Show the image.
        let baseImage = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

        // Add a drop shadow from the slat above
        // We are in the gap. 'centeredSlatUV' is > visibleSlatSize/2
        // Distance from the bottom edge of the slat above?
        // Actually, distance from top of gap.
        // Top of gap is at slatUV = 0.5 - visibleSlatSize/2 ?? No.

        // Let's simplify shadow. Distance from center.
        let dist = centeredSlatUV - (visibleSlatSize * 0.5);

        // Shadows appear at the top of the gap (bottom of the upper slat)
        // If slatUV < 0.5, we are in top half? No slatUV goes 0..1.
        // 0 is top, 1 is bottom.
        // Slat is centered at 0.5.
        // So gap is at 0..start and end..1.
        // Wait, centered logic above implies slat is in the MIDDLE of the cell.
        // So gap is at top (0.0) and bottom (1.0).

        // Let's re-verify centered logic.
        // if abs(slatUV - 0.5) < size/2 -> Slat is in middle.
        // So gap is at edges.

        // Shadow should be cast by the slat on the image.
        // Usually shadow falls downwards. So the slat casts shadow on the gap BELOW it.
        // The gap below the slat is the region (0.5 + size/2) to 1.0.

        var shadow = 1.0;
        if (slatUV > 0.5) {
             // We are below the slat center.
             let distFromSlatEdge = slatUV - (0.5 + visibleSlatSize * 0.5);
             shadow = smoothstep(0.0, 0.2, distFromSlatEdge);
             // mix shadow intensity
             shadow = mix(0.5, 1.0, shadow);
        }

        finalColor = vec4<f32>(baseImage.rgb * shadow, baseImage.a);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
