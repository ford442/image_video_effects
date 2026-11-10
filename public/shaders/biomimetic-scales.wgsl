// ═══════════════════════════════════════════════════════════════════
//  Biomimetic Scales
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-10
//  Ideas: circuli growth ridges on each scale; imbricate contact shadow from the scale above
//  A packing: raw lighting terms (diff, spec, 1, alpha); display RGB in writeTexture only
//  Chunks From: biomimetic-scales
//  Created: 2026-05-30
//  By: Copilot CLI
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=ScaleSize, y=Roughness, z=ReactionRadius, w=LiftStrength

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Parameters
    let density = mix(10.0, 60.0, u.zoom_params.x) * (1.0 + bass * 0.12); // Scale count
    let roughness = u.zoom_params.y;
    let reactionRadius = u.zoom_params.z * 0.5;
    let liftStrength = u.zoom_params.w * (1.0 + mids * 0.3);

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

            // RESCUE: HEAD subtracted a grid-unit centre from a UV-unit position (`scaleUV`),
            // so only ~0.3% of pixels ever landed inside a scale. Both sides are in grid units now.
            let distVec = baseGrid - (cellCenter * gridSize); // vector from center to pixel in grid units
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
                    // ── Idea 1: circuli growth ridges ───────────────────────────
                    // Fish scales carry concentric growth rings. They tilt the dome
                    // normal along the radial direction; the ridge amplitude rides
                    // Roughness (rougher scales read more ridged) and fades toward
                    // the smooth centre so the nucleus stays clean.
                    let dirR = distVec / max(dist, 0.0001);
                    let ridge = sin(dist * 40.0) * smoothstep(0.08, 0.24, dist);
                    let ridgeAmp = 0.05 + roughness * 0.12;
                    let localN = normalize(vec3<f32>(distVec + dirR * ridge * ridgeAmp, sqrt(max(0.0, radius*radius - dist*dist))));

                    // Mouse Interaction
                    // Vector from Mouse to Scale Center
                    let mouseVec = (mouse - vec2<f32>(cellCenter.x / aspect, cellCenter.y));
                    let mouseDist = length(mouseVec * vec2<f32>(aspect, 1.0));

                    var interact = vec3<f32>(0.0);
                    if (mouseDist < reactionRadius) {
                        let force = smoothstep(reactionRadius, 0.0, mouseDist) * liftStrength;
                        // Tilt away from mouse
                        let pushDir = mouseVec / max(length(mouseVec), 0.0001);
                        interact = vec3<f32>(pushDir.x, pushDir.y, 0.0) * force;
                    }

                    finalNormal = normalize(localN - interact);
                    finalCenter = vec2<f32>(cellCenter.x / aspect, cellCenter.y); // Actual UV
                }
            }
        }
    }

    if (hit) {
        // ── Idea 2: imbricate contact shadow ────────────────────────────
        // Scales on rows above the visible one (higher index = drawn on top) do not
        // contain this pixel, but each casts a soft shadow just outside its rim,
        // displaced away from the light (light comes from the upper left).
        var contact = 0.0;
        for (var sy = -1; sy <= 1; sy++) {
            for (var sx = -1; sx <= 1; sx++) {
                let ci = baseCell + vec2<f32>(f32(sx), f32(sy));
                if (ci.y > maxLayer) {
                    var ccx = ci.x + 0.5;
                    if (abs(ci.y % 2.0) >= 0.5) { ccx += 0.5; }
                    let casterDist = length(baseGrid - (vec2<f32>(ccx, ci.y + 0.5) + vec2<f32>(0.10, 0.10)));
                    contact = max(contact, smoothstep(0.65 + 0.24, 0.65, casterDist));
                }
            }
        }

        // Lighting
        let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
        let diff = max(dot(finalNormal, lightDir), 0.0) * (1.0 - 0.55 * contact);
        let spec = pow(max(dot(reflect(-lightDir, finalNormal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 20.0) * (1.0 - contact);

        // Sampling
        // Use normal to refract sample
        let sampleUV = clamp(uv - finalNormal.xy * 0.02 * (1.0 - roughness), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
        var texColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

        // Apply roughness/lighting
        let lighting = (diff * 0.8 + 0.2) + spec * (1.0 - roughness + treble * 0.1);

        // Add subtle edge darkening for scale definition
        // (Implicit in the curvature normal, but we can boost it)

        finalColor = acesToneMap(max(texColor * lighting, vec3<f32>(0.0)));
        let alpha = clamp(0.22 + diff * 0.25 + spec * 0.2 + bass * 0.08, 0.1, 0.92);
        let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + spec * 0.05, 0.0, 1.0);
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        textureStore(dataTextureA, global_id.xy, vec4<f32>(diff, spec, 1.0, alpha));
    } else {
        // Gap between scales (shouldn't happen with sufficient overlap/radius)
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb * 0.2;
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 0.14));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        textureStore(dataTextureA, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.14));
    }
}
