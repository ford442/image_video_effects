// ═══════════════════════════════════════════════════════════════════
//  Neuro-Cosmos
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14, 2026-11-21
//  Ideas: saltatory conduction hopping between nodes of Ranvier on web strands; integrate-and-fire soma spiking with refractory afterglow per neuron; activity-dependent pruning where underused web strands dim into shadow gaps; Hebbian reinforcement from feedback where repeatedly active filaments thicken into persistent bright corridors; action-potential undershoot (after-hyperpolarization) trailing each node hop; soft inverse-square somatic halo from firing somas (§12.2F)
//  Rescues: web = axon segments between neighbouring somas (HEAD drew F2-F1 foam membranes); saltatory hop now propagates node to node (HEAD's fract() erased the node index so all nodes blinked in unison, ramp-then-cut)
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Network Density, y=Pulse Speed, z=Glow Intensity, w=Connection Thickness

// 3D Hash Function
fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Voronoi seed search - the three nearest somas around p (8-cell block, below).
// r1..r3 are (seed - p) vectors in lattice space, nearest first; h is the cell
// hash of the nearest soma (stable per neuron, used for its firing phase);
// h2/h3 are the hashes of the 2nd/3rd nearest (they key which axons exist).
struct Seeds {
    r1: vec3<f32>,
    r2: vec3<f32>,
    r3: vec3<f32>,
    h: f32,
    h2: f32,
    h3: f32,
};

fn voronoiMap(p: vec3<f32>) -> Seeds {
    var n = floor(p);
    let f = fract(p);

    var d1 = 8.0;
    var d2 = 8.0;
    var d3 = 8.0;
    var r1 = vec3<f32>(0.0);
    var r2 = vec3<f32>(0.0);
    var r3 = vec3<f32>(0.0);
    var cell_id = vec3<f32>(0.0);
    var c2 = 0.0;
    var c3 = 0.0;

    // 2x2x2 block of seed cells on p's side of its cell. With the soma jitter
    // confined to [0.15, 0.85] of a cell the three nearest somas are in this block;
    // HEAD's 27-cell search cost 3.4x more per march step, and the strand lattice
    // needs ~10x more march steps than HEAD's foam (which stopped at the first wall).
    let sg = select(vec3<f32>(-1.0), vec3<f32>(1.0), f >= vec3<f32>(0.5));
    for (var k = 0; k <= 1; k++) {
        for (var j = 0; j <= 1; j++) {
            for (var i = 0; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k)) * sg;
                let o = 0.15 + 0.7 * hash33(n + g);

                let r = g + o - f;
                let d = dot(r, r);

                if (d < d1) {
                    d3 = d2; r3 = r2; c3 = c2;
                    d2 = d1; r2 = r1; c2 = cell_id.x;
                    d1 = d; r1 = r;
                    cell_id = o; // Store hash of closest cell
                } else if (d < d2) {
                    d3 = d2; r3 = r2; c3 = c2;
                    d2 = d; r2 = r; c2 = o.x;
                } else if (d < d3) {
                    d3 = d; r3 = r; c3 = o.x;
                }
            }
        }
    }

    return Seeds(r1, r2, r3, cell_id.x, c2, c3);
}

// Distance from the sample point (origin) to the axon between two somas a, b,
// both given as (seed - p) vectors. A neural net is sparse (a 3-D Delaunay graph
// would link every soma to ~15 neighbours = a thicket), so an axon only exists
// when it is short and its symmetric per-link hash survives; absent links are
// pushed away by 0.2 rather than removed so marching steps stay conservative.
fn axonDist(a: vec3<f32>, b: vec3<f32>, ha: f32, hb: f32) -> f32 {
    let ab = b - a;
    let t = clamp(-dot(a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    let dseg = length(a + ab * t);
    let link = fract((ha + hb) * 91.3 + ha * hb * 37.7);
    let present = (link < 0.5) && (length(ab) < 1.15);
    return dseg + select(0.2, 0.0, present);
}

// Raymarching Map function
// Returns distance to the "structure" but since this is volumetric,
// we might treat it as density field or just SDF to closest element.
// Somas sit at the Voronoi seeds; strands are the axons joining each soma to
// its neighbours (segments from the nearest seed to the 2nd and 3rd nearest), so
// f1 is the true distance along a strand away from the nearest soma.
fn map(p: vec3<f32>) -> vec4<f32> {
    // Parameter: Network Density
    let scale = u.zoom_params.x * 2.0;
    let p_scaled = p * scale;

    let v = voronoiMap(p_scaled);
    let f1 = length(v.r1);
    let f2 = length(v.r2);
    let cell_hash = v.h;

    // Neurons are at f1 approx 0 (the seed); the web is the set of axons.

    // Thickness parameter controls how "thick" the web is
    let thickness = u.zoom_params.w * 0.2;

    // ── Rescue R1: strands are 1-D axon segments between neighbouring somas.
    // HEAD used F2-F1 (the 2-D Voronoi bisector), i.e. foam membranes: the
    // camera saw giant flat sheets and the somas floated disconnected inside
    // cells. A 1-D strand needs a thicker radius than a 2-D sheet to be seen,
    // so the radius multiplier is 1.5x (slider role unchanged).
    let d_web = min(axonDist(v.r1, v.r2, v.h, v.h2), axonDist(v.r1, v.r3, v.h, v.h3)) - thickness * 1.5;

    // Distance to neuron (cell center)
    // f1 is distance to center. Neuron radius ~ thickness * 3
    let neuron_radius = thickness * 3.0;
    let d_neuron = f1 - neuron_radius;

    // Combine web and neuron (smooth union)
    var k = 0.1;
    let h = clamp(0.5 + 0.5 * (d_web - d_neuron) / k, 0.0, 1.0);
    let d = mix(d_web, d_neuron, h) - k * h * (1.0 - h);

    // Return distance and cell hash for coloring
    return vec4<f32>(d / scale, cell_hash, f1, f2);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    var d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Native idea 1: saltatory conduction. Myelinated strands only conduct at
// the nodes of Ranvier, so the action potential hops node-to-node instead of
// sliding smoothly. f1 parametrizes position along a strand away from the soma.
// Returns (node flash, node mask, after-hyperpolarization undershoot).
fn saltatoryConduction(f1: f32, time: f32, pulseSpeed: f32, cellHash: f32) -> vec3<f32> {
    let nodeFreq = 12.0;
    let nodeCoord = f1 * nodeFreq;
    let nodeMask = smoothstep(0.16, 0.0, abs(fract(nodeCoord) - 0.5));
    // Rescue: HEAD used fract(floor(nodeCoord) - time*speed + hash*5). fract()
    // drops the integer node index, so every node of a soma's strands flashed in
    // unison (no hop), and exp(-fract(wave)*5) rose slowly then cut to zero (the
    // reverse of a spike). Each node now fires HOP of a period after the previous
    // one (outward from the soma) and the flash is abrupt-then-decaying.
    let HOP = 0.18;
    let age = fract(time * pulseSpeed * 1.6 + cellHash * 5.0 - floor(nodeCoord) * HOP);
    let flash = exp(-age * 5.0);
    // ── Idea 1: action-potential undershoot (after-hyperpolarization). Behind the
    // spike the membrane overshoots below rest and the node is refractory: a dim,
    // cool trailing zone (age 0.3..0.9) that recovers before the node can fire again.
    let ahp = smoothstep(0.3, 0.45, age) * (1.0 - smoothstep(0.6, 0.95, age));
    return vec3<f32>(flash * nodeMask, nodeMask, ahp);
}

// Native idea 2: integrate-and-fire soma. Each neuron (cell hash) charges its
// membrane potential linearly; when it crosses threshold it spikes, resets and
// glows through a refractory afterglow. Bass lowers the firing threshold.
// Returns (charge, spike, refractory glow).
fn integrateAndFire(cellHash: f32, time: f32, threshold: f32) -> vec3<f32> {
    let rate = 0.22 + cellHash * 0.35;
    let potential = fract(time * rate + cellHash * 7.31);
    let spike = smoothstep(threshold, 1.0, potential);
    let refractory = exp(-potential * 14.0);
    return vec3<f32>(potential, spike, refractory);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let uv01 = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);

    // Audio (plasmaBuffer[0] only)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Camera Control
    var mouse = u.zoom_config.yz; // 0..1
    let mouseDown = u.zoom_config.w;

    // Orbit camera
    let yaw = (mouse.x - 0.5) * 6.28;
    let pitch = ((mouse.y - 0.5)) * 3.14;
    let dist = 5.0; // Orbit distance

    // Drifting camera motion
    var time = u.config.x * 0.1;
    let camPos = vec3<f32>(
        dist * sin(yaw + time) * cos(pitch),
        dist * sin(pitch) + sin(time * 0.5),
        dist * cos(yaw + time) * cos(pitch)
    );

    let target_pos = vec3<f32>(0.0, 0.0, 0.0);
    let forward = normalize(target_pos - camPos);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Evoked stimulation: click ripples are electrode pulses that launch an
    // expanding depolarization front; holding the mouse is a sustained
    // stimulating electrode at the cursor.
    var evoked = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = u.config.x - rp.z;
        if (age >= 0.0 && age < 2.5) {
            let dv = (uv01 - rp.xy) * vec2<f32>(aspect, 1.0);
            let front = length(dv) - age * 0.5;
            evoked += exp(-front * front * 220.0) * exp(-age * 1.3);
        }
    }
    let md = (uv01 - mouse) * vec2<f32>(aspect, 1.0);
    let electrode = step(0.5, mouseDown) * exp(-dot(md, md) * 40.0);
    evoked = min(evoked + electrode * 0.8, 2.0);

    // Raymarching
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;
    var hit = false;
    var hit_data = vec4<f32>(0.0);

    // Volumetric march
    let glow_intensity = u.zoom_params.z * (1.0 + bass * 0.4);
    // Firing threshold (bass / stimulation lower it) — hoisted so the march can
    // read each soma's spike state for the somatic halo (Idea 2).
    let threshold = clamp(0.93 - bass * 0.22 - evoked * 0.3, 0.45, 0.97);
    let sceneScale = max(u.zoom_params.x * 2.0, 1e-3);
    var halo = 0.0;
    for(var i=0; i<48; i++) {
        var p = camPos + rd * t;
        let data = map(p);
        var d = data.x;
        // Near-clip bubble: the camera sits inside an open lattice now, so a strand
        // grazing the lens would fill the frame as a giant tube.
        d = max(d, 0.45 - t);
        let stepLen = clamp(d * 0.85, 0.02, 0.5);

        // Accumulate glow based on proximity to structure
        // The closer we are (smaller d), the more glow
        // Intensity controlled by param Z. Weighted by the step length: with strands
        // (not foam) the ray crosses open space and takes many more, smaller steps.
        glow += (0.02 * glow_intensity) * (stepLen * 4.0) / (abs(d) + 0.05);

        // ── Idea 2: soft inverse-square somatic halo (§12.2F). map() already hands
        // back the nearest-soma distance and its cell hash every step; a soma that
        // is firing (same integrate-and-fire state as the surface) lights the haze
        // around it as I/(r^2 + r0^2) with a soft core r0 — an extracellular field
        // you can see from across the volume, integrated along the ray (ds = step).
        let somaR = data.z / sceneScale;
        let iafM = integrateAndFire(data.y, u.config.x, threshold);
        halo += (iafM.y + iafM.z * 0.8) * (0.022 * glow_intensity) * stepLen / (somaR * somaR + 0.012);

        if (d < max(0.002, t * 0.7 / resolution.y)) {
            hit = true;
            hit_data = data;
            break;
        }

        if (t > 9.0) { break; }
        t += stepLen; // Step size
    }

    // Base colors
    let col_neuron_core = vec3<f32>(1.0, 0.9, 0.7); // Bright warm core
    let col_neuron_outer = vec3<f32>(0.2, 0.5, 1.0); // Blue outer
    let col_synapse = vec3<f32>(0.1, 0.8, 0.9); // Cyan web
    let bg_col = vec3<f32>(0.02, 0.0, 0.05); // Deep space
    let prevFrame = textureLoad(dataTextureC, coord, 0);

    var surfaceCoverage = 0.0;
    var firing = 0.0;
    var reinforce = 0.0;

    if (hit) {
        var p = camPos + rd * t;
        var n = calcNormal(p);

        var f1 = hit_data.z;
        var f2 = hit_data.w;
        let hash = hit_data.y;

        // Lighting
        let lightPos = vec3<f32>(2.0, 5.0, 2.0);
        let lightDir = normalize(lightPos - p);
        let diff = max(dot(n, lightDir), 0.2);

        // Pulse animation
        // Pulse travels along strands based on distance from center (f1)
        let pulse_speed = u.zoom_params.y * 5.0;
        let pulse = sin(f1 * 10.0 - u.config.x * pulse_speed);
        let pulse_strength = smoothstep(0.8, 1.0, pulse) * (1.0 + mids * 0.4);

        // Determine if Neuron or Web
        // Based on f1 value (small f1 = closer to center)
        let is_neuron = smoothstep(0.2, 0.0, f1);

        var object_col = mix(col_synapse, col_neuron_outer, is_neuron);

        // Add core glow to neuron
        object_col = mix(object_col, col_neuron_core, is_neuron * smoothstep(0.1, 0.0, f1));

        // Saltatory conduction: smooth pulse persists dimly on the myelin,
        // while nodes of Ranvier flash in discrete hops.
        let salt = saltatoryConduction(f1, u.config.x, u.zoom_params.y, hash);
        let web = 1.0 - is_neuron;
        object_col += col_synapse * pulse_strength * web * mix(0.55, 1.0, salt.y);
        object_col += vec3<f32>(0.55, 1.0, 0.95) * salt.x * web * (0.6 + mids * 0.4 + evoked * 0.8);
        // Idea 1 lands here: hyperpolarized trailing zone is dimmer and cooler.
        object_col = mix(object_col, object_col * vec3<f32>(0.55, 0.62, 0.9), salt.z * web * (1.0 - salt.x) * 0.8);

        // Integrate-and-fire soma spiking (bass / stimulation lower threshold).
        let iaf = integrateAndFire(hash, u.config.x, threshold);
        let somaCharge = is_neuron * iaf.x * 0.25;
        firing = is_neuron * (iaf.y + iaf.z * 0.8);
        object_col = mix(object_col, col_neuron_core, somaCharge);
        object_col += vec3<f32>(1.0, 0.95, 0.85) * firing * (1.2 + treble * 0.6);
        // IDEA 3: pruning shadows — chronically weak strands lose conductivity.
        let activity = pulse_strength * web + salt.x + firing + evoked * 0.4;
        let prune = smoothstep(0.22, 0.02, activity) * web;
        object_col = mix(object_col, object_col * 0.45, prune * 0.7);
        object_col += vec3<f32>(0.45, 0.2, 0.9) * prune * 0.08;
        // IDEA 4: Hebbian reinforcement keeps repeatedly active strands luminous.
        reinforce = clamp(prevFrame.a * 0.6 + activity * 0.3, 0.0, 1.0);

        col = object_col * diff;

        // Evoked depolarization front lights up whatever it crosses.
        col += vec3<f32>(0.9, 0.7, 1.0) * evoked * 0.6;

        // Rim lighting for 3D feel
        let rim = 1.0 - max(dot(n, -rd), 0.0);
        col += vec3<f32>(0.2, 0.4, 1.0) * pow(rim, 3.0) * (1.0 + treble * 0.5);

        surfaceCoverage = clamp(0.7 + (1.0 - rim) * 0.2 + firing * 0.1, 0.0, 1.0);
    } else {
        col = bg_col;
    }

    // Apply volumetric glow
    // Glow color changes slightly based on view direction or time
    let glow_col = vec3<f32>(0.1, 0.2, 0.5) + vec3<f32>(0.1, 0.0, 0.2) * sin(u.config.x);
    col += glow * glow_col;
    col += vec3<f32>(1.0, 0.82, 0.6) * halo;
    col += vec3<f32>(0.25, 0.2, 0.5) * evoked * 0.25 * (1.0 - surfaceCoverage);
    col = mix(col, max(col, prevFrame.rgb * 0.95), reinforce * 0.22);

    // Distance fog
    let fog = 1.0 - exp(-t * 0.1);
    col = mix(col, bg_col, fog);

    col = acesToneMap(col * (1.0 + bass * 0.12));

    // Alpha: surface coverage attenuated by fog, plus volumetric glow density.
    let glowDensity = 1.0 - exp(-(glow + halo * 6.0) * 0.08);
    let alpha = clamp(max(surfaceCoverage * (1.0 - fog * 0.6), glowDensity * 0.8) + evoked * 0.1 + reinforce * 0.12, 0.0, 1.0);
    let finalColor = vec4<f32>(col, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(t / 20.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
