// ═══════════════════════════════════════════════════════════════════
//  Cybernetic Crystalline Neuro-Lattice
//  Category: generative
//  Features: raymarched, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: nucleation front (outgoing spherical freezing shells convert the gyroid melt into IFS crystal nodes through the existing smooth blend, bright frost rim at the front); memory-crystal bit states (each lattice cell's crystal is a stored bit that Glitch flips on/off, off = dim smoky node, write glint on flip); light-piped links (magenta gyroid links glow with the node colour by proximity to lit, frozen, on-bit crystals)
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read back exactly as HDR history
// ═══════════════════════════════════════════════════════════════════
// --- COPY PASTE THIS HEADER ---
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Node Density, .y = Growth Speed, .z = Glitch Intensity, .w = Neon Hue Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Rotate 3D space
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

// Organic gyroid base
fn sdGyroid(p: vec3<f32>, scale: f32) -> f32 {
    let q = p * scale;
    return abs(dot(sin(q), cos(q.zxy)) / scale) - 0.05;
}

// Crystalline IFS folding
fn ifsCrystals(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    for (var i = 0; i < 4; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.5, 0.5);
        p = rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), PI * 0.25) * p;
        p = abs(p) - vec3<f32>(0.2, 0.2, 0.2);
    }
    return p;
}

// Neon hue rotation about the grey axis (Rodrigues).
// FIX: HEAD's parallel term used (1,1,1)/3 * dot(k, v) with k = (1,1,1)/sqrt(3), i.e. k(k.v)/sqrt(3);
// the correct term is k * dot(k, v). Identical at hue 0; now links rotate with the nodes.
fn hueRotate(col: vec3<f32>, angle: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 1.0, 1.0) / sqrt(3.0);
    return col * cos(angle) + cross(k, col) * sin(angle) + k * dot(k, col) * (1.0 - cos(angle));
}

// Integer hash (PCG) for per-cell bit states.
fn pcg(x: u32) -> u32 {
    let v = x * 747796405u + 2891336453u;
    let w = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
    return (w >> 22u) ^ w;
}

fn hashCell(cell: vec3<f32>, s: f32) -> f32 {
    let ic = vec3<i32>(cell);
    let h = pcg(bitcast<u32>(ic.x) ^ pcg(bitcast<u32>(ic.y) ^ pcg(bitcast<u32>(ic.z) ^ pcg(bitcast<u32>(i32(s))))));
    return f32(h) * (1.0 / 4294967295.0);
}

struct Lattice {
    q: vec3<f32>,     // centred local coordinate inside the repeated cell
    cell: vec3<f32>,  // integer cell index
    r: f32,           // distance from the lattice origin (rotation-invariant)
};

// Mouse bend + slow rotation + domain repetition (shared by the SDF and the shading).
fn latticeSpace(p_in: vec3<f32>) -> Lattice {
    var p = p_in;

    // Mouse Interaction: localized data surge/bending.
    // FIX: the image is now upright (uv.y up), so the cursor maps to world +y up; the surge is centred on the
    // cursor ray at the depth where the lattice is actually seen (HEAD centred it on z=0, ~6 units behind every
    // visible surface, so the bend never showed).
    let res = u.config.zw;
    let aspect = res.x / max(res.y, 1.0);
    let mouse = u.zoom_config.yz; // (0..1, 0..1), y=0 top
    let mouse_dir = normalize(vec3<f32>((mouse.x - 0.5) * aspect, 0.5 - mouse.y, 1.0));
    let mouse_pos = vec3<f32>(0.0, 0.0, -8.0) + mouse_dir * 3.0;

    let to_mouse = p - mouse_pos;
    let dist_to_mouse = length(to_mouse);
    let bend_factor = (1.0 - smoothstep(0.0, 5.0, dist_to_mouse)) * 1.5;

    if (u.zoom_config.w > 0.0) { // mouse down
        p = p + (to_mouse / max(dist_to_mouse, 1e-4)) * sin(u.config.x * 20.0 - dist_to_mouse * 5.0) * 0.2 * bend_factor;
    }

    // FIX: no audio jitter on the rotation phase (HEAD added mids to time).
    let time = u.config.x;
    let growthSpeed = u.zoom_params.y; // 0.0 to 1.0

    // Rotate overall structure slowly
    p = rot3D(normalize(vec3<f32>(0.2, 0.8, 0.5)), time * growthSpeed) * p;

    // Infinite domain repetition.
    // FIX: treble no longer rescales the cell (distant cells swam); centred repetition instead of float %,
    // which keeps the dividend's sign and put seams on the x/y/z = 0 planes.
    let density = u.zoom_params.x * 5.0 + 1.0; // 1.5 to 6.0
    let cell_size = 8.0 / density;
    let cell = floor(p / cell_size + 0.5);

    var o: Lattice;
    o.q = p - cell_size * cell;
    o.cell = cell;
    o.r = length(p);
    return o;
}

// Idea 1: nucleation front. Outgoing spherical freezing shells (wavelength 6, rate from Growth Speed) sweep out
// from the lattice origin. x = frozen fraction (snaps to 1 just behind the front, slowly re-melts late in the
// cycle), y = frost rim glow at the front.
fn nucleationFront(r: f32) -> vec2<f32> {
    let wavelength = 6.0;
    let rate = 0.04 + u.zoom_params.y * 0.2;
    let s = fract(u.config.x * rate - r / wavelength);
    let frozen = smoothstep(0.0, 0.08, s) * (1.0 - smoothstep(0.6, 1.0, s));
    let rim = exp(-s * wavelength * 5.0) + 0.35 * exp(-(1.0 - s) * wavelength * 10.0);
    return vec2<f32>(frozen, rim);
}

// Idea 2: memory-crystal bit states. Each cell's crystal holds a bit that is rewritten once per (per-cell
// desynchronised) time slice; Glitch Intensity sets both the write rate and the probability of a 0-bit.
// Glitch 0 = every bit stays 1 (HEAD state). x = bit level (eased over the first quarter slice), y = write glint.
fn cellBit(cell: vec3<f32>) -> vec2<f32> {
    let g = u.zoom_params.z;
    let rate = 0.4 + g * 2.6;
    let ph = u.config.x * rate + hashCell(cell, -7.0) * 8.0;
    let slice = floor(ph);
    let f = ph - slice;
    let pOff = g * 0.5;
    let now = select(1.0, 0.0, hashCell(cell, slice) < pOff);
    let before = select(1.0, 0.0, hashCell(cell, slice - 1.0) < pOff);
    let level = mix(before, now, smoothstep(0.0, 0.25, f));
    let glint = abs(now - before) * (1.0 - smoothstep(0.0, 0.25, f));
    return vec2<f32>(level, glint);
}

// Main SDF: x = distance, y = material (0 crystal .. 1 gyroid), z = crystal distance (for the light pipes)
fn mapFull(p_in: vec3<f32>) -> vec3<f32> {
    let L = latticeSpace(p_in);
    let q = L.q;

    // Audio reactivity uses the engine's three-band regional envelope.
    let audio = plasmaBuffer[0].xyz;
    let time = u.config.x;

    // Crystalline details
    let c = ifsCrystals(q);

    // Gyroid network
    let d_gyroid = sdGyroid(q, 1.5 + sin(time) * 0.5 + audio.x * 0.35);

    // Box SDF for the crystals.
    // FIX: after the 4 IFS folds every component of c lies in about [-0.09, 0.41], so HEAD's 0.3 half-box was
    // inside ~96% of space: d_crystal == -0.05 everywhere, the camera started inside, map was flat there and the
    // normal was normalize(0) = NaN -> a blank frame. 0.1 leaves discrete nodes (~5% fill).
    var d_crystal = length(max(abs(c) - vec3<f32>(0.1, 0.1, 0.1), vec3<f32>(0.0))) - 0.05;

    // Idea 1: ahead of the freezing front the crystals are melted back into the gyroid (only seed specks stay),
    // behind it they nucleate; the existing smooth blend below does the melt <-> crystal fusion.
    let front = nucleationFront(L.r);
    d_crystal += (1.0 - front.x) * 0.13;
    // Idea 2: a 0-bit cell's crystal contracts slightly (and goes dark in the shading).
    let bit = cellBit(L.cell);
    d_crystal += (1.0 - bit.x) * 0.05;

    // Smoothmin between organic network and crystals
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (d_gyroid - d_crystal) / k, 0.0, 1.0);
    let d_combined = mix(d_gyroid, d_crystal, h) - k * h * (1.0 - h);

    // Material ID: 0.0 for crystal/nodes, 1.0 for gyroid connections
    let mat = mix(1.0, 0.0, h);

    // FIX: the camera sits inside the infinite lattice; carve a 0.6 near-clip bubble around it so a ray never
    // starts inside a surface (HEAD returned t = 0 "hits" for the whole screen).
    let d = max(d_combined * 0.5, 0.6 - length(p_in - vec3<f32>(0.0, 0.0, -8.0)));

    return vec3<f32>(d, mat, d_crystal);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    return mapFull(p).xy;
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ) + vec3<f32>(0.0, 1e-7, 0.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    // FIX: world +y is up (HEAD rendered upside down relative to the mouse mapping).
    let uv = vec2<f32>(f32(id.x) - 0.5 * resolution.x, 0.5 * resolution.y - f32(id.y)) / resolution.y;
    let uv01 = (vec2<f32>(id.xy) + vec2<f32>(0.5)) / resolution;
    let audio = plasmaBuffer[0].xyz;

    let ro = vec3<f32>(0.0, 0.0, -8.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat = 0.0;
    var d = 0.0;

    // Raymarching
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        mat = res.y;

        if (d < 0.001 || t > 30.0) { break; }
        t += d;
    }

    // FIX: an exhausted march far from any surface is a miss, not a hit.
    let hit = t < 30.0 && d < 0.01;

    var col = vec3<f32>(0.02, 0.02, 0.04); // Dark obsidian background
    let glitch = u.zoom_params.z; // 0.0 to 1.0
    let hueShift = u.zoom_params.w * PI * 2.0; // 0.0 to 2PI

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;
        let r = reflect(rd, n);

        // Basic lighting
        let l1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let l2 = normalize(vec3<f32>(-1.0, -0.5, -2.0));

        let diff1 = max(dot(n, l1), 0.0);
        let diff2 = max(dot(n, l2), 0.0);
        let spec = pow(max(dot(r, l1), 0.0), 32.0);

        let lat = latticeSpace(p);
        let front = nucleationFront(lat.r);
        let bit = cellBit(lat.cell);
        let d_crystal = mapFull(p).z;

        // Nodes (Crystal) neon: cyan base, hue rotated
        let neonCol = hueRotate(vec3<f32>(0.0, 1.0, 1.0), hueShift);

        // Base color
        var baseCol = vec3<f32>(0.05, 0.05, 0.05); // Obsidian

        // Neon emission
        if (mat < 0.5) {
            // Subsurface scattering / glow effect based on depth & time
            let sss = smoothstep(0.0, 1.0, map(p + n * 0.1).x * 10.0);
            let emission = (1.0 - sss) * (2.0 + audio.z * 1.5);

            // Idea 2: a 0-bit node is dark smoky quartz; a freshly written bit flashes white.
            let bitGain = mix(0.12, 1.0, bit.x);
            baseCol = mix(baseCol, neonCol * bitGain, 0.8) + neonCol * emission * bitGain + vec3<f32>(1.2) * bit.y;
        } else {
            // Gyroid connections
            let t_val = u.config.x * 2.0 + length(p) * 2.0;
            let pulse = sin(t_val) * 0.5 + 0.5;
            var edgeCol = vec3<f32>(1.0, 0.0, 1.0); // Magenta base

            // Glitch chromatic aberration on edges based on curvature/normal derivative
            if (glitch > 0.0) {
                 edgeCol.r += glitch * sin(t_val * 5.0) * 0.5;
                 edgeCol.b += glitch * cos(t_val * 7.0) * 0.5;
            }
            edgeCol = hueRotate(edgeCol, hueShift);

            baseCol += edgeCol * pulse * (0.5 + audio.y * 0.45);

            // Idea 3: light-piped links. The sheet carries the node colour out of nearby crystals that are
            // frozen (Idea 1) and hold a 1-bit (Idea 2): nodes light the network, melted/0-bit ones do not.
            let pipe = exp(-max(d_crystal, 0.0) * 6.0) * front.x * bit.x;
            baseCol += neonCol * pipe * 1.3;
        }

        col = baseCol * (diff1 * 0.6 + diff2 * 0.4) + vec3<f32>(1.0) * spec;

        // Idea 1: frost rim where the freezing front is nucleating crystal right now (emissive, both materials).
        let frostCol = hueRotate(vec3<f32>(0.65, 1.0, 1.0), hueShift);
        col += frostCol * front.y * 1.4;

        // Fog
        col = mix(col, vec3<f32>(0.02, 0.02, 0.04), 1.0 - exp(-0.02 * t * t));
    }

    // Mouse-down shockwave post-process.
    // FIX: centred on the cursor (HEAD used the screen centre) and clamped >= 0 (HEAD subtracted colour).
    if (u.zoom_config.w > 0.0) {
        let aspectS = resolution.x / max(resolution.y, 1.0);
        let center = vec2<f32>((u.zoom_config.y - 0.5) * aspectS, 0.5 - u.zoom_config.z);
        let dist = length(uv - center);
        let shock = max(sin(dist * 50.0 - u.config.x * 20.0), 0.0) * exp(-dist * 5.0);
        col += vec3<f32>(shock * glitch, shock * glitch * 0.5, shock * glitch * 0.2);
    }

    // Timestamped click ripples propagate through the neural links.
    var clickEnergy = 0.0;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let delta = vec2<f32>((uv01.x - ripple.x) * aspect, uv01.y - ripple.y);
            clickEnergy += exp(-abs(length(delta) - age * 0.22) * 72.0) * exp(-age * 1.5);
        }
    }
    col += vec3<f32>(0.12 + audio.x * 0.3, 0.7 + audio.y * 0.4, 1.1 + audio.z * 0.5) * clickEnergy * 0.5;

    let coord = vec2<i32>(id.xy);
    let history = textureLoad(dataTextureC, coord, 0);
    let hdrColor = clamp(mix(col, history.rgb, 0.06 + audio.x * 0.07), vec3<f32>(0.0), vec3<f32>(7.0));
    let mappedColor = acesToneMap(hdrColor);
    let alpha = clamp(select(0.03, 0.3 + length(mappedColor) * 0.34, hit) + clickEnergy * 0.12, 0.02, 0.98);
    let depth = select(0.0, clamp(1.0 - t / 30.0, 0.0, 1.0), hit);

    textureStore(writeTexture, coord, vec4<f32>(mappedColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
