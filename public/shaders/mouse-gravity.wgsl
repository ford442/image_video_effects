// ═══════════════════════════════════════════════════════════════════
//  Interactive Gravity
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, chromatic-aberration, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: frame-dragging swirl with drag-velocity smear; Doppler-beamed photon ring from the lensed sky; tidal spaghettification near the hole
//  A packing: display RGBA; texel (0,0) = (prevMouse.xy, prevTime, valid); texel (1,0) = (smoothed pointer velocity.xy in aspect-uv/s, 0, valid)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Strength, y=Radius, z=Aberration, w=Darkness

const PI: f32 = 3.14159265358979;

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);

    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let aspectV = vec2<f32>(aspect, 1.0);

    // The hole sits directly on the cursor (HEAD's extraBuffer spring was dead:
    // the buffer is re-uploaded every frame, so it reset to the mouse anyway).
    let wellPos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Audio: bass deepens the well, mids widens its reach, treble splits chromatic aberration
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let strength = u.zoom_params.x * 2.0 * (1.0 + bass * 0.4) * (1.0 + mouseDown * 0.3);    // 0.0 to 2.0
    let radius = max(0.01, u.zoom_params.y * 0.5 * (1.0 + mids * 0.3)); // 0.01 to 0.5
    let aberration = u.zoom_params.z * 0.05 * (1.0 + treble * 0.8); // 0.0 to 0.05
    let darkness = u.zoom_params.w;          // 0.0 to 1.0

    // --- Pointer velocity from A-texel state (exact C loads) ---------------
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let dt = time - st0.z;
    var rawVel = vec2<f32>(0.0);
    let st0Ok = st0.w > 0.5 && all(st0.xy == st0.xy) && all(abs(st0.xy) <= vec2<f32>(4.0));
    if (st0Ok && dt > 1e-4 && dt < 0.25) {
        rawVel = (wellPos - st0.xy) * aspectV / max(dt, 1e-3);
        let sp = length(rawVel);
        if (sp > 4.0) { rawVel = rawVel * (4.0 / sp); }
    }
    // Leftover C from another shader can hold NaN or huge values here; only
    // trust a finite, in-range velocity written alongside a valid texel (0,0).
    let prevVel = select(vec2<f32>(0.0), st1.xy,
        st0Ok && st1.w > 0.5 && all(st1.xy == st1.xy) && dot(st1.xy, st1.xy) <= 16.0);
    let vel = mix(prevVel, rawVel, 0.35);     // aspect-uv per second

    // Vector from UV to the well, aspect-correct
    let toMouse = uv - wellPos;
    let distVec = toMouse * aspectV;
    let dist = length(distVec);
    let well = exp(-dist / radius);

    // --- Click gravity pulses ---------------------------------------------
    // Every live ripple is a temporary SECONDARY well that pulls toward its own
    // click point (HEAD multiplied it into the main well's radial scale, so the
    // dent was centred on the cursor instead of the click). Relaxes over ~2 s.
    var clickPull = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 2.0) { continue; }
        let rpVec = (uv - rp.xy) * aspectV;
        let rpDist = length(rpVec);
        let rpStrength = 0.6 * exp(-age * 2.0);
        clickPull = clickPull - (uv - rp.xy) * rpStrength * exp(-rpDist / radius);
    }

    // Gravity lens: NewUV = Well + (UV - Well) * (1 - Strength * exp(-dist / Radius)).
    // Magnifies toward the well and inverts once the factor goes negative.
    let distortion = 1.0 - strength * well;

    // Idea 1: frame-dragging swirl — a spinning hole drags space around with it,
    // a bounded tangential twist ∝ exp(-d/r). Moving the hole smears space
    // behind it along the A-texel drag velocity.
    let swirl = strength * 0.8 * well;
    let twisted = rot2(distVec, swirl);
    let dragSmear = -vel * 0.06 * well;

    // Idea 3: tidal stretching — the pull varies steeply with distance, so
    // near the hole the image is spaghettified: stretched along the radius,
    // squeezed across it. Grows with well² (tides are the field's gradient).
    let tide = strength * 0.6 * well * well;
    let rHat = twisted / max(dist, 1e-5);
    let radialC = dot(twisted, rHat);
    let tidal = rHat * (radialC / (1.0 + tide)) + (twisted - rHat * radialC) * (1.0 + 0.5 * tide);

    // Chromatic aberration confined to the well (HEAD fringed the whole frame).
    let ab = aberration * well;
    let offsetR = tidal * (distortion - ab);
    let offsetG = tidal * distortion;
    let offsetB = tidal * (distortion + ab);

    let uvR = wellPos + (offsetR + dragSmear) / aspectV + clickPull;
    let uvG = wellPos + (offsetG + dragSmear) / aspectV + clickPull;
    let uvB = wellPos + (offsetB + dragSmear) / aspectV + clickPull;

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let gS = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    var color = vec3<f32>(r, gS.g, b);

    // Darkness at the singularity (center)
    let core = smoothstep(radius * 0.2, radius * 0.5, dist);
    color = mix(vec3<f32>(0.0), color, mix(1.0, core, darkness));

    // Idea 2: Doppler-beamed photon ring — the ring is the lensed sky wrapped
    // around the horizon, rotating with the hole's spin; the approaching side
    // (left) is beamed brighter and bluer, the receding side dim and red.
    let ring = smoothstep(0.02, 0.0, abs(dist - radius * 0.35));
    let phi = atan2(distVec.y, distVec.x + 1e-7);
    let orbit = phi + time * 0.8;
    let skyUV = wellPos + vec2<f32>(cos(orbit), sin(orbit)) * radius * 1.6 / aspectV;
    let sky = textureSampleLevel(readTexture, u_sampler, skyUV, 0.0).rgb;
    let approach = cos(phi - PI);
    let dop = 1.0 + 0.55 * approach;              // >= 0.45, so the cube stays positive
    let beaming = dop * dop * dop;
    let dopTint = mix(vec3<f32>(1.0, 0.55, 0.3), vec3<f32>(0.75, 0.9, 1.15), 0.5 + 0.5 * approach);
    let ringGlow = ring * darkness * (1.0 - core) * (0.5 + 0.8 * treble);
    color = color + (sky * 0.7 + vec3<f32>(0.25)) * dopTint * beaming * ringGlow;

    let display = aces(max(color, vec3<f32>(0.0)));

    // Lensing-mask alpha: brighter near the warped core, luma-keyed elsewhere
    let alpha = clamp(dot(display, vec3<f32>(0.299, 0.587, 0.114)) * gS.a + (1.0 - core) * darkness * 0.5 + ringGlow * 0.3, 0.0, 1.0);
    let finalOut = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, finalOut);

    // A: display RGBA, except the two state texels the next frame reads back.
    var aOut = finalOut;
    if (global_id.x == 0u && global_id.y == 0u) {
        aOut = vec4<f32>(wellPos, time, 1.0);
    } else if (global_id.x == 1u && global_id.y == 0u) {
        aOut = vec4<f32>(vel, 0.0, 1.0);
    }
    textureStore(dataTextureA, coord, aOut);

    // Depth warped with the lens so compositing follows the bent geometry.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uvG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
