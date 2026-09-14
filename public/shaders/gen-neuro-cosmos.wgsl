// ═══════════════════════════════════════════════════════════════════
//  Neuro-Cosmos
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: saltatory conduction hopping between nodes of Ranvier on web strands; integrate-and-fire soma spiking with refractory afterglow per neuron
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Network Density, y=Pulse Speed, z=Glow Intensity, w=Connection Thickness
    ripples: array<vec4<f32>, 50>,
};

// 3D Hash Function
fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Voronoi Map - Returns vec3(F1, F2, CellHash)
// But we mainly need F1 and F2 for the web structure.
// F1 is distance to closest center (Neuron)
// F2 is distance to second closest center (defines Voronoi edges)
fn voronoiMap(p: vec3<f32>) -> vec3<f32> {
    var n = floor(p);
    let f = fract(p);

    var f1 = 1.0;
    var f2 = 1.0;
    var cell_id = vec3<f32>(0.0);

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + g);
                // Animate the points a bit
                var time = u.config.x * 0.1;
                let anim = 0.5 + 0.5 * sin(time + 6.2831 * o);

                let r = g + o - f;
                let d = dot(r, r);

                if (d < f1) {
                    f2 = f1;
                    f1 = d;
                    cell_id = o; // Store hash of closest cell
                } else if (d < f2) {
                    f2 = d;
                }
            }
        }
    }

    // Convert squared distances to Euclidean
    return vec3<f32>(sqrt(f1), sqrt(f2), cell_id.x);
}

// Raymarching Map function
// Returns distance to the "structure" but since this is volumetric,
// we might treat it as density field or just SDF to closest element.
// For a web, we want the space where F2 - F1 is small.
fn map(p: vec3<f32>) -> vec4<f32> {
    // Parameter: Network Density
    let scale = u.zoom_params.x * 2.0;
    let p_scaled = p * scale;

    let v = voronoiMap(p_scaled);
    var f1 = v.x;
    var f2 = v.y;
    let cell_hash = v.z;

    // Neurons are at f1 approx 0 (center of cell)
    // Synapses (Web) are where f2 - f1 approx 0 (edges)

    // Thickness parameter controls how "thick" the web is
    let thickness = u.zoom_params.w * 0.2;

    // Distance to web strand
    // f2 - f1 is distance from Voronoi boundary
    // We want to be "inside" the strand if f2 - f1 < thickness
    // So SDF = (f2 - f1) - thickness
    let d_web = (f2 - f1) - thickness;

    // Distance to neuron (cell center)
    // f1 is distance to center. Neuron radius ~ thickness * 2
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
// Returns (node flash, node mask).
fn saltatoryConduction(f1: f32, time: f32, pulseSpeed: f32, cellHash: f32) -> vec2<f32> {
    let nodeFreq = 12.0;
    let nodeCoord = f1 * nodeFreq;
    let nodeMask = smoothstep(0.16, 0.0, abs(fract(nodeCoord) - 0.5));
    // Node index advances in whole steps; each node fires, then decays while
    // the depolarization jumps down the myelinated internode.
    let wave = floor(nodeCoord) - time * pulseSpeed * 1.6 + cellHash * 5.0;
    let flash = exp(-fract(wave) * 5.0);
    return vec2<f32>(flash * nodeMask, nodeMask);
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
    for(var i=0; i<80; i++) {
        var p = camPos + rd * t;
        let data = map(p);
        var d = data.x;

        // Accumulate glow based on proximity to structure
        // The closer we are (smaller d), the more glow
        // Intensity controlled by param Z
        glow += (0.02 * glow_intensity) / (abs(d) + 0.05);

        if (d < 0.002) {
            hit = true;
            hit_data = data;
            break;
        }

        if (t > 20.0) { break; }
        t += d * 0.8; // Step size
    }

    // Base colors
    let col_neuron_core = vec3<f32>(1.0, 0.9, 0.7); // Bright warm core
    let col_neuron_outer = vec3<f32>(0.2, 0.5, 1.0); // Blue outer
    let col_synapse = vec3<f32>(0.1, 0.8, 0.9); // Cyan web
    let bg_col = vec3<f32>(0.02, 0.0, 0.05); // Deep space

    var surfaceCoverage = 0.0;
    var firing = 0.0;

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

        // Integrate-and-fire soma spiking (bass / stimulation lower threshold).
        let threshold = clamp(0.93 - bass * 0.22 - evoked * 0.3, 0.45, 0.97);
        let iaf = integrateAndFire(hash, u.config.x, threshold);
        let somaCharge = is_neuron * iaf.x * 0.25;
        firing = is_neuron * (iaf.y + iaf.z * 0.8);
        object_col = mix(object_col, col_neuron_core, somaCharge);
        object_col += vec3<f32>(1.0, 0.95, 0.85) * firing * (1.2 + treble * 0.6);

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
    col += vec3<f32>(0.25, 0.2, 0.5) * evoked * 0.25 * (1.0 - surfaceCoverage);

    // Distance fog
    let fog = 1.0 - exp(-t * 0.1);
    col = mix(col, bg_col, fog);

    col = acesToneMap(col * (1.0 + bass * 0.12));

    // Alpha: surface coverage attenuated by fog, plus volumetric glow density.
    let glowDensity = 1.0 - exp(-glow * 0.08);
    let alpha = clamp(max(surfaceCoverage * (1.0 - fog * 0.6), glowDensity * 0.8) + evoked * 0.1, 0.0, 1.0);
    let finalColor = vec4<f32>(col, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(t / 20.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
