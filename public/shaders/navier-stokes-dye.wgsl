// ═══════════════════════════════════════════════════════════════════
//  Navier-Stokes Dye Injection
//  Category: simulation
//  Features: dye-advection, vorticity-confinement, audio-reactive, mouse-source
//  Rescue: 2026-10-05 — HEAD stored velocity in A and then overwrote the same texel with
//          colour (last store wins), so next frame read colour as velocity; nothing was
//          advected; the palette was plasmaBuffer[1..255], which the runtime never writes
//          (index 0 is audio), so it was black; advect_velocity was a dead entry point.
//          Now one store of (velocity, dye, hue) with semi-Lagrangian advection of all four,
//          vorticity confinement, a divergence-damping step in place of a pressure solve, a
//          meandering jet at the cursor (radial push while held), and an analytic palette.
//          Numpy-gated: scripts/sim_models/nsd_rescue.py
//  A packing: (vel.x, vel.y in px/frame, dye density, dye hue)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const VMAX: f32 = 6.0;

fn wrapi(c: vec2<i32>) -> vec2<i32> {
    let d = vec2<i32>(textureDimensions(dataTextureC));
    return ((c % d) + d) % d;
}

fn stateAt(c: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, wrapi(c), 0);
}

fn velAt(c: vec2<i32>) -> vec2<f32> {
    return stateAt(c).xy;
}

// Manual bilinear (exact loads; works on unfilterable float formats).
fn sampleState(p: vec2<f32>) -> vec4<f32> {
    let f0 = floor(p);
    let fr = p - f0;
    let c = vec2<i32>(f0);
    let a = stateAt(c);
    let b = stateAt(c + vec2<i32>(1, 0));
    let d = stateAt(c + vec2<i32>(0, 1));
    let e = stateAt(c + vec2<i32>(1, 1));
    return mix(mix(a, b, fr.x), mix(d, e, fr.x), fr.y);
}

fn curlAt(c: vec2<i32>) -> f32 {
    return 0.5 * ((velAt(c + vec2<i32>(1, 0)).y - velAt(c - vec2<i32>(1, 0)).y)
                - (velAt(c + vec2<i32>(0, 1)).x - velAt(c - vec2<i32>(0, 1)).x));
}

fn divAt(c: vec2<i32>) -> f32 {
    return 0.5 * ((velAt(c + vec2<i32>(1, 0)).x - velAt(c - vec2<i32>(1, 0)).x)
                + (velAt(c + vec2<i32>(0, 1)).y - velAt(c - vec2<i32>(0, 1)).y));
}

fn palette(t: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(6.28318 * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let pos = vec2<f32>(coord);
    let uv = (pos + 0.5) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = step(0.5, u.zoom_config.w);

    let viscosity = u.zoom_params.x;
    let turbulence = u.zoom_params.y;
    let rippleStrength = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let damping = 0.002 + 0.02 * viscosity;
    let vorticityScale = 0.05 + 0.3 * turbulence;
    // Velocities are px/frame: scale forces with the working size so the flow covers the
    // same share of the frame at any working size (the numpy model is 128², scale 1).
    let pxScale = resolution.x / 128.0;
    let push = (0.3 + 2.0 * rippleStrength) * (1.0 + bass * 0.4 + mids * 0.2) * pxScale;

    // ── Advect velocity, dye and hue from p - v ──
    let here = stateAt(coord);
    let adv = sampleState(pos - here.xy);

    // ── Forces ──
    let aspect = resolution.x / resolution.y;
    let toMouse = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0);
    let dM2 = dot(toMouse, toMouse);
    let near = exp(-dM2 * 900.0);
    let radial = toMouse / max(length(toMouse), 1e-4);
    // Idle: a jet whose heading meanders, so the source sheds curling plumes.
    let heading = time * 0.6 + 1.5 * sin(time * 0.23);
    var force = vec2<f32>(cos(heading), sin(heading)) * near * 0.12 * push;
    // Held: radial push away from the cursor.
    force += radial * near * held * 0.25 * push;

    var dyeBurst = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rip = u.ripples[i];
        let age = time - rip.z;
        if (age < 0.0 || age > 2.0) { continue; }
        let toR = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
        let dr = length(toR);
        let fade = 1.0 - age * 0.5;
        force += toR / max(dr, 1e-4) * exp(-dr * dr * 800.0) * fade * rippleStrength * 1.5;
        dyeBurst += exp(-dr * dr * 600.0) * (1.0 - age * 0.4) * rippleStrength;
    }

    // Vorticity confinement: push along the |curl| gradient's normal.
    let curl = curlAt(coord);
    let gradW = 0.5 * vec2<f32>(abs(curlAt(coord + vec2<i32>(1, 0))) - abs(curlAt(coord - vec2<i32>(1, 0))),
                                abs(curlAt(coord + vec2<i32>(0, 1))) - abs(curlAt(coord - vec2<i32>(0, 1))));
    let nGrad = gradW / (length(gradW) + 1e-5);
    let confine = vec2<f32>(nGrad.y, -nGrad.x) * curl * vorticityScale;

    // One gradient step on the divergence: a cheap stand-in for a pressure projection.
    let gradDiv = 0.5 * vec2<f32>(divAt(coord + vec2<i32>(1, 0)) - divAt(coord - vec2<i32>(1, 0)),
                                  divAt(coord + vec2<i32>(0, 1)) - divAt(coord - vec2<i32>(0, 1)));

    // Filament runner / vortex ribbon (HEAD): small travelling gains on speed.
    let filamentRunner = pow(max(0.0, sin(atan2(adv.y, adv.x) * 4.0 - time * (16.0 + treble * 8.0))), 12.0);
    let vortexRibbon = pow(max(0.0, sin(abs(curl) * 12.0 - time * (10.0 + mids * 5.0))), 14.0);
    let gain = 1.0 + filamentRunner * turbulence * 0.03 + vortexRibbon * turbulence * 0.02;

    var vel = (adv.xy * gain + force + confine + 0.25 * gradDiv) * (1.0 - damping);
    let speed = length(vel);
    if (speed > VMAX * pxScale) { vel = vel * (VMAX * pxScale / speed); }

    // ── Dye: advected density fades slowly; the cursor and clicks inject new dye ──
    let inject = near * (0.08 + held * 0.3) + dyeBurst * 0.4;
    let injectHue = time * 0.05 + colorShift + treble * 0.1;
    let dye = clamp(adv.z * (0.998 - 0.004 * viscosity) + inject, 0.0, 1.0);
    let hue = select(adv.w, (adv.z * adv.w + inject * injectHue) / (adv.z + inject + 1e-6), inject > 1e-3);

    textureStore(dataTextureA, coord, vec4<f32>(vel, dye, hue));

    // ── Display: the image, tinted by flow speed and coloured by dye ──
    let src = textureLoad(readTexture, coord, 0);
    let dyeColor = palette(hue + colorShift + curl * 0.1);
    let saturation = clamp(length(vel) / pxScale * 0.15, 0.0, 1.0);
    var dyed = mix(src.rgb, src.rgb * (0.6 + dyeColor * 0.8), saturation);
    dyed = mix(dyed, dyeColor, clamp(dye, 0.0, 1.0) * (0.75 + 0.2 * bass));
    let finalAlpha = mix(src.a, 1.0, clamp((saturation + dye) * 0.7, 0.0, 1.0));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(dyed, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
