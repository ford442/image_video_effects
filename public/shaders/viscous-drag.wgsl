// Thick-liquid displacement with advected jets, vortices, and click pressure fronts.
// Upgraded: 2026-11-15
// Ideas: shear-thinning viscosity (prior dragEnergy thins the mix locally); bass jet surge; thickness-gradient meniscus lighting (native); strain-directed smear (native)
// A packing: RG offset, thickness, drag energy (raw sim state, unchanged)

#include "_prelude.wgsl"

fn historyLoad(pixel: vec2<i32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

// Tuning for the 2026-11-15 ideas. Zero a gain to get the 2026-10 look back exactly.
const MENISCUS_SLOPE: f32 = 0.05;  // surface slope per (thickness change per uv)
const MENISCUS_GAIN: f32 = 2.2;    // meniscus highlight strength
const MENISCUS_SHADE: f32 = 0.45;  // matching diffuse relief on the photo
const SMEAR_LEN: f32 = 0.05;       // uv length of the drag streak at dragEnergy = 1

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let viscosity = mix(0.08, 0.88, u.zoom_params.x);
    let dragStrength = mix(0.1, 2.0, u.zoom_params.y);
    let recovery = mix(0.88, 0.994, u.zoom_params.z);
    let scale = mix(0.01, 0.2, u.zoom_params.w);

    // Idea 2: bass jet surge — a secondary jet direction briefly adds onto the
    // constant rotating jet on bass energy, reading as the liquid getting
    // "pumped" on the beat instead of only drifting at a fixed rate.
    let jetSurgeDirection = normalize(vec2<f32>(cos(time * 1.9 + 1.7), sin(time * 2.3 + 0.4)));
    let jetDirection = normalize(vec2<f32>(cos(time * 0.77), sin(time * 0.61)) + jetSurgeDirection * audio.x * audio.x * 1.4);

    // Advect the RG offset state along the (now surge-augmented) liquid jet.
    let advectPixels = vec2<i32>(round(jetDirection * (1.0 + (1.0 - viscosity) * 3.0) * (1.0 + audio.x * 0.6)));
    let baseCoord = coord - advectPixels;
    let previous = historyLoad(baseCoord);
    let upState = historyLoad(baseCoord + vec2<i32>(0, -1));
    let downState = historyLoad(baseCoord + vec2<i32>(0, 1));
    let leftState = historyLoad(baseCoord + vec2<i32>(-1, 0));
    let rightState = historyLoad(baseCoord + vec2<i32>(1, 0));
    let neighborState = (upState + downState + leftState + rightState) * 0.25;

    // Idea 1: shear-thinning viscosity — the prior frame's drag energy (a
    // proxy for local shear/strain, already stored in the .w channel) thins
    // the effective viscosity where the fluid was recently sheared hard,
    // mimicking real non-Newtonian shear-thinning behavior.
    let shearThinning = clamp(previous.w * 0.5, 0.0, 0.6);
    let effectiveViscosity = clamp(viscosity - shearThinning, 0.02, 0.95);
    let diffusedOffset = mix(previous.xy, neighborState.xy, effectiveViscosity);

    let aspect = resolution.x / resolution.y;
    let delta = vec2<f32>((uv.x - u.zoom_config.y) * aspect, uv.y - u.zoom_config.z);
    let distanceToMouse = max(length(delta), 0.001);
    let radial = delta / distanceToMouse;
    let tangent = vec2<f32>(-radial.y, radial.x);
    let mouseMask = smoothstep(0.18, 0.0, distanceToMouse);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let mouseForce = (radial + tangent * sin(time * 5.0) * 0.55) * mouseMask * (0.12 + held * 1.88) * dragStrength * 0.018;

    // Traveling vortices form a second fast-motion family independent of input history.
    let vortexPhase = dot(uv, vec2<f32>(19.0, -13.0)) - time * (6.0 + dragStrength * 2.0);
    let vortexPacket = pow(0.5 + 0.5 * cos(vortexPhase), 16.0);
    let vortexForce = vec2<f32>(-jetDirection.y, jetDirection.x) * vortexPacket * dragStrength * (0.002 + audio.y * 0.004);
    var clickForce = vec2<f32>(0.0);
    var clickPressure = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.8) { continue; }
        {
            let rippleDelta = vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y);
            let rippleDistance = max(length(rippleDelta), 0.001);
            let ring = abs(rippleDistance - age * (0.18 + audio.x * 0.08));
            let front = (1.0 - smoothstep(0.0, 0.026, ring)) * (1.0 - age / 2.8);
            clickForce += rippleDelta / rippleDistance * front * 0.018 * dragStrength;
            clickPressure += front;
        }
    }
    var newOffset = (diffusedOffset * recovery) + mouseForce + vortexForce + clickForce;
    newOffset = clamp(newOffset, vec2<f32>(-0.5), vec2<f32>(0.5));
    let strain = length(newOffset - previous.xy);
    let pressureDrive = mouseMask * (0.08 + held * 0.52) + clickPressure * 0.22 + vortexPacket * audio.x * 0.08;
    let thickness = clamp(mix(previous.z, neighborState.z, viscosity * 0.28) * recovery + pressureDrive, 0.0, 2.0);
    let dragEnergy = clamp(mix(previous.w, neighborState.w, 0.2) * recovery + strain * 3.0 + clickPressure * 0.12, 0.0, 2.0);
    textureStore(dataTextureA, coord, vec4<f32>(newOffset, thickness, dragEnergy));

    let sampleUV = clamp(uv - newOffset * scale, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // ── Idea 2: strain-directed smear (native) ────────────────────────
    // Thick liquid dragged along a direction does not just displace the photo, it
    // STRETCHES it along that direction, in proportion to the strain it carries.
    // The single HEAD tap becomes a short comet tail upstream along the offset
    // direction; length and weight follow dragEnergy, so nothing happens where the
    // liquid has not flowed (dragEnergy ~ 0 returns the HEAD tap exactly).
    let flowDir = newOffset / max(length(newOffset), 1e-5);
    let smearAmount = smoothstep(0.03, 0.55, dragEnergy);
    if (smearAmount > 0.004) {
        let smearVec = flowDir * (min(dragEnergy, 1.2) * SMEAR_LEN);
        var tail = vec4<f32>(0.0);
        for (var k = 1; k <= 4; k = k + 1) {
            let tuv = clamp(sampleUV - smearVec * (f32(k) * 0.25), vec2<f32>(0.0), vec2<f32>(1.0));
            tail = tail + textureSampleLevel(readTexture, u_sampler, tuv, 0.0);
        }
        color = mix(color, (color + tail) * 0.2, smearAmount * 0.85);
    }

    // ── Idea 1: thickness-gradient meniscus lighting (native) ─────────
    // HEAD lit a normal built from the offset VECTOR (vec3(offset, 0.02): nearly
    // horizontal, so dot(n, L)^20 never exceeds ~0.02 and the "illuminated ridges"
    // were invisible). The liquid's own relief is its stored THICKNESS: its gradient
    // (neighbours already loaded for the advection) tilts the normal, so thick ridges
    // catch the light on one flank and fall into relief on the other.
    // Light direction and exponent are HEAD's.
    let thickGrad = vec2<f32>(rightState.z - leftState.z, downState.z - upState.z) * (0.5 * resolution.y);
    let normal = normalize(vec3<f32>(-thickGrad * MENISCUS_SLOPE, 1.0));
    let lightDirection = normalize(vec3<f32>(0.5, 0.5, 1.0));
    let facing = dot(normal, lightDirection);
    let wet = smoothstep(0.02, 0.45, thickness);
    let specular = pow(max(facing, 0.0), 20.0) * (length(newOffset) + thickness * 0.16) * (1.0 + audio.z) * MENISCUS_GAIN * wet;
    color = vec4<f32>(color.rgb * (1.0 + MENISCUS_SHADE * (facing - 0.8165) * wet), color.a);
    let ridgeColor = vec3<f32>(0.14 + audio.x * 0.12, 0.38 + audio.y * 0.28, 0.62 + audio.z * 0.38) * dragEnergy * 0.22;
    let hdr = max(color.rgb + vec3<f32>(specular) + ridgeColor, vec3<f32>(0.0));
    let mapped = clamp((hdr * (2.51 * hdr + 0.03)) / (hdr * (2.43 * hdr + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
    let alpha = clamp(color.a * 0.78 + thickness * 0.12 + dragEnergy * 0.08 + length(newOffset) * 0.3, 0.0, 1.0);
    let finalColor = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, coord, finalColor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
