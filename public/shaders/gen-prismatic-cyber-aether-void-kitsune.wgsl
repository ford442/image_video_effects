// ═══════════════════════════════════════════════════════════════════
//  Prismatic Cyber-Aether Void-Kitsune
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: kitsune-bi fox-fire flames hovering at the nine tail tips; nine-tail thin-film interference spectrum (each tail a film of different thickness)
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .x = Tail Dispersion, .y = Current Warp, .z = Storm Density, .w = Rune Glow
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

// 3D Simplex Noise for volumetric environment
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(q) * 43758.5453123);
}

fn simplex_noise3d(p: vec3<f32>) -> f32 {
    let i = floor(p + dot(p, vec3<f32>(1.0 / 3.0)));
    let x0 = p - i + dot(i, vec3<f32>(1.0 / 6.0));
    let g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);
    let x1 = x0 - i1 + vec3<f32>(1.0 / 6.0);
    let x2 = x0 - i2 + vec3<f32>(1.0 / 3.0);
    let x3 = x0 - 1.0 + vec3<f32>(0.5);
    var n = max(0.6 - vec4<f32>(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), vec4<f32>(0.0));
    n = n * n * n * n;
    let d0 = dot(hash3(i), x0);
    let d1 = dot(hash3(i + i1), x1);
    let d2 = dot(hash3(i + i2), x2);
    let d3 = dot(hash3(i + 1.0), x3);
    return 27.5 * dot(n, vec4<f32>(d0, d1, d2, d3));
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var freq = p;
    for (var i = 0; i < 4; i++) {
        f += amp * simplex_noise3d(freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return f;
}

// ─── 3D SDF library ───
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
fn sdOctahedron(p_in: vec3<f32>, s: f32) -> f32 {
    let p = abs(p_in);
    return (p.x + p.y + p.z - s) * 0.57735027;
}
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// ─── 2D geometric library ───
fn mod2(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return a - b * floor(a / b);
}
fn hexDist(p: vec2<f32>) -> f32 {
    let q = abs(p);
    return max(dot(q, normalize(vec2<f32>(1.0, 1.7320508))), q.x);
}
// vec4(local_xy, cell_id_xy) of nearest hex cell
fn hexCell(p: vec2<f32>) -> vec4<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let a = mod2(p, r) - h;
    let b = mod2(p - h, r) - h;
    let gv = select(b, a, dot(a, a) < dot(b, b));
    return vec4<f32>(gv, p - gv);
}
// kaleidoscopic symmetry fold
fn kaleido(p: vec2<f32>, folds: f32) -> vec2<f32> {
    let r = length(p);
    var a = atan2(p.y, p.x);
    let seg = TAU / folds;
    a = fract(a / seg) * seg;
    a = abs(a - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}

fn mouseWorld() -> vec2<f32> {
    // mouse_uv is 0-1, y=0 top; world is y-up
    let mUv = u.zoom_config.yz;
    return vec2<f32>((mUv.x - 0.5) * 6.0, (0.5 - mUv.y) * 6.0);
}

fn heldAmount() -> f32 {
    return select(0.0, 1.0, u.zoom_config.w > 0.5);
}

// Mouse current warp (held mouse pulls the aether current harder)
fn warpPoint(p: vec3<f32>) -> vec3<f32> {
    let mWorld = mouseWorld();
    let dist = length(p.xy - mWorld * 0.5);
    let warp_factor = u.zoom_params.y * (1.0 + heldAmount() * 1.2) / (1.0 + dist * dist * 5.0); // Current Warp slider
    return p - vec3<f32>(mWorld * 0.33, 0.0) * warp_factor;
}

// Tail geometry shared by the SDF and the fox-fire tips
fn tailDir(i: i32, t: f32, tail_disp: f32) -> vec3<f32> {
    let angle = f32(i) / 9.0 * TAU + sin(t * 0.5) * 0.2;
    let s = sin(angle);
    let c = cos(angle);
    return vec3<f32>(s * tail_disp, sin(t + f32(i)) * 0.5 * tail_disp, -1.5 - c * 0.2 * tail_disp);
}

// Native idea 1: kitsune-bi — a wisp of fox-fire hovering at each tail tip.
// Each flame is an emissive Gaussian (stretched vertically into a teardrop);
// the ray's line integral through it is analytic, so flames never alias
// between march steps. Occluded by the first SDF hit (tMax).
fn foxFire(ro: vec3<f32>, rd: vec3<f32>, tMax: f32, t: f32, tail_disp: f32, bass: f32, treble: f32) -> f32 {
    let tail_origin = vec3<f32>(0.0, -0.1, -1.0);
    let held = heldAmount();
    let mWorld = mouseWorld();
    let k = 55.0;
    let stretch = vec3<f32>(1.0, 0.6, 1.0); // teardrop: taller than wide
    let dS = rd * stretch;
    let dd = max(dot(dS, dS), 1e-4);
    var acc = 0.0;
    for (var i = 0; i < 9; i++) {
        let dir = tailDir(i, t, tail_disp);
        var tip = tail_origin + normalize(dir) * length(dir) * 1.9;
        tip.y += 0.25 + sin(t * 2.3 + f32(i) * 1.7) * 0.08;
        // held mouse: onibi drift toward the cursor
        tip = mix(tip, vec3<f32>(mWorld * 0.5, tip.z * 0.5), held * 0.3);
        let w = (ro - tip) * stretch;
        let sClosest = -dot(w, dS) / dd;
        if (sClosest < 0.0 || sClosest > tMax) { continue; }
        let perp2 = max(dot(w, w) - dot(w, dS) * dot(w, dS) / dd, 0.0);
        let flick = 0.75 + 0.25 * sin(t * 11.0 + f32(i) * 2.9) * (0.4 + treble);
        acc += exp(-k * perp2) * sqrt(PI / (k * dd)) * flick * (0.7 + bass * 0.5);
    }
    return acc;
}

// Native idea 2: thin-film interference — each tail is a soap-film of its
// own thickness (nm); reflected colour depends on optical path 2*n*d*cos(theta_t).
fn thinFilm(cosTheta: f32, thicknessNm: f32) -> vec3<f32> {
    let nFilm = 1.33;
    let sinT2 = (1.0 - cosTheta * cosTheta) / (nFilm * nFilm);
    let cosT = sqrt(max(1.0 - sinT2, 0.0));
    let opd = 2.0 * nFilm * thicknessNm * cosT;
    let lambdas = vec3<f32>(650.0, 530.0, 450.0);
    return 0.5 + 0.5 * cos(TAU * opd / lambdas + PI);
}

// Distance, Material ID, Glow Intensity — 1 body, 2.x tails (fraction = tail index/10), 3 shard swarm, 4 tail-rings
fn map(p: vec3<f32>) -> vec3<f32> {
    let p_warp = warpPoint(p);

    let t = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let tail_disp = u.zoom_params.x; // Tail Dispersion

    // 1. Cybernetic Kitsune Body (Mechanical/Crystalline Armor)
    var p_body = p_warp;
    p_body.y += sin(t * 1.5) * 0.1; // breathing float

    // Core body (capsule)
    var d_body = sdCapsule(p_body, vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0, -0.2, -1.0), 0.3);
    // Head
    let p_head = p_body - vec3<f32>(0.0, 0.4, 1.5);
    var d_head = sdCapsule(p_head, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 0.0, 0.4), 0.25);
    // Snout
    d_head = smin(d_head, sdCapsule(p_head, vec3<f32>(0.0, 0.0, 0.4), vec3<f32>(0.0, -0.1, 0.8), 0.1), 0.1);
    // Ears
    let p_ear_l = p_head - vec3<f32>(0.15, 0.2, 0.0);
    let d_ear_l = sdCapsule(p_ear_l, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.2, 0.4, -0.1), 0.05);
    let p_ear_r = p_head - vec3<f32>(-0.15, 0.2, 0.0);
    let d_ear_r = sdCapsule(p_ear_r, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(-0.2, 0.4, -0.1), 0.05);
    d_head = smin(d_head, d_ear_l, 0.05);
    d_head = smin(d_head, d_ear_r, 0.05);
    d_body = smin(d_body, d_head, 0.2);

    // Cyber-armor plates (boxes booleaned out or added)
    let p_armor = p_body;
    d_body = max(d_body, -sdBox(p_armor - vec3<f32>(0.0, 0.0, -0.2), vec3<f32>(0.4, 0.02, 1.0))); // Cuts
    d_body = smin(d_body, sdBox(p_armor - vec3<f32>(0.0, 0.2, 0.0), vec3<f32>(0.2, 0.2, 0.5)), 0.1); // Back ridge
    // Octahedral shoulder crystals
    let p_sh = abs(p_body) - vec3<f32>(0.3, 0.25, 0.6);
    d_body = smin(d_body, sdOctahedron(rotY(t * 0.8) * p_sh, 0.12 + treble * 0.05), 0.06);

    // Rune Glow — hex-tessellated rune grid on the armor (2D geometric layer)
    let runeUV = vec2<f32>(atan2(p_body.x, p_body.z) * 2.0, p_body.y * 3.0) + vec2<f32>(0.0, -t * 0.4);
    let hc = hexCell(runeUV * 3.0);
    let runeEdge = smoothstep(0.4, 0.48, hexDist(hc.xy));
    let rune_noise = simplex_noise3d(p_body * 10.0 + vec3<f32>(0.0, 0.0, -t * 2.0));
    var rune_glow = 0.0;
    if (d_body < 0.1) {
        let cellPulse = 0.5 + 0.5 * sin(t * 3.0 + dot(hc.zw, vec2<f32>(1.3, 1.9)));
        rune_glow = runeEdge * cellPulse * step(0.2, rune_noise) * u.zoom_params.w * (1.0 + bass * 2.0);
    }

    // 2. Nine Volumetric Aether Tails
    var d_tails = 100.0;
    var tail_glow = 0.0;
    var tail_best = 100.0;
    var tail_idx = 0.0;
    let tail_origin = vec3<f32>(0.0, -0.1, -1.0);

    for (var i = 0; i < 9; i++) {
        let angle = f32(i) / 9.0 * TAU + sin(t * 0.5) * 0.2;
        let s = sin(angle);
        let c = cos(angle);

        // Spread tails out backwards and outwards
        let dir = tailDir(i, t, tail_disp);
        let dir_norm = normalize(dir);

        var p_tail = p_warp - tail_origin;
        let h = clamp(dot(p_tail, dir_norm), 0.0, length(dir) * 2.0);

        // Wavy motion based on audio and time
        let wave = sin(h * 2.0 - t * 3.0 + f32(i)) * 0.2 * (1.0 + bass);
        p_tail -= dir_norm * h + vec3<f32>(wave * c, wave, wave * s);

        // Tapering tail radius
        let tailFade = 1.0 - smoothstep(1.0, length(dir) * 2.0, h);
        let r = 0.15 * smoothstep(0.0, 1.0, h) * tailFade * (1.0 + simplex_noise3d(p_tail * 5.0 + t) * 0.3);

        let d_t = length(p_tail) - r;
        d_tails = smin(d_tails, d_t, 0.3);
        if (d_t < tail_best) { tail_best = d_t; tail_idx = f32(i); }

        if (d_t < 0.5) {
            tail_glow += 0.05 / (0.01 + d_t * d_t) * (0.5 + bass * 1.5);
        }
    }

    // 3. Prismatic octahedral shard swarm orbiting the kitsune (matID 3)
    let swarmP = rotY(t * 0.6) * p_warp;
    let swarmAngle = atan2(swarmP.z, swarmP.x);
    let cellA = floor(swarmAngle * 3.0 / PI) / 3.0 * PI + PI / 6.0;
    let orbitR = 2.2 + bass * 0.4;
    let shardC = vec3<f32>(cos(cellA) * orbitR, sin(t * 0.9 + cellA * 3.0) * 0.8, sin(cellA) * orbitR);
    let d_shards = sdOctahedron(rotY(-cellA - t) * (swarmP - shardC), 0.18 + treble * 0.12);

    // 4. Torus auroral tail-rings stacked behind the body (matID 4)
    var d_rings = 100.0;
    for (var j = 0; j < 3; j++) {
        let fj = f32(j);
        let ringC = tail_origin + vec3<f32>(0.0, sin(t * 0.7 + fj * 2.1) * 0.3, -0.8 - fj * 0.9);
        let pRing = rotY(t * (0.4 + fj * 0.2)) * (p_warp - ringC);
        d_rings = min(d_rings, sdTorus(pRing, vec2<f32>(0.5 + fj * 0.35 + bass * 0.2, 0.03 + treble * 0.03)));
    }

    // Combine
    var d_final = d_body;
    var mat_id = 1.0; // 1 = Body, 2 = Tails, 3 = Shards, 4 = Rings

    if (d_tails < d_final) { d_final = d_tails; mat_id = 2.0 + tail_idx * 0.1; }
    if (d_shards < d_final) { d_final = d_shards; mat_id = 3.0; }
    if (d_rings < d_final) { d_final = d_rings; mat_id = 4.0; }

    return vec3<f32>(d_final, mat_id, max(rune_glow, tail_glow));
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    // bounds guard — mandatory
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(pixel) - 0.5 * res) / res.y;

    let t = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let tail_disp = u.zoom_params.x;

    // Camera setup
    var ro = vec3<f32>(0.0, 1.0, 4.0);
    ro.x = sin(t * 0.2) * 2.0;
    ro.z = cos(t * 0.2) * 4.0;
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.2 * ww);

    // Raymarching — adaptive step count with storm density
    var p = ro;
    var t_dist = 0.0;
    var res_map: vec3<f32>;
    var hit = false;
    var total_glow = 0.0;
    var fox_fire = 0.0;

    let maxSteps = 80 + min(i32(u.zoom_params.z * 60.0), 40);
    let maxDist = 15.0;

    for (var i = 0; i < maxSteps; i++) {
        p = ro + rd * t_dist;
        res_map = map(p);
        total_glow += res_map.z; // Accumulate glow from runes/tails
        if (res_map.x < 0.001) { hit = true; break; }
        if (t_dist > maxDist) { break; }
        t_dist += res_map.x * 0.8;
    }

    fox_fire = foxFire(ro, rd, select(maxDist, t_dist, hit), t, tail_disp, bass, treble) * 2.5;

    var col = vec3<f32>(0.0);
    let storm_density = u.zoom_params.z;

    if (hit) {
        let n = calcNormal(p);
        let v = -rd;
        let l = normalize(vec3<f32>(1.0, 2.0, 3.0));
        let h_vec = normalize(v + l);

        let dif = max(dot(n, l), 0.0);
        let amb = 0.1 + 0.9 * max(0.0, dot(n, vec3<f32>(0.0, 1.0, 0.0)));
        let spec = pow(max(dot(n, h_vec), 0.0), 32.0);
        let fre = pow(clamp(1.0 - dot(n, v), 0.0, 1.0), 3.0);

        let matI = floor(res_map.y + 0.001);
        if (matI < 1.5) {
            // Body - Prismatic / Crystalline Armor
            let base_col = vec3<f32>(0.1, 0.1, 0.15); // Dark cybernetic
            col = base_col * (dif + amb) + spec * 0.5;

            // Refraction/Subsurface approximation (Prismatic)
            let refr = fbm(p * 2.0 + t);
            let prism_col = vec3<f32>(
                0.5 + 0.5 * sin(refr * 10.0 + 0.0),
                0.5 + 0.5 * sin(refr * 10.0 + 2.0),
                0.5 + 0.5 * sin(refr * 10.0 + 4.0)
            );
            col += prism_col * fre * 0.5;

            // Hex runes
            col += vec3<f32>(0.0, 0.8, 1.0) * res_map.z; // Cyan glow

        } else if (matI < 2.5) {
            // Tails - Aether Plasma
            let plasma_col = mix(
                vec3<f32>(1.0, 0.2, 0.8), // Magenta
                vec3<f32>(1.0, 0.5, 0.0), // Orange
                sin(p.z * 2.0 - t * 4.0) * 0.5 + 0.5
            );
            col = plasma_col * (0.5 + amb * 0.5) + spec * 0.2;
            col += plasma_col * res_map.z * 0.2; // Self illumination

            // Idea 2: nine-tail thin-film spectrum — tail index sets film thickness,
            // a slow ripple along the tail modulates it; view angle picks the colour.
            let tailIndex = round((res_map.y - 2.0) * 10.0);
            let filmNm = 280.0 + tailIndex * 45.0 + sin(p.z * 3.0 - t * 2.0 + tailIndex) * 40.0 * (1.0 + mids);
            let film = thinFilm(clamp(dot(n, v), 0.0, 1.0), filmNm);
            col = mix(col, film * (0.45 + amb * 0.4) + spec * 0.3, 0.35 + fre * 0.4);

        } else if (res_map.y == 3.0) {
            // Prismatic shards — glassy rainbow fresnel
            let shard_col = 0.5 + 0.5 * cos(t * 2.0 + p.x * 4.0 + vec3<f32>(0.0, 2.1, 4.2));
            col = shard_col * (dif * 0.5 + 0.3) + shard_col * fre * 1.5 + spec * 0.6;

        } else {
            // Auroral torus rings — spectral band emission
            let band = 0.5 + 0.5 * sin(length(p.xz) * 12.0 - t * 5.0);
            let ring_col = mix(vec3<f32>(0.1, 1.0, 0.6), vec3<f32>(0.6, 0.2, 1.0), band);
            col = ring_col * (0.6 + dif * 0.4) * (1.0 + bass) + fre * ring_col;
        }
    } else {
        // Quantum-Storm Void Environment — kaleidoscopically folded volumetric FBM
        let kFolds = 5.0 + floor(mids * 5.0);
        let rdK = vec3<f32>(kaleido(rd.xy, kFolds), rd.z);
        var vol_col = vec3<f32>(0.0);
        var vol_t = 0.0;
        for (var i = 0; i < 40; i++) {
            let p_vol = ro + normalize(rdK) * vol_t;
            let density = fbm(p_vol * 1.5 - vec3<f32>(0.0, 0.0, t * 1.0));
            if (density > 0.4) {
                let d = (density - 0.4) * storm_density * (1.0 + bass);
                vol_col += vec3<f32>(0.2, 0.0, 0.4) * d * 0.1; // Dark matter purple
            }
            vol_t += 0.3;
        }
        col = vol_col;
    }

    // Add accumulated glow bloom
    let bloom_col = mix(vec3<f32>(1.0, 0.0, 0.5), vec3<f32>(0.0, 1.0, 1.0), sin(t) * 0.5 + 0.5);
    col += bloom_col * total_glow * 0.01;

    // Idea 1: kitsune-bi fox-fire — white-blue core fading to spectral violet rim
    let ffCore = clamp(fox_fire * 1.5, 0.0, 1.0);
    let ff_col = mix(vec3<f32>(0.35, 0.3, 1.0), vec3<f32>(0.75, 0.95, 1.0), ffCore);
    col += ff_col * fox_fire * (1.4 + treble * 0.6);

    // Click ripples: a fox-fire flare ring bursting from the click point
    let uv01 = vec2<f32>(pixel) / res;
    let aspectV = vec2<f32>(res.x / res.y, 1.0);
    var ripple_glow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r = 0u; r < rippleCount; r++) {
        let rp = u.ripples[r];
        let age = t - rp.z;
        if (age < 0.0 || age > 2.5) { continue; }
        let rd2 = length((uv01 - rp.xy) * aspectV);
        let ring = exp(-pow((rd2 - age * 0.35) * 28.0, 2.0)) * exp(-age * 1.6);
        ripple_glow += ring;
    }
    col += thinFilm(clamp(1.0 - ripple_glow, 0.0, 1.0), 380.0 + ripple_glow * 200.0) * ripple_glow * 0.9;

    // Vignette + ACES tone mapping + display gamma
    col *= 1.0 - 0.5 * length(uv);
    col = acesToneMap(col * (1.25 + bass * 0.2));
    col = pow(col, vec3<f32>(0.4545));

    // Real depth: normalized ray distance on hit
    let depth = select(0.0, clamp(1.0 - t_dist / maxDist, 0.0, 1.0), hit);

    // Semantic alpha: solid coverage on SDF hits, emissive density (fox-fire, glow, storm) in the void
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let emissive = clamp(fox_fire * 0.8 + total_glow * 0.004 + ripple_glow * 0.5, 0.0, 1.0);
    let alpha = clamp(select(luma * 0.6 + emissive * 0.4, 0.85 + luma * 0.15, hit), 0.0, 1.0);

    let finalColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, pixel, finalColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, finalColor);
}
