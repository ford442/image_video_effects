// ═══════════════════════════════════════════════════════════════════
//  Quantum Resonance Lattice
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: resonant band-splitting halos around octahedral nodes; nodal-plane standing-wave sheets; probability wave interference; Planck-scale lattice dislocation
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// Helper for 3D rotation
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;

    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// SDF for Octahedron
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let p_abs = abs(p);
    return (p_abs.x + p_abs.y + p_abs.z - s) * 0.57735027;
}

// Map function returning distance and material id
fn map(p: vec3<f32>, audioReactive: f32) -> vec2<f32> {
    // Domain repetition
    let spacing = u.zoom_params.x * 2.5 + 0.5; // Node Spacing (0.5 to 3.0)
    let cell = floor(p / spacing + 0.5);
    var q = p - cell * spacing;

    // Wave disruption
    let t = u.config.x * (u.zoom_params.z * 5.0); // Travel Speed
    let amp = u.zoom_params.y * 3.0; // Wave Amplitude
    let wave = sin(cell.x * 0.5 + t) * cos(cell.z * 0.5 + t) * amp;

    // Audio disruption
    let audioWave = audioReactive * 2.0 * sin(cell.y * 1.5 - t);

    q += vec3<f32>(0.0, wave + audioWave, 0.0);
    
    // Idea 2: Planck-scale lattice dislocation
    let dislocation = step(0.9, fract(cell.y * 0.3 + t * 0.2)) * 0.15;
    q += vec3<f32>(dislocation, 0.0, -dislocation);

    // Chaos rotation
    let chaos = u.zoom_params.w;
    if (chaos > 0.0) {
       let axis = normalize(vec3<f32>(sin(cell.x*1.2), cos(cell.y*0.8), sin(cell.z*1.5)));
       q = q * rot3D(axis, t * chaos + cell.x * chaos * 5.0);
    }

    // Mouse distortion (Gravity well)
    if (u.zoom_config.w > 0.0) {
        // Map mouse uv to roughly world space bounds (assumes camera is at z=-something looking at z=0)
        // Camera is actually at ro = vec3(0,0,time) moving forward.
        // Let's create a local gravity well in front of the camera based on mouse UV.
        let camZ = u.config.x * u.zoom_params.z * 5.0;
        // Map mouse (0..1) to (-10..10)
        let mx = (u.zoom_config.y - 0.5) * 20.0;
        let my = (0.5 - u.zoom_config.z) * 20.0;

        let mouse_pos = vec3<f32>(mx, my, camZ + 15.0); // well is ahead of camera
        let dist = length(p - mouse_pos);

        let pull = exp(-dist * 0.2) * 5.0; // strength of well

        // Stretch towards mouse
        let dir = normalize(mouse_pos - p);
        q -= dir * pull;
    }

    let d = sdOctahedron(q, 0.5 + audioReactive * 0.5);
    return vec2<f32>(d, 1.0);
}

// Idea 1: local mode splitting around each octahedral node adds halo bands that
// breathe at slightly different rates (like coupled resonators splitting lines).
fn resonanceHalo(p: vec3<f32>, t: f32, spacing: f32, bass: f32, mids: f32) -> f32 {
    let cell = floor(p / spacing + 0.5);
    let q = p - cell * spacing;
    let r = length(q);
    let bandA = exp(-pow((r - 0.58) * 8.5, 2.0));
    let bandB = exp(-pow((r - 0.74) * 8.0, 2.0));
    let beat = 0.5 + 0.5 * sin(t * (3.0 + bass * 4.0) + dot(cell, vec3<f32>(1.1, 0.9, 1.3)));
    let split = 0.5 + 0.5 * sin(t * (3.35 + mids * 3.4) + dot(cell, vec3<f32>(1.7, 0.7, 1.5)));
    return (bandA * beat + bandB * split) * (0.25 + bass * 0.45);
}

// Idea 2: standing nodal sheets crossing the lattice volume.
fn nodalSheets(p: vec3<f32>, t: f32, amp: f32, treble: f32) -> f32 {
    let s = abs(sin(p.x * 1.3 + t * (0.8 + amp * 0.3)))
          * abs(sin(p.y * 1.1 - t * (0.7 + amp * 0.25)))
          * abs(sin(p.z * 1.25 + t * (0.9 + amp * 0.35)));
    let plane = smoothstep(0.97 - treble * 0.12, 1.0, s);
    return plane * (0.18 + treble * 0.3);
}

// Normal calculation
fn calcNormal(p: vec3<f32>, audioReactive: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize( e.xyy*map( p + e.xyy, audioReactive ).x +
					  e.yyx*map( p + e.yyx, audioReactive ).x +
					  e.yxy*map( p + e.yxy, audioReactive ).x +
					  e.xxx*map( p + e.xxx, audioReactive ).x );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(coord) - 0.5 * res) / res.y;

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mid = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let spacing = u.zoom_params.x * 2.5 + 0.5;
    let amp = u.zoom_params.y * 3.0;

    // Ray setup
    // Moving camera
    let camSpeed = u.zoom_params.z * 5.0;
    let ro = vec3<f32>(0.0, 0.0, u.config.x * camSpeed);

    // Camera shake from bass
    let shake = vec3<f32>(sin(u.config.x*10.0), cos(u.config.x*12.0), 0.0) * bass * 0.1;

    let rd = normalize(vec3<f32>(uv, 1.0)); // simple forward looking

    // Chromatic dispersion parameters
    let dispersion = 0.02 * (u.zoom_params.w + bass); // chaos increases dispersion
    var col = vec3<f32>(0.0);
    var sheetGlow = 0.0;

    // Render 3 channels slightly offset
    for(var c = 0; c < 3; c++) {
        var t = 0.0;
        var d = 0.0;
        var steps = 0;
        var hit = false;
        var p = vec3<f32>(0.0);

        let rd_off = normalize(rd + vec3<f32>(f32(c)*dispersion - dispersion, 0.0, 0.0));

        for (var i = 0; i < 100; i++) {
            p = ro + shake + rd_off * t;
            let res2 = map(p, bass);
            d = res2.x;
            sheetGlow += nodalSheets(p, u.config.x, amp, treble) * exp(-t * 0.03);
            if (d < 0.001) {
                hit = true;
                break;
            }
            if (t > 60.0) { break; }
            t += d * 0.8; // understep to avoid artifacts from space folding
            steps++;
        }

        var channelCol = 0.0;
        if (hit) {
            let n = calcNormal(p, bass);
            let lightDir = normalize(vec3<f32>(1.0, 1.0, -0.5));
            let diff = max(dot(n, lightDir), 0.0);

            // Ambient based on position to give colorful lattice
            let cell = floor(p / (u.zoom_params.x * 2.5 + 0.5) + 0.5);
            let ambientCol = vec3<f32>(
                sin(cell.x)*0.5+0.5,
                cos(cell.y)*0.5+0.5,
                sin(cell.z+u.config.x)*0.5+0.5
            );

            let ao = 1.0 - f32(steps) / 100.0;

            let finalL = diff * 0.8 + 0.2;

            // Subsurface scattering fake
            let sss = exp(-d * 5.0) * 0.5 * mid;
            let halo = resonanceHalo(p, u.config.x, spacing, bass, mid);

            // Idea 1: Probability wave interference
            let probInterference = 0.5 + 0.5 * sin(dot(p, vec3<f32>(1.0, 2.0, 3.0)) * 5.0 - u.config.x * 10.0);
            
            channelCol = (finalL * ambientCol[c] + sss + halo) * ao * (0.8 + 0.4 * probInterference);

            // Distance fog
            channelCol = mix(channelCol, 0.0, smoothstep(20.0, 60.0, t));
        }

        if (c == 0) { col.x = channelCol; }
        if (c == 1) { col.y = channelCol; }
        if (c == 2) { col.z = channelCol; }
    }

    col += vec3<f32>(0.35, 0.75, 1.0) * sheetGlow * 0.015;
    col = acesToneMap(col * (1.05 + bass * 0.15));
    let alpha = clamp(0.15 + dot(col, vec3<f32>(0.2126, 0.7152, 0.0722)) * 0.8 + sheetGlow * 0.01, 0.0, 0.98);

    // Output
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));

    // Depth output (using first channel hit roughly)
    var depth = 100.0;
    var t_depth = 0.0;
    for (var i = 0; i < 100; i++) {
        let p_d = ro + rd * t_depth;
        let d_d = map(p_d, bass).x;
        if (d_d < 0.001) { depth = t_depth; break; }
        if (t_depth > 60.0) { break; }
        t_depth += d_d * 0.8;
    }

    let depth01 = clamp(1.0 - depth / 60.0, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth01, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
