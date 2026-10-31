// ═══════════════════════════════════════════════════════════════════
//  Quantum Mycelial Neural Web
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27, 2026-10-31
//  Ideas: action-potential spikes along fibres; synaptic junction flares; axonal varicosities (radius swells into boutons that the spike lights as it passes); Fresnel-Schlick myelin sheath rim (E.F Fresnel-Schlick); entanglement phase-lock (Entanglement slider also locks the three axons' spike phases together)
//  A packing: ACES display RGBA (C unused)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Web Density, .y = Pulse Speed, .z = Bioluminescence, .w = Entanglement

// --- CORE UTILITIES ---
// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D Noise for organic structures
fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + vec3<f32>(33.33));
    return fract((p.xxy + p.yxx) * p.zyx);
}

// 3D Perlin noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);
    return mix(
        mix(mix(dot(hash33(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash33(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash33(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(dot(hash33(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash33(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash33(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// Distance estimation for mycelial network
// returns (sdf, axial coord along nearest fibre, junction closeness, fibre id 0/1/2)
fn map(p: vec3<f32>, time: f32, audio: f32) -> vec4<f32> {
    let density = u.zoom_params.x; // Web Density
    let entanglement = u.zoom_params.w; // Entanglement

    var pos = p;
    var d = length(pos) - 1.0;

    // Add curl noise distortion based on entanglement
    var n = vec3<f32>(
        noise(pos * 2.0 + vec3<f32>(time * 0.1)),
        noise(pos * 2.0 + vec3<f32>(time * 0.1 + 100.0)),
        noise(pos * 2.0 + vec3<f32>(time * 0.1 + 200.0))
    ) * entanglement;

    pos = pos + n;

    // Create fibrous structures using a sine-based domain repetition and noise
    let spacing = max(0.1, 1.0 - density * 0.4);
    var q = pos / spacing;

    // Apply rotations for entanglement
    q = vec3<f32>(rot(q.z * entanglement * 0.5) * q.xy, q.z);
    q = vec3<f32>(q.x, rot(q.x * entanglement * 0.5) * q.yz);

    // Fibers
    // Idea 3 (varicosities): each axon's radius swells into boutons every ~1 unit of
    // its own axis, where a real axon stores vesicles. Boutons are narrower than
    // 35% so the SDF stays safely conservative at the 0.5 step factor.
    let r0 = 0.1 * density;
    let fiber_x = length(q.yz) - r0 * (1.0 + 0.35 * sin(q.x * 6.0));
    let fiber_y = length(q.xz) - r0 * (1.0 + 0.35 * sin(q.y * 6.0));
    let fiber_z = length(q.xy) - r0 * (1.0 + 0.35 * sin(q.z * 6.0));

    // Combine fibers
    let min_fiber = min(min(fiber_x, fiber_y), fiber_z);

    // Idea 1 support: axial coordinate of the nearest fibre + which axon it is
    // (the per-fibre phase seed is applied in main so Entanglement can lock it).
    var axial = q.x;
    var fibreId = 0.0;
    if (fiber_y <= fiber_x && fiber_y <= fiber_z) { axial = q.y; fibreId = 1.0; }
    if (fiber_z < fiber_x && fiber_z < fiber_y) { axial = q.z; fibreId = 2.0; }

    // Idea 2 support: second-nearest fibre almost as close = a crossing.
    let max_fiber = max(max(fiber_x, fiber_y), fiber_z);
    let second_fiber = fiber_x + fiber_y + fiber_z - min_fiber - max_fiber;
    let junction = 1.0 - smoothstep(0.0, 0.18, second_fiber - min_fiber);

    // Add some noise displacement for organic feel
    let disp = noise(q * 4.0) * 0.1 * (1.0 + audio);

    return vec4<f32>(min_fiber * spacing - disp, axial, junction, fibreId);
}

// Calculate normal
fn getNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audio).x - map(p - e.xyy, time, audio).x,
        map(p + e.yxy, time, audio).x - map(p - e.yxy, time, audio).x,
        map(p + e.yyx, time, audio).x - map(p - e.yyx, time, audio).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    // HEAD fix: y-up (HEAD left uv.y down, so the picture and the mouse mapping disagreed).
    let st = vec2<f32>(uv.x - 0.5, 0.5 - uv.y) * 2.0;
    let aspect = resolution.x / resolution.y;
    let st_aspect = vec2<f32>(st.x * aspect, st.y);

    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let time = u.config.x;

    // Live audio (binding 12): bass drives displacement/glow as the old
    // "audio" term did; mids tint the membrane, treble sharpens spikes.
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass;

    // Camera setup
    // HEAD fix: the camera sat at (0,0,-3), exactly inside the z-axis fibre, so every
    // pixel hit at t=0 and the frame was one flat wash. Orbit it off-axis instead.
    let orbit = time * 0.07;
    let camDir = normalize(vec3<f32>(sin(orbit) * 0.8 + 0.35, 0.45 + 0.2 * sin(orbit * 0.7), -cos(orbit) * 0.8 - 0.45));
    let ro = camDir * 3.2;
    let fwd = -camDir;
    let camR = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let camU = cross(fwd, camR);
    let rd = normalize(camR * st_aspect.x + camU * st_aspect.y + fwd * 1.5);

    // Mouse interaction - acts as an attractor point
    // The attractor sits 2 units in front of the (orbiting) camera, under the cursor.
    let mouse = u.zoom_config.yz;
    let mouse_world = ro + fwd * 2.0
        + camR * ((mouse.x - 0.5) * 2.0 * aspect * 1.3333)
        + camU * ((0.5 - mouse.y) * 2.0 * 1.3333);

    // Raymarching
    var t = 0.0;
    let max_d = 10.0;
    var d = 0.0;
    let iters = 64;
    var p = ro;

    var glow = 0.0;
    let pulse_speed = u.zoom_params.y;

    for (var i = 0; i < iters; i = i + 1) {
        p = ro + rd * t;

        // Warping space towards mouse interaction
        let dist_to_mouse = length(p - mouse_world);
        if (u.zoom_config.w > 0.5 && dist_to_mouse < 2.0) {
            let pull = (2.0 - dist_to_mouse) * 0.5;
            p = mix(p, mouse_world, pull * 0.1);
        }

        d = map(p, time, audio).x;

        // Accumulate glow based on proximity to surfaces and audio
        glow = glow + 0.01 / (0.01 + abs(d)) * (1.0 + audio * 2.0);

        if (d < 0.001 || t > max_d) {
            break;
        }
        t = t + d * 0.5; // step size factor for volumetric feel
    }

    var col = vec3<f32>(0.0);
    let hit = t < max_d;
    var spike = 0.0;
    var flare = 0.0;

    if (hit) {
        let n = getNormal(p, time, audio);
        let hitRes = map(p, time, audio);

        // Simple lighting
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let amb = 0.1;

        let bioluminescence = u.zoom_params.z;
        let pulse = sin(time * pulse_speed + length(p) * 2.0) * 0.5 + 0.5;

        // Base color based on depth and position
        let base_col = mix(vec3<f32>(0.1, 0.3, 0.5), vec3<f32>(0.6, 0.1, 0.4),
                           clamp(sin(p.z * 0.5) * 0.5 + 0.5 + mids * 0.15, 0.0, 1.0));

        // Emission color
        let emit_col = vec3<f32>(0.2, 0.8, 1.0) * bioluminescence * pulse * (1.0 + audio * 3.0);

        col = base_col * (diff + amb) + emit_col * 0.5;

        // Idea 1: action-potential spikes travel along each fibre's axis.
        // Idea 4 (entanglement phase-lock): HEAD seeds were 17 / 41 units of axial phase.
        // Same values at the default Entanglement 0.2; at 1.0 the three axons fire in lockstep.
        let seedOff = select(select(0.0, 17.0, hitRes.w > 0.5), 41.0, hitRes.w > 1.5);
        let axialP = hitRes.y + seedOff * (1.0 - u.zoom_params.w) * 1.25;
        let spikePhase = sin(axialP * 3.0 - time * pulse_speed * 2.5);
        spike = pow(max(spikePhase, 0.0), 18.0 - treble * 8.0);
        col += vec3<f32>(0.55, 0.95, 1.0) * spike * bioluminescence * (1.6 + bass);

        // Idea 3 (varicosities): the spike lights each bouton it crosses.
        let bouton = pow(0.5 + 0.5 * sin(hitRes.y * 6.0), 4.0);
        col += vec3<f32>(0.9, 0.75, 1.0) * bouton * (0.12 + 0.9 * spike) * bioluminescence * (0.5 + mids);

        // Idea 2 (Fresnel-Schlick sheath): grazing angles of the myelin membrane reflect the
        // cool sky; F0 ~ lipid/water interface.
        let ndv = clamp(dot(n, -rd), 0.0, 1.0);
        let fres = 0.06 + 0.94 * pow(1.0 - ndv, 5.0);
        col += vec3<f32>(0.35, 0.7, 1.0) * fres * (0.35 + 0.35 * mids) * (1.0 + bass * 0.5);

        // Idea 2: synaptic junction flares where fibres cross — they fire as
        // the spike train passes, tinted warmer by Entanglement.
        let arrival = pow(max(sin(-time * pulse_speed * 2.5 + axialP * 0.35), 0.0), 6.0);
        flare = hitRes.z * (0.25 + 0.75 * max(arrival, spike));
        let synCol = mix(vec3<f32>(1.0, 0.62, 0.25), vec3<f32>(1.0, 0.3, 0.75), u.zoom_params.w);
        col += synCol * flare * bioluminescence * 1.4;
    }

    // Add volumetric glow
    let bioluminescence = u.zoom_params.z;
    let glow_col = vec3<f32>(0.1, 0.5, 0.8) * glow * 0.02 * bioluminescence;
    col = col + glow_col;

    // Attenuation based on distance
    col = mix(col, vec3<f32>(0.0, 0.0, 0.05), clamp(t / max_d, 0.0, 1.0));

    // Semantic alpha: fibre coverage + spike/flare emission, volumetric glow off-surface.
    let glowA = clamp(glow * 0.012 * bioluminescence, 0.0, 0.6);
    let alpha = select(glowA + 0.02, clamp(0.55 + spike * 0.25 + flare * 0.2, 0.0, 1.0), hit);
    let display = vec4<f32>(acesToneMap(max(col, vec3<f32>(0.0))), alpha);

    let coord = vec2<i32>(global_id.xy);
    let srcDepth = textureLoad(readDepthTexture, coord, 0).r;
    let depth = select(srcDepth, clamp(1.0 - t / max_d, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, display);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, display);
}
