// ═══════════════════════════════════════════════════════════════════
//  Refractive Bubbles
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-04, 2026-11-20
//  Ideas: ball-lens core; thin-film wall; contact walls; Snell rim (§12.2F); Airy disc on the specular (§12.2F)
//  A packing: ACES display RGBA (alpha = transmission inside, edge proximity outside)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn airyDisc(x: f32) -> f32 {
  let xs = max(abs(x), 1e-4);
  let j1 = xs * (0.5 - xs * xs * (0.0625 - xs * xs * (0.0026042 - xs * xs * 0.0000543)));
  let v = 2.0 * j1 / xs;
  return v * v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mouse = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Bass pulses bubble size and refraction strength
    let size = (u.zoom_params.x * 0.15 + 0.01) * (1.0 + bass * 0.3);
    let refrStrength = u.zoom_params.y * 0.2 * (1.0 + mids * 0.4);
    let count = i32(u.zoom_params.z * 15.0) + 1;
    let wobble = u.zoom_params.w;
    let glassDensity = 0.8 + u.zoom_params.w * 1.5;

    let aspect = resolution.x / resolution.y;
    var finalUV = uv;
    var inBubble = false;
    var bubbleNormal = vec3<f32>(0.0, 0.0, 1.0);
    var bubbleDepth = 0.0;
    var bubbleThickness = 0.0;
    var minBubbleDist = 9.9;
    // Every bubble this pixel lies inside, for contact walls (aspect space).
    var hits = 0;
    var hitA = vec2<f32>(0.0);
    var hitB = vec2<f32>(0.0);

    for (var i = 0; i < count; i++) {
        let fi = f32(i);
        // Orbit around mouse
        let angle = time * (wobble + 0.1) * (fi * 0.5 + 1.0) + fi * 137.5;
        let radius = 0.05 + fi * 0.03;
        // Wobble radius
        let rWobble = sin(time * 2.0 + fi) * 0.02 * wobble;
        let offset = vec2<f32>(cos(angle), sin(angle)) * (radius + rWobble);
        let bubblePos = mouse + offset * vec2<f32>(1.0, aspect);

        // Distance to this bubble center
        let dVec = (uv - bubblePos) * vec2<f32>(aspect, 1.0);
        let d = length(dVec);
        minBubbleDist = min(minBubbleDist, d);

        if (d < size) {
            // Sphere normal approximation
            let z = sqrt(max(0.0, size*size - d*d));
            let nXY = dVec / size;
            bubbleNormal = normalize(vec3<f32>(nXY, z / size));
            bubbleDepth = z;

            // ── Idea 1: Snell rim (§12.2F) ────────────────────────────
            // refract() through the sphere normal. The ball-lens mix below
            // still owns the core. Refraction Index still scales the bend.
            let eta = 1.0 / (1.2 + refrStrength * 3.0);
            let incident = vec3<f32>(0.0, 0.0, -1.0);
            let snell = refract(incident, bubbleNormal, eta);
            let bounced = reflect(incident, bubbleNormal);
            let tir = dot(snell, snell) < 1e-8;
            let bent = select(snell.xy, bounced.xy, tir);
            let refracted = clamp(uv + bent * refrStrength * 0.45, vec2<f32>(0.0), vec2<f32>(1.0));
            // Ball lens. The core shows the inverted, minified view.
            let inverted = bubblePos - (uv - bubblePos) * (0.55 + refrStrength * 2.0);
            let invAmt = smoothstep(0.85, 0.25, d / size) * 0.85;
            finalUV = mix(refracted, inverted, invAmt);
            inBubble = true;

            // Calculate bubble wall thickness (thin film approximation)
            // Bubbles have thin walls, thicker near edges
            bubbleThickness = 0.01 + (d / size) * 0.02;

            hitB = hitA;
            hitA = bubblePos * vec2<f32>(aspect, 1.0);
            hits = hits + 1;
        }
    }

    var color = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    if (inBubble) {
        // View direction
        let viewDir = vec3<f32>(0.0, 0.0, 1.0);
        // Fresnel effect (strong at bubble edges)
        let cos_theta = max(dot(viewDir, bubbleNormal), 0.0);
        let R0 = 0.04; // Glass-air
        let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

        // Bubble glass color (very slight tint)
        let bubbleColor = vec3<f32>(0.96, 0.98, 1.0);
        // Beer-Lambert for thin glass
        let absorption = exp(-(1.0 - bubbleColor) * bubbleThickness * glassDensity);
        // Transmission coefficient
        let transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
        // Apply bubble tint and alpha
        color = vec4<f32>(color.rgb * bubbleColor, transmission);

        // Idea 2: thin-film wall. The wall thickness already computed above
        // sets an interference phase per wavelength (red, green, blue), so the
        // rim shows rings of film colour where the wall changes thickness.
        let filmPhase = bubbleThickness * 42.0 * vec3<f32>(1.0 / 0.65, 1.0 / 0.53, 1.0 / 0.45);
        let film = vec3<f32>(0.5) + 0.5 * cos(6.2831853 * filmPhase);
        color = vec4<f32>(mix(color.rgb, color.rgb * (0.4 + film * 0.9), clamp(fresnel * 0.9, 0.0, 0.55)), color.a);

        // Add specular highlight
        let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
        let specBase = max(dot(bubbleNormal, lightDir), 0.0);
        let spec = pow(specBase, 15.0);
        // ── Idea 2: Airy disc (§12.2F) ──────────────────────────────
        // Diffraction rings on the highlight this bubble already draws.
        let airyX = (1.0 - specBase) * 8.0;
        let ring = airyDisc(airyX) * smoothstep(0.2, 0.75, specBase);
        color = color + vec4<f32>(spec, spec, spec, 0.0) * 0.8 + vec4<f32>(ring, ring, ring, 0.0) * 0.28;

        // Fresnel edge enhancement
        let fresnelEdge = pow(length(bubbleNormal.xy), 3.0);
        color = mix(color, vec4<f32>(0.8, 0.9, 1.0, 1.0), fresnelEdge * 0.3);

        // Idea 3: contact walls. Where two bubbles overlap they share a flat
        // wall on the perpendicular bisector of their centres (a Plateau wall),
        // which catches the light as a thin bright line.
        if (hits >= 2) {
            let p = uv * vec2<f32>(aspect, 1.0);
            let axis = hitA - hitB;
            let wallN = axis / max(length(axis), 0.0001);
            let planeDist = abs(dot(p - (hitA + hitB) * 0.5, wallN));
            let wall = 1.0 - smoothstep(0.0015, 0.005, planeDist);
            color = vec4<f32>(color.rgb + vec3<f32>(0.85, 0.92, 1.0) * wall * 0.7, max(color.a, wall * 0.8));
        }
    } else {
        // Outside bubble — alpha encodes proximity to nearest bubble edge
        let edgeProx = clamp(1.0 - minBubbleDist / max(size, 0.001) * 0.5, 0.0, 1.0) * 0.2 + bass * 0.05;
        color = vec4<f32>(color.rgb, clamp(edgeProx, 0.0, 1.0));
    }

    color = vec4<f32>(aces(max(color.rgb, vec3<f32>(0.0)) * 0.8), color.a);
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, color);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, color);
}
