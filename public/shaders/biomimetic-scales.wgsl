// ═══════════════════════════════════════════════════════════════
//  Biomimetic Scales
//  Overlapping procedural scales that react to mouse presence.
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
  config: vec4<f32>,       // x=Time, y=ResX, z=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ScaleSize, y=Roughness, z=ReactionRadius, w=LiftStrength
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

    // Parameters
    let density = mix(10.0, 60.0, u.zoom_params.x); // Scale count
    let roughness = u.zoom_params.y;
    let reactionRadius = u.zoom_params.z * 0.5;
    let liftStrength = u.zoom_params.w;

    // Grid Setup (Staggered)
    // We scale UV.y by a factor to make scales somewhat circular in aspect
    let scaleUV = vec2<f32>(uv.x * aspect, uv.y);
    let gridSize = vec2<f32>(density, density);

    // We need to check neighbors to handle overlap.
    // The "current" cell is just a guess.
    let baseGrid = scaleUV * gridSize;
    let baseCell = floor(baseGrid);

    var finalColor = vec3<f32>(0.0);
    var hit = false;
    var maxLayer = -100.0;
    var finalNormal = vec3<f32>(0.0, 0.0, 1.0);
    var finalCenter = vec2<f32>(0.0);

    // Iterate 3x3 neighbors
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let cellIndex = baseCell + neighbor;

            // Stagger logic: Shift odd rows
            var cellCenterX = cellIndex.x + 0.5;
            if (abs(cellIndex.y % 2.0) >= 0.5) { // odd row
                 cellCenterX += 0.5;
            }

            let cellCenter = vec2<f32>(cellCenterX, cellIndex.y + 0.5) / gridSize;

            // Correct back to UV space for distance check
            // cellCenter is in "Aspect Corrected" UV space (0..aspect, 0..1) approx

            let distVec = scaleUV - (cellCenter * gridSize); // vector from center to pixel in grid units
            let dist = length(distVec);

            // Scale radius. Overlap required.
            let radius = 0.65;

            if (dist < radius) {
                // We are inside this scale.
                // Determine stacking order.
                // Assuming lower scales (higher Y index) are on top, OR standard roof tiling.
                // Let's say higher Y (bottom of screen) overlaps lower Y (top).
                let layerDepth = cellIndex.y;

                // If we found a scale on top of the previous one
                if (layerDepth > maxLayer) {
                    maxLayer = layerDepth;
                    hit = true;

                    // Calculate Normal
                    // Base curvature (dome)
                    let localN = normalize(vec3<f32>(distVec.x, distVec.y, sqrt(max(0.0, radius*radius - dist*dist))));

                    // Mouse Interaction
                    // Vector from Mouse to Scale Center
                    let mouseVec = (mouse - vec2<f32>(cellCenter.x / aspect, cellCenter.y));
                    let mouseDist = length(mouseVec * vec2<f32>(aspect, 1.0));

                    var interact = vec3<f32>(0.0);
                    if (mouseDist < reactionRadius) {
                        let force = smoothstep(reactionRadius, 0.0, mouseDist) * liftStrength;
                        // Tilt away from mouse
                        let pushDir = normalize(mouseVec);
                        interact = vec3<f32>(pushDir.x, pushDir.y, 0.0) * force;
                    }

                    finalNormal = normalize(localN - interact);
                    finalCenter = vec2<f32>(cellCenter.x / aspect, cellCenter.y); // Actual UV
                }
            }
        }
    }

    if (hit) {
        // Lighting
        let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
        let diff = max(dot(finalNormal, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, finalNormal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 20.0);

        // Sampling
        // Use normal to refract sample
        let sampleUV = uv - finalNormal.xy * 0.02 * (1.0 - roughness);
        var texColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

        // Apply roughness/lighting
        let lighting = (diff * 0.8 + 0.2) + spec * (1.0 - roughness);

        // Add subtle edge darkening for scale definition
        // (Implicit in the curvature normal, but we can boost it)

        finalColor = texColor * lighting;
    } else {
        // Gap between scales (shouldn't happen with sufficient overlap/radius)
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb * 0.2;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
}
