// ═══════════════════════════════════════════════════════════════════
//  Cyber-Organic Void-Mycelium Pulsar
//  Category: generative
//  Features: raymarching, bioluminescent, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: rhizomorphic root-fan branches sprouting from each node; electroplaque ring discharges around pulsing spores
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Density, y=Spore Glow, z=Twist, w=Fog

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p2 = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                       dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                       dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 2 — a bead running out from the node along each axis tube.
fn sporePulse(q: vec3<f32>, time: f32, mids: f32) -> f32 {
    let reach = fract(time * (0.35 + mids * 1.35)) * 1.7;
    let beadX = exp(-abs(abs(q.x) - reach) * 16.0) * exp(-length(q.yz) * 12.0);
    let beadY = exp(-abs(abs(q.y) - reach) * 16.0) * exp(-length(q.xz) * 12.0);
    let beadZ = exp(-abs(abs(q.z) - reach) * 16.0) * exp(-length(q.xy) * 12.0);
    return beadX + beadY + beadZ;
}

fn map(p: vec3<f32>, time: f32, bass: f32, mids: f32, density: f32, twist_str: f32) -> vec3<f32> {
    var q = p;

    // Domain repetition / Grid
    let cell_size = 4.0 / max(density, 0.1);
    q = (fract(q / cell_size) - 0.5) * cell_size;

    // Twist — a real 2D rotation (the old second row read the updated q.x).
    let angle = length(p.xy) * twist_str * 0.1 + time * 0.2;
    let cs = cos(angle);
    let sn = sin(angle);
    let qx = q.x * cs - q.y * sn;
    let qy = q.x * sn + q.y * cs;
    q = vec3<f32>(qx, qy, q.z);

    // Mycelium branches (cylinders)
    let r1 = length(q.xy) - 0.1 - bass * 0.05;
    let r2 = length(q.yz) - 0.1 - bass * 0.05;
    let r3 = length(q.xz) - 0.1 - bass * 0.05;
    var d = smin(r1, r2, 0.5);
    d = smin(d, r3, 0.5);

    // Idea 1 — anastomosis: short bridges tying the three axis tubes into one junction.
    let anastomosis = min(
        sdCapsule(q, vec3<f32>(0.55, 0.0, 0.0), vec3<f32>(0.0, 0.55, 0.0), 0.04),
        min(
            sdCapsule(q, vec3<f32>(0.55, 0.0, 0.0), vec3<f32>(0.0, 0.0, 0.55), 0.04),
            sdCapsule(q, vec3<f32>(0.0, 0.55, 0.0), vec3<f32>(0.0, 0.0, 0.55), 0.04)
        )
    );
    d = smin(d, anastomosis, 0.18);

    // Idea 3 — rhizomorphic root-fan side branches.
    let rootA = sdCapsule(q, vec3<f32>(0.0, -0.2, 0.0), vec3<f32>(0.95, -1.05, 0.55), 0.035);
    let rootB = sdCapsule(q, vec3<f32>(0.0, -0.2, 0.0), vec3<f32>(-0.95, -1.05, -0.55), 0.035);
    let rootC = sdCapsule(q, vec3<f32>(0.0, -0.2, 0.0), vec3<f32>(0.6, -1.0, -0.95), 0.03);
    d = smin(d, min(rootA, min(rootB, rootC)), 0.14);

    // Nodes (spheres)
    let node_dist = length(q) - (0.3 + bass * 0.2);
    d = smin(d, node_dist, 0.8);

    // Add some noise displacement
    let disp = sin(10.0*p.x)*sin(10.0*p.y)*sin(10.0*p.z) * 0.05;
    d += disp;

    // Distinguish materials: 1.0 for branch, 2.0 for node
    let mat = select(1.0, 2.0, node_dist < d + 0.1);
    let pulse = sporePulse(q, time, mids);

    return vec3<f32>(d, mat, pulse);
}

fn getNormal(p: vec3<f32>, time: f32, bass: f32, mids: f32, density: f32, twist_str: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, bass, mids, density, twist_str).x - map(p - e.xyy, time, bass, mids, density, twist_str).x,
        map(p + e.yxy, time, bass, mids, density, twist_str).x - map(p - e.yxy, time, bass, mids, density, twist_str).x,
        map(p + e.yyx, time, bass, mids, density, twist_str).x - map(p - e.yyx, time, bass, mids, density, twist_str).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(global_id.xy);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) {
        return;
    }
    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    let density = u.zoom_params.x;
    let spore_glow = u.zoom_params.y;
    let twist_str = u.zoom_params.z;
    let fog_dens = u.zoom_params.w;

    // Camera setup
    var ro = vec3<f32>(time, 0.0, -time * 2.0); // Moving through the void
    let lookAtTarget = ro + vec3<f32>(-1.0, 0.0, 2.0);

    // Mouse Interaction
    var rd = normalize(vec3<f32>(uv, 1.0));
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = (u.zoom_config.yz - 0.5) * vec2<f32>(res.x/res.y, 1.0);
        let m = vec2<f32>(mouse_uv.x * 3.14, mouse_uv.y * 3.14);

        let rotM = rot(m.y);
        rd.y = rd.y * rotM[0][0] + rd.z * rotM[0][1];
        rd.z = rd.y * rotM[1][0] + rd.z * rotM[1][1];

        let rotM2 = rot(m.x);
        rd.x = rd.x * rotM2[0][0] + rd.z * rotM2[0][1];
        rd.z = rd.x * rotM2[1][0] + rd.z * rotM2[1][1];
    } else {
        // Default camera orientation
        let f = normalize(lookAtTarget - ro);
        let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
        let u_vec = cross(f, r);
        rd = normalize(r * uv.x + u_vec * uv.y + f * 1.0);
    }

    // Raymarching
    var dO: f32 = 0.0;
    var dS: f32 = 0.0;
    var p: vec3<f32>;
    var mat: f32 = 0.0;
    var steps: i32 = 0;
    var min_dist_to_spore: f32 = 1000.0;
    var pulseAccum = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let map_res = map(p, time, bass, mids, density, twist_str);
        dS = map_res.x;
        mat = map_res.y;
        pulseAccum = max(pulseAccum, map_res.z * exp(-dS * 6.0));

        // Track closest distance to nodes (spores) for glow
        if (mat == 2.0) {
            min_dist_to_spore = min(min_dist_to_spore, dS);
        }

        if (abs(dS) < SURF_DIST || dO > MAX_DIST) {
            steps = i;
            break;
        }
        dO += dS;
    }

    var col = vec3<f32>(0.0);
    let depth = dO;

    if (dO < MAX_DIST) {
        let n = getNormal(p, time, bass, mids, density, twist_str);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        // Obsidian material
        col = vec3<f32>(0.05, 0.05, 0.06) * diff * ao;

        // Specular
        let refl = reflect(-lightDir, n);
        let spec = pow(max(dot(refl, -rd), 0.0), 32.0);
        col += vec3<f32>(0.2) * spec;

        // Node Bioluminescence (Cyan, Magenta, Green)
        if (mat == 2.0) {
             let emit_color = vec3<f32>(
                 0.5 + 0.5 * sin(p.x * 2.0 + time),
                 0.5 + 0.5 * sin(p.y * 2.0 + time + 2.0),
                 0.5 + 0.5 * sin(p.z * 2.0 + time + 4.0)
             );
             // Boost emission on bass
             col += emit_color * (1.0 + bass * 2.0) * spore_glow;
        }

        // Idea 4 — electroplaque discharge rings around pulsing nodes.
        let cell_size = 4.0 / max(density, 0.1);
        var qn = p;
        qn = (fract(qn / cell_size) - 0.5) * cell_size;
        let ring = exp(-abs(length(qn) - 0.45) * 22.0) * pow(max(sin(time * 6.0 + qn.y * 9.0), 0.0), 7.0);
        col += vec3<f32>(0.16, 0.85, 1.0) * ring * (0.22 + bass * 0.25);
    }

    // Subspace fog (dark abyssal purple/blue)
    let fogColor = vec3<f32>(0.02, 0.0, 0.05);
    let fogFactor = 1.0 - exp(-dO * 0.05 * fog_dens);
    col = mix(col, fogColor, fogFactor);

    // Volumetric Spore Bloom
    let bloomCol = vec3<f32>(0.0, 1.0, 0.5); // Toxic green
    let bloom = exp(-min_dist_to_spore * 2.0) * spore_glow * (0.35 + bass);
    col += bloomCol * bloom;
    col += vec3<f32>(0.45, 1.0, 0.72) * pulseAccum * spore_glow;

    let hit = dO < MAX_DIST;
    col = acesToneMap(col * 1.15);
    let alpha = clamp(select(0.04, 0.7, hit) + bloom * 0.2 + pulseAccum * spore_glow * 0.15, 0.0, 1.0);
    let depthOut = select(0.0, clamp(1.0 - depth / MAX_DIST, 0.0, 1.0), hit);
    let outColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, coords, outColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, outColor);
}
