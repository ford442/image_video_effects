// ═══════════════════════════════════════════════════════════════════
//  Molten Glass
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-16, 2026-11-15
//  Ideas: cooling crust where heat falls; drip thread on the convection packet; blackbody incandescence from the heat field (§12.2F) [Idea 3]; cooling craquelure in the cooling skirt [Idea 4]
//  A packing: raw heat in A.r (C.r is heat). ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
// zoom_params: x=HeatRadius, y=Viscosity, z=Refraction, w=CoolingRate

// Idea 3 tuning: HDR gain of the blackbody emission before ACES. Kept low so the refracted photo stays
// readable inside the saturated hot core (2.2 flattened it to a cream disc).
const INCAND_GAIN: f32 = 0.5;
// Idea 4 tuning: crack cells across the frame height.
const CRACK_SCALE: f32 = 13.0;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);

    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;

    // Audio: bass adds heat injection, mids feeds viscosity wobble, treble sharpens refraction
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let heatRadius = max(0.01, u.zoom_params.x * 0.2);
    let viscosity = u.zoom_params.y * (1.0 + mids * 0.5);
    let refraction = u.zoom_params.z * 0.1 * (1.0 + treble * 0.6);
    let coolingRate = 0.01 + u.zoom_params.w * 0.1;
    let glassDensity = 1.15;

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Advect heat upward with a smooth, viscosity-dependent convection conveyor.
    let sourceOffset = vec2<i32>(
        i32(round(sin(uv.y * 16.0 + time * 2.2) * (1.0 + viscosity * 2.0))),
        2 + i32(round(bass * 2.0))
    );
    let sourceCoord = clamp(coord + sourceOffset, vec2<i32>(0), maxCoord);
    let prevColor = textureLoad(dataTextureC, sourceCoord, 0);
    var heat = prevColor.r;

    // Decay heat
    heat = max(0.0, heat - coolingRate);

    // Add heat from mouse (bass pulses the injection)
    let influence = smoothstep(heatRadius, 0.0, dist);
    let heldBoost = mix(0.35, 1.0, step(0.5, u.zoom_config.w));
    heat = min(1.0, heat + influence * (0.5 + bass * 0.4) * heldBoost);

    let convectionPacket = pow(max(0.0, sin(uv.y * 34.0 + uv.x * 11.0 - time * 11.0)), 10.0);
    heat += convectionPacket * prevColor.r * (0.04 + mids * 0.04);

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let clickDelta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let heatFront = smoothstep(0.025, 0.0, abs(length(clickDelta) - age * 0.36));
            heat += heatFront * exp(-age * 1.25) * (0.55 + bass * 0.25);
        }
    }
    heat = clamp(heat, 0.0, 1.0);

    // Write new heat state
    textureStore(dataTextureA, coord, vec4<f32>(heat, 0.0, 0.0, 1.0));

    // Calculate distortion based on heat
    let wobble = sin(uv.y * 20.0 + time * 5.0) * cos(uv.x * 20.0 + time * 3.0) * 0.02;
    let distort = (heat * refraction) + (heat * wobble * viscosity);

    // Offset UVs based on heat gradient
    let pushDelta = uv - mousePos;
    let safePushDir = pushDelta / max(length(pushDelta), 0.0001);

    let offset = safePushDir * distort * 0.5 + vec2<f32>(
        sin(uv.y * 50.0 + heat * 10.0),
        cos(uv.x * 50.0 + heat * 10.0)
    ) * distort * 0.5;

    let finalUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Physical properties of molten glass
    // Normal from heat distortion
    let normal = normalize(vec3<f32>(offset * 10.0, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Fresnel increases with heat (surface becomes more irregular)
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let roughness = heat * 0.3; // More rough when hot
    let fresnel = R0 + (1.0 - R0 - roughness) * pow(1.0 - cos_theta, 5.0);
    
    // Glass thickness varies inversely with heat (thins when melting)
    let thickness = 0.1 * (1.0 - heat * 0.3);
    
    // Molten glass color shifts with heat (orange/red when hot)
    let coolGlassColor = vec3<f32>(0.92, 0.96, 1.0);
    let hotGlassColor = vec3<f32>(1.0, 0.7, 0.4);
    let glassColor = mix(coolGlassColor, hotGlassColor, heat);
    
    // Beer-Lambert absorption
    let absorption = exp(-(1.0 - glassColor) * thickness * glassDensity);
    
    // Transmission coefficient
    let transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;

    // Apply glass tint and transmission
    color = vec4<f32>(clamp(color.rgb * glassColor, vec3<f32>(0.0), vec3<f32>(4.0)), clamp(transmission, 0.0, 1.0));

    // Gloss/specular where heat is high
    let gloss = smoothstep(0.8, 1.0, heat) * 0.2;
    color = vec4<f32>(clamp(color.rgb + vec3<f32>(gloss), vec3<f32>(0.0), vec3<f32>(4.0)), color.a);

    // Idea 1 — cooling crust. Idea 2 — the convection packet drawn as a drip.
    let crust = smoothstep(0.0, 0.12, prevColor.r - heat) * (1.0 - heat);
    let drip = convectionPacket * heat;
    var body = color.rgb * mix(vec3<f32>(1.0), vec3<f32>(0.55, 0.62, 0.70), crust)
        + vec3<f32>(1.0, 0.78, 0.42) * drip * (0.55 + bass * 0.2);

    // ── Idea 3: incandescence (blackbody row, §12.2F) ──
    // Hot glass EMITS: dull red -> orange -> yellow-white, super-linear in the heat so it only
    // switches on in the hottest part of the field. Over a dark photo a hot blob now glows.
    let incand = smoothstep(0.3, 1.0, heat);
    let blackbodyLow = mix(vec3<f32>(0.45, 0.04, 0.0), vec3<f32>(1.0, 0.36, 0.05), smoothstep(0.0, 0.55, incand));
    let blackbody = mix(blackbodyLow, vec3<f32>(1.0, 0.88, 0.55), smoothstep(0.55, 1.0, incand));
    body += blackbody * incand * sqrt(incand) * (0.55 + bass * 0.2) * INCAND_GAIN;

    // ── Idea 4: cooling craquelure (native) ──
    // Thermal-stress cracks open where the glass has cooled below the soft range: the cooling
    // front (`crust`) plus the cooled skirt around a heat source. Healed (no cracks) where heat is
    // high again. Voronoi cell edges, static in screen space so nothing strobes.
    let skirt = smoothstep(0.03, 0.10, heat) * (1.0 - smoothstep(0.25, 0.6, heat));
    // No cracks on bare photo: `crust` is non-zero on just-cooled pixels at heat == 0, so gate by heat.
    let crackZone = clamp(max(crust * 3.0, skirt), 0.0, 1.0) * smoothstep(0.0, 0.05, heat);
    if (crackZone > 0.02) {
        let vp = uv * vec2<f32>(aspect, 1.0) * CRACK_SCALE;
        let vi = floor(vp);
        let vf = fract(vp);
        var f1 = 8.0;
        var f2 = 8.0;
        for (var j = -1; j <= 1; j = j + 1) {
            for (var i = -1; i <= 1; i = i + 1) {
                let g = vec2<f32>(f32(i), f32(j));
                let d = length(g + hash22(vi + g) - vf);
                let nf1 = min(f1, d);
                f2 = min(f2, max(f1, d));
                f1 = nf1;
            }
        }
        let edge = f2 - f1;
        let crackCore = 1.0 - smoothstep(0.0, 0.10, edge);
        let crackRim = smoothstep(0.0, 0.10, edge) * (1.0 - smoothstep(0.10, 0.26, edge));
        body = body * (1.0 - 0.75 * crackCore * crackZone)
            + vec3<f32>(1.0, 0.5, 0.12) * crackRim * crackZone * smoothstep(0.03, 0.4, heat) * 0.6;
    }
    let display = aces(max(body, vec3<f32>(0.0)));
    textureStore(writeTexture, coord, vec4<f32>(display, color.a));

    // Depth pass-through, brought slightly forward where glass is hottest
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth - heat * 0.1, 0.0, 1.0), 0.0, 0.0, 0.0));
}
