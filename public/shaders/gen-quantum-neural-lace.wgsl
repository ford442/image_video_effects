// ═══════════════════════════════════════════════════════════════════
//  Quantum Neural Lace
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27, 2026-10-25
//  Ideas: per-node stochastic firing with refractory decay; nodes of Ranvier (saltatory packets); conducted spike hopping outward from the firing node one internode per step (§12.1 t2/t7); soft inverse-square soma spill on neighbouring strands (§12.2F)
//  HEAD fixes: eye sat on the z-axis inside a strand cylinder (every ray hit at t=0 -> blank white); camera basis was rotated 180 degrees; key light came from behind the lattice
//  A packing: HDR trail RGB (pre-ACES, read back from C), alpha = coverage
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Lattice Density, y=Pulse Speed, z=Fiber Chaos, w=Energy Level

// --- SDF Primitives ---

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let p_abs = abs(p);
    return (p_abs.x + p_abs.y + p_abs.z - s) * 0.57735027;
}

// --- Helper Functions ---

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash31(p: vec3<f32>) -> f32 {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q = q + dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Per-node firing clock, shared by the node flash and the conducted spike so
// both read the same phase. Returns (phase since last fire, rate, node fires?).
fn fireClock(seed: f32, time: f32, pulseSpeed: f32, bass: f32) -> vec3<f32> {
    let fireRate = 0.25 + pulseSpeed * 0.9 + bass * 0.35;
    let rate = fireRate * (0.7 + seed * 0.6);
    let ph = fract(time * rate + seed * 7.13);
    let on = step(0.3, fract(seed * 13.7));
    return vec3<f32>(ph, rate, on);
}

fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// --- Map Function ---

fn map(p: vec3<f32>) -> vec2<f32> {
    // Parameters
    let density = mix(2.0, 6.0, u.zoom_params.x); // Node spacing
    let distortion = u.zoom_params.z;             // Sine wave amplitude

    // 1. Domain Repetition
    let cell_size = 8.0 / density;
    let half_cell = cell_size * 0.5;

    let id = floor((p + half_cell) / cell_size);
    let local_p = (fract((p + half_cell) / cell_size) - 0.5) * cell_size;

    // 2. Nodes (Octahedrons)
    let node_size = cell_size * 0.15;
    // Rotate octahedron slightly over time for dynamic feel
    var p_rot = local_p;
    let temp_p_rot_xz = rotate2D(p_rot.xz, u.config.x * 0.5);
    p_rot.x = temp_p_rot_xz.x;
    p_rot.z = temp_p_rot_xz.y;

    let temp_p_rot_xy = rotate2D(p_rot.xy, u.config.x * 0.3);
    p_rot.x = temp_p_rot_xy.x;
    p_rot.y = temp_p_rot_xy.y;


    let d_node = sdOctahedron(p_rot, node_size);

    // 3. Strands (Connecting Cylinders)
    // We need connections along X, Y, Z axes to neighbors.
    // In a simple repetition, the "connections" are just infinite cylinders passing through the centers?
    // No, standard opRep makes localized objects.
    // To connect them, we can place cylinders that span the cell.

    // Axis X cylinder
    // Add distortion
    let wave = sin(p.z * 2.0 + u.config.x) * distortion * 0.2;
    let d_axis_x = length(local_p.yz + vec2<f32>(wave, 0.0));
    let d_axis_y = length(local_p.xz);
    let d_axis_z = length(local_p.xy);

    // Idea 2: nodes of Ranvier — myelin segments along each strand's axis,
    // separated by narrow constricted gaps.
    var axial = local_p.x;
    if (d_axis_y < d_axis_x && d_axis_y <= d_axis_z) { axial = local_p.y; }
    if (d_axis_z < d_axis_x && d_axis_z < d_axis_y) { axial = local_p.z; }
    let segPhase = fract(axial / cell_size * 4.0);
    let gap = 1.0 - smoothstep(0.0, 0.07, min(segPhase, 1.0 - segPhase));
    let strandR = node_size * 0.3 * (1.0 - gap * 0.35);

    let d_cyl_x = d_axis_x - strandR;
    let d_cyl_y = d_axis_y - strandR;
    let d_cyl_z = d_axis_z - strandR;

    // Union cylinders
    let d_strands = min(d_cyl_x, min(d_cyl_y, d_cyl_z));

    // Smooth blend nodes and strands
    let d_struct = smin(d_node, d_strands, 0.2);

    // Material: [1, 1.5] = strand (fraction = Ranvier gap),
    //           [2, 3)   = node   (fraction = per-cell firing seed from `id`).
    let mat = select(1.0 + gap * 0.5, 2.0 + hash31(id) * 0.99, d_node < d_strands);

    return vec2<f32>(d_struct, mat);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    var d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var mat = 0.0;
    for(var i=0; i<128; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        mat = res.y;
        if(d < 0.001 || t > 100.0) { break; }
        t += d;
    }
    return vec2<f32>(t, mat);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let pixel = vec2<i32>(global_id.xy);
    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    uv.y = -uv.y; // pixel y runs down; world up is +y

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var mouse = u.zoom_config.yz;
    let time = u.config.x;
    let pulseSpeed = u.zoom_params.y;
    let glowIntensity = u.zoom_params.w;
    let warpT = time + 0.35 * sin(time * 0.37);

    // Orbit controls
    let radius = 8.0;
    let yaw = (mouse.x - 0.5) * 6.28;
    let pitch = (mouse.y - 0.5) * 3.14;
    let safe_pitch = clamp(pitch, -1.5, 1.5);

    let cam_pos = vec3<f32>(
        radius * cos(safe_pitch) * sin(yaw),
        radius * sin(safe_pitch),
        radius * cos(safe_pitch) * cos(yaw)
    );

    // Warp-flight through the lattice — closed-form forward conveyor.
    let forward_speed = 1.8 + pulseSpeed * 2.5 + bass * 1.2;
    let cam_offset = vec3<f32>(0.0, 0.0, warpT * forward_speed);

    // Fly in the free corridor between strands: strands run along each cell's
    // axes through its centre, so an eye on those axes starts inside a cylinder.
    let cellSize = 8.0 / mix(2.0, 6.0, u.zoom_params.x);
    let anchor = cam_offset + vec3<f32>(0.36 * cellSize, 0.3 * cellSize, 0.0);

    let ro = cam_pos + anchor;
    let target_pos = anchor;
    let forward = normalize(target_pos - ro);
    let right = normalize(cross(forward, vec3<f32>(0.0, 1.0, 0.0)));
    let up = cross(right, forward);
    let rd = normalize(forward + right * uv.x + up * uv.y);

    var res = raymarch(ro, rd);
    var t = res.x;
    var color = vec3<f32>(0.0);
    let bg_color = vec3<f32>(0.0, 0.02, 0.05);

    if (t < 100.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);
        let mat = res.y;
        let isNode = mat >= 2.0;
        let gapMask = select(clamp((mat - 1.0) * 2.0, 0.0, 1.0), 0.0, isNode);

        let light_dir = normalize(vec3<f32>(0.5, 0.8, 0.5));
        let diff = max(dot(n, light_dir), 0.0);
        let view_dir = normalize(ro - p);
        let halfway = normalize(light_dir + view_dir);
        let spec = pow(max(dot(n, halfway), 0.0), 32.0);

        let base_col = vec3<f32>(0.1, 0.15, 0.2);
        let pulse_wave_speed = pulseSpeed * 7.0 + mids * 2.0;
        let pulse_wave = sin(length(p) * 0.5 - warpT * pulse_wave_speed);
        let pulse_mask = smoothstep(0.75, 1.0, pulse_wave);

        // Traveling pulse packets along fiber direction.
        let packetPhase = sin(dot(p, vec3<f32>(1.0, 0.3, 0.7)) * 2.0 - warpT * (6.0 + pulseSpeed * 8.0));
        // Saltatory conduction: packets only light up at the Ranvier gaps on strands.
        let packet = pow(max(packetPhase, 0.0), 10.0) * 2.5 * select(0.2 + 0.8 * gapMask, 1.0, isNode);

        let glow_col = vec3<f32>(0.0, 0.8, 1.0);
        color = base_col * (diff * 0.5 + 0.1) + vec3<f32>(spec);
        color += glow_col * (pow(pulse_mask, 8.0) * 2.0 + packet) * glowIntensity * (1.0 + treble * 0.5);

        // Gap rings glow faintly even between packets.
        color += glow_col * gapMask * 0.25 * glowIntensity;

        // Idea 1: each node fires on its own clock — sharp flash, then an
        // exponential refractory decay; bass quickens the firing rate.
        if (isNode) {
            let seed = fract(mat);
            let fc = fireClock(seed, time, pulseSpeed, bass);
            let fire = exp(-fc.x * 9.0) * fc.z;
            color += mix(vec3<f32>(0.6, 0.9, 1.0), vec3<f32>(1.0, 0.85, 0.6), seed) * fire * 3.0 * (0.4 + glowIntensity);
        }

        // The cell this surface point belongs to, and its soma's firing clock.
        // Same seed/phase as the node flash above (seed = hash31(id) * 0.99).
        let cellHalf = 4.0 / mix(2.0, 6.0, u.zoom_params.x);
        let cellSz = cellHalf * 2.0;
        let cellId = floor((p + cellHalf) / cellSz);
        let lp = (fract((p + cellHalf) / cellSz) - 0.5) * cellSz;
        let somaClock = fireClock(hash31(cellId) * 0.99, time, pulseSpeed, bass);
        let somaFire = exp(-somaClock.x * 9.0) * somaClock.z;

        // ── Idea 3: conducted spike (§12.1 t2/t7). The firing soma launches an
        // action potential outward along ITS strands, one Ranvier internode per
        // step (saltatory), brightest at the front and fading behind it.
        let radial = vec3<f32>(length(lp.yz), length(lp.xz), length(lp.xy));
        let axisX = radial.x <= radial.y && radial.x <= radial.z;
        let axisY = !axisX && radial.y <= radial.z;
        let axial = select(select(lp.z, lp.y, axisY), lp.x, axisX);
        let segLen = cellSz * 0.25;                       // matches the 4-per-cell Ranvier banding
        let segIdx = floor(abs(axial) / segLen);
        let frontIdx = floor(somaClock.x * 8.0);          // front reaches the cell edge at phase 0.25
        let behindFront = frontIdx - segIdx;
        let conduct = somaClock.z * select(1.0, 0.0, isNode) * step(0.0, behindFront)
                    * exp(-max(behindFront, 0.0) * 0.9) * exp(-somaClock.x * 3.5);
        color += vec3<f32>(0.7, 1.0, 1.0) * conduct * 2.2 * (0.4 + glowIntensity) * (1.0 + treble * 0.5);

        // ── Idea 4: soft inverse-square soma spill (§12.2F). The firing soma
        // is a point source with a core radius r0, so strands and the node
        // body near it brighten as r0²/(d²+r0²) — no singularity at the core.
        let r0 = cellSz * 0.12;
        let spill = somaFire * (r0 * r0) / (dot(lp, lp) + r0 * r0);
        color += vec3<f32>(1.0, 0.85, 0.55) * spill * 1.2 * (0.4 + glowIntensity);

        let rim = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);
        color += vec3<f32>(0.5, 0.0, 0.8) * rim * 0.5;

        let fog_amount = 1.0 - exp(-t * 0.08);
        color = mix(color, bg_color, fog_amount);
    } else {
        color = bg_color;
    }

    color = clamp(color, vec3<f32>(0.0), vec3<f32>(4.0));

    // Advected HDR lattice trails.
    let histCoord = clamp(pixel - vec2<i32>(vec2<f32>(cos(warpT * 0.6), sin(warpT * 0.55)) * (2.0 + pulseSpeed * 3.0)),
                          vec2<i32>(0), vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1));
    let prev = textureLoad(dataTextureC, histCoord, 0).rgb;
    // Leaky integrator: steady-state gain = inject / (1 - decay). HEAD injected the
    // full colour (gain ~6.9x) which saturated every lit surface once the lattice
    // actually rendered; inject 0.22 keeps the trails at ~1.5x.
    let trailDecay = 0.83 + pulseSpeed * 0.05;
    let temporal = clamp(color * 0.22 + prev * trailDecay, vec3<f32>(0.0), vec3<f32>(5.5));

    let depth = select(1.0, clamp(t / 100.0, 0.05, 0.98), t < 100.0);
    let alpha = clamp(length(temporal) * 0.9 + 0.1, 0.1, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(temporal), alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(temporal, alpha));
}
