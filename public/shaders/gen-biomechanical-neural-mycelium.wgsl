// ═══════════════════════════════════════════════════════════════════
//  Biomechanical Neural Mycelium
//  Category: generative
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: action-potential packets (hash-gated pulses run along each fiber into the glow); hyphal jitter (per-strand wandering offsets turn the grid into an organic web); cursor synapse firing (nodes near the pointer swell and fire)
//  A packing: ACES display RGBA, a = coverage (fogged hit) + glow; C unread
// ═══════════════════════════════════════════════════════════════════
//  A flight down a twisting lattice of bio-metallic nodes and fibers.
//  Network Density packs the lattice tighter, Pulse Speed drives the
//  travelling packets and glow pulse, Glow Intensity scales the emission,
//  Mycelium Color shifts acid-green toward electric-blue.
#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const FAR: f32 = 20.0;
const MAX_STEPS: i32 = 110;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 = p3 + dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Network Density: higher = denser. Default 0.5 keeps HEAD's cell size 2.0.
fn cellScale() -> f32 {
    return 3.0 - u.zoom_params.x * 2.0;
}

// Camera line: the centre of a lattice cell, so it flies between fibers.
fn cameraAxis() -> vec2<f32> {
    return vec2<f32>(0.5, 0.5) * cellScale();
}

// Geometry clock is independent of Pulse Speed (HEAD froze the lattice at 0).
fn geoTime() -> f32 {
    return u.config.x * 0.5;
}

// The twist rotates around the camera axis, so the camera never leaves its cell.
fn twist(p: vec3<f32>) -> vec3<f32> {
    let c = cameraAxis();
    let rot = rot2D(geoTime() * 0.1 + p.z * 0.1);
    let xy = (p.xy - c) * rot + c;
    return vec3<f32>(xy, p.z);
}

// Idea 2: hyphal jitter — a strand wanders around its lattice axis along its own
// length, with phase/frequency hashed from the column it lives in.
fn hyphaOffset(column: vec2<f32>, along: f32, scale: f32) -> vec2<f32> {
    let h = hash22(column + 17.0);
    let f = 1.1 + h.x * 0.9;
    let amp = 0.12 * scale;
    return amp * vec2<f32>(sin(along * f + h.y * TAU), cos(along * f * 0.73 + h.x * TAU));
}

// Idea 1: action-potential packet on a strand. Gated per strand by hash.
fn packet(column: vec2<f32>, along: f32, scale: f32, ptime: f32) -> f32 {
    let h = hash22(column + 3.7);
    let gate = step(0.4, h.x);
    let ph = fract(along / (scale * 2.0) - ptime * (0.6 + h.y * 0.8) + h.y);
    let head = 1.0 - smoothstep(0.0, 0.05, abs(ph - 0.5));
    let tail = (1.0 - smoothstep(0.0, 0.18, 0.5 - ph)) * step(ph, 0.5) * 0.35;
    return gate * max(head, tail);
}

struct Scene {
    d: f32,
    packetE: f32,
    fireE: f32,
};

fn mapScene(p: vec3<f32>, mouseQ: vec3<f32>, synapseGain: f32) -> Scene {
    var pp = p;
    let gt = geoTime();
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let scale = cellScale();

    // Held pointer pulls the lattice toward it (HEAD behaviour, re-centred).
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec2<f32>(u.zoom_config.y - 0.5, (1.0 - u.zoom_config.z) - 0.5) * 5.0 + cameraAxis();
        let dist = length(pp.xy - mouse_pos);
        let pull = exp(-dist * 3.0);
        let qxy = pp.xy - (mouse_pos - cameraAxis()) * pull;
        pp = vec3<f32>(qxy, pp.z);
    }

    let q = twist(pp);

    // Domain repetition
    let cell = floor(q / scale + 0.5);
    let qRep = q - cell * scale;

    // Idea 3: cursor synapse firing — proximity of this node to the pointer.
    let toMouse = length(cell * scale - mouseQ);
    let proxLin = clamp(1.0 - toMouse / (1.3 * scale), 0.0, 1.0);
    let prox = proxLin * proxLin * synapseGain;
    let nodeHash = hash31(cell + 11.0);
    let fire = prox * (0.55 + 0.45 * sin(u.config.x * (7.0 + nodeHash * 5.0) + nodeHash * TAU));

    let nodeR = 0.1 + bass * 0.05 + prox * 0.14;
    let dNode = length(qRep) - nodeR; // Spheres at nodes

    // Fibers with hyphal jitter (Idea 2). Columns are keyed on the two
    // cross-axis cells so each strand stays continuous along its own axis.
    let offZ = hyphaOffset(cell.xy, q.z, scale);
    let offY = hyphaOffset(cell.xz + 41.0, q.y, scale);
    let offX = hyphaOffset(cell.yz + 83.0, q.x, scale);
    let fz = length(qRep.xy - offZ) - 0.02; // Z-axis fibers
    let fy = length(qRep.xz - offY) - 0.02; // Y-axis fibers
    let fx = length(qRep.yz - offX) - 0.02; // X-axis fibers
    let dFiber = min(fz, min(fy, fx));

    var d = smin(dNode, dFiber, 0.2);

    // Noise distortion
    d += sin(q.x * 5.0 + gt) * cos(q.y * 4.0 - gt) * 0.05;

    // Idea 1: packets on whichever strand is nearest, mids push them brighter.
    let ptime = u.config.x * u.zoom_params.y * 1.5;
    var pk = packet(cell.xy, q.z, scale, ptime);
    var fd = fz;
    if (fy < fd) { pk = packet(cell.xz + 41.0, q.y, scale, ptime); fd = fy; }
    if (fx < fd) { pk = packet(cell.yz + 83.0, q.x, scale, ptime); fd = fx; }
    let packetE = pk * exp(-max(fd, 0.0) * 10.0) * (1.0 + mids * 1.5);

    let fireE = fire * exp(-max(dNode, 0.0) * 5.0);

    var s: Scene;
    s.d = d;
    s.packetE = packetE;
    s.fireE = fireE;
    return s;
}

fn getNormal(p: vec3<f32>, mouseQ: vec3<f32>, g: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        mapScene(p + e.xyy, mouseQ, g).d - mapScene(p - e.xyy, mouseQ, g).d,
        mapScene(p + e.yxy, mouseQ, g).d - mapScene(p - e.yxy, mouseQ, g).d,
        mapScene(p + e.yyx, mouseQ, g).d - mapScene(p - e.yyx, mouseQ, g).d
    ) + vec3<f32>(1e-6));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    if (f32(id.x) >= dims.x || f32(id.y) >= dims.y) {
        return;
    }

    var uv = ((vec2<f32>(id.xy) + 0.5) * 2.0 - dims) / min(dims.x, dims.y);
    uv.y = -uv.y; // storage rows run top-down; keep the pointer upright
    let time = u.config.x;
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    let axis = cameraAxis();
    let ro = vec3<f32>(axis.x, axis.y, -3.0 + time * 0.5);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Idea 3: the pointer as a point in the lattice ~3 units ahead of the camera.
    let mUv = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mAsp = vec2<f32>(dims.x / min(dims.x, dims.y), dims.y / min(dims.x, dims.y));
    let mDir = normalize(vec3<f32>(mUv.x * mAsp.x, -mUv.y * mAsp.y, 1.0));
    let mouseQ = twist(ro + mDir * 3.0);
    let synapseGain = select(0.35, 1.0, u.zoom_config.w > 0.5);

    var t: f32 = 0.0;
    var d: f32 = 0.0;
    var glow: f32 = 0.0;
    var packetGlow: f32 = 0.0;
    var fireGlow: f32 = 0.0;
    var steps: i32 = MAX_STEPS;
    var hit: bool = false;

    let glowIntens = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.y;

    for (var i: i32 = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let s = mapScene(p, mouseQ, synapseGain);
        d = s.d;

        let localTime = time * pulseSpeed * 5.0;
        let glowPulse = sin(localTime + length(p) * 2.0) * 0.5 + 0.5;

        // Accumulate glow based on distance to nearest fiber
        let near = 0.01 / (d * d + 0.01);
        glow += near * glowPulse * glowIntens;
        packetGlow += s.packetE * near * 0.6;
        fireGlow += s.fireE * near * 0.5;

        if (d < 0.001) {
            steps = i;
            hit = true;
            break;
        }
        if (t > FAR) {
            steps = i;
            break;
        }
        t += d * 0.7; // Raymarching step (jittered strands need a little slack)
    }

    var col = vec3<f32>(0.0);
    let colorShift = u.zoom_params.w;

    // Base colors based on color shift (Acid-green to electric-blue)
    let c1 = vec3<f32>(0.2 + colorShift * 0.3, 1.0 - colorShift * 0.5, 0.2 + colorShift * 0.8);
    let c2 = vec3<f32>(0.1, 0.4 + colorShift * 0.4, 0.8 - colorShift * 0.2);

    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p, mouseQ, synapseGain);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0)); // Light dir
        let v = normalize(ro - p); // View dir
        let refl = reflect(-l, n);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(v, refl), 0.0), 32.0); // High specularity for bio-metallic look

        // Fake ambient occlusion based on step count
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        col = mix(c2, c1, diff) * ao + vec3<f32>(spec);
    }

    // Add emissive glow
    col += c1 * glow * 0.02;
    // Idea 1: packets burn hotter than the fiber glow (white-shifted c1), treble sparkles them
    let packetCol = mix(c1, vec3<f32>(1.0, 0.95, 0.85), 0.55);
    col += packetCol * packetGlow * 0.02 * (0.5 + glowIntens) * (1.0 + treble * 0.8);
    // Idea 3: synapse discharge — complementary magenta-white flare on fired nodes
    let fireCol = vec3<f32>(1.0, 0.45 + colorShift * 0.3, 0.9);
    col += fireCol * fireGlow * 0.03 * (0.5 + glowIntens) * (1.0 + bass);

    // Fog for intense scale
    let fog = exp(-t * 0.1);
    col = mix(vec3<f32>(0.02, 0.02, 0.05), col, fog);

    let display = acesToneMap(max(col, vec3<f32>(0.0)));
    let glowLum = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(select(0.0, fog, hit) + glowLum * 0.6, 0.0, 1.0);
    let depth = select(0.0, clamp(1.0 - t / FAR, 0.0, 1.0), hit);

    textureStore(writeTexture, id.xy, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(display, alpha));
}
