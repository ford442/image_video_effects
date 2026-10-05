// ----------------------------------------------------------------
// Quantum Resonance Lattice
// Category: generative
// ----------------------------------------------------------------
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
    let bass = extraBuffer[0];
    let mid = extraBuffer[1];

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

            channelCol = (finalL * ambientCol[c] + sss) * ao;

            // Distance fog
            channelCol = mix(channelCol, 0.0, smoothstep(20.0, 60.0, t));
        }

        if (c == 0) { col.x = channelCol; }
        if (c == 1) { col.y = channelCol; }
        if (c == 2) { col.z = channelCol; }
    }

    // Output
    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));

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

    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, 1.0));
}
