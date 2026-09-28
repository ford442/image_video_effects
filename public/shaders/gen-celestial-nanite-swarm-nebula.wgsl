// ═══════════════════════════════════════════════════════════════════
//  Celestial Nanite-Swarm Nebula
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: Kuramoto nanite sync (per-cell Adler-locked blink phases sweep in waves as Geometric Order couples them); lattice self-assembly (Voronoi feature points dock onto the box-lattice edges); face-dust extinction (Beer-Lambert dark sheets on the Voronoi faces between nanites)
//  A packing: ACES display RGBA + semantic alpha (C not read)
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
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY (0..1, y=0 top), w=MouseDown
    zoom_params: vec4<f32>,  // x=Swarm Density, y=Constellation Link, z=Wind Speed, w=Geometric Order
    ripples: array<vec4<f32>, 50>,
};

// One density sample of the nebula: HEAD's scalar density plus what the ideas need.
struct NebulaSample {
    density: f32,   // HEAD density (cells + links + lattice)
    blink: f32,     // Idea 1: Kuramoto flash of the nearest nanite, 0..1
    core: f32,      // closeness to the nearest nanite's feature point
    dust: f32,      // Idea 3: Voronoi-face dust mask, 0..1
};

struct Voro {
    f: vec2<f32>,    // F1, F2 (HEAD)
    cell: vec3<f32>, // nearest (docked) feature point, voronoi space
    id: vec3<f32>,   // per-nanite hash of the nearest cell
};

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

// Idea 2: nearest point on the 12 edges of the lattice box (half-size 0.5, period 4 — the HEAD lattice), world space.
fn latticeEdgePoint(w: vec3<f32>) -> vec3<f32> {
    let node = 4.0 * round(w / 4.0);
    let q = w - node;
    let h = 0.5;
    let s = select(vec3<f32>(-h), vec3<f32>(h), q >= vec3<f32>(0.0));
    let c = clamp(q, vec3<f32>(-h), vec3<f32>(h));
    let ea = vec3<f32>(c.x, s.y, s.z);
    let eb = vec3<f32>(s.x, c.y, s.z);
    let ec = vec3<f32>(s.x, s.y, c.z);
    let da = dot(q - ea, q - ea);
    let db = dot(q - eb, q - eb);
    let dc = dot(q - ec, q - ec);
    var best = ea;
    var bd = da;
    if (db < bd) { best = eb; bd = db; }
    if (dc < bd) { best = ec; }
    return node + best;
}

// HEAD F1/F2 Voronoi, now also returning the nearest nanite (id + position) and letting feature points dock.
// flow = the voronoi-space advection offset, so a feature point P lives at world (P - flow) * 0.5.
fn voronoi(x: vec3<f32>, flow: vec3<f32>, assemble: f32, time: f32) -> Voro {
    let n = floor(x);
    let f = fract(x);
    var res = vec2<f32>(8.0);
    var cell = vec3<f32>(0.0);
    var id = vec3<f32>(0.0);

    for (var k: i32 = -1; k <= 1; k = k + 1) {
        for (var j: i32 = -1; j <= 1; j = j + 1) {
            for (var i: i32 = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let hh = hash3(n + g + vec3<f32>(17.13, 5.71, 9.37));
                var fp = n + g + o;

                // Idea 2: lattice self-assembly — as Geometric Order rises each nanite docks onto the nearest
                // lattice edge. Docking is staggered per nanite (hh.z) and breathes slowly, so the swarm is seen
                // assembling / shedding rather than cross-fading. Target is clamped inside the nanite's own cell
                // so the 3x3x3 search stays valid; far nanites feel a weaker pull.
                if (assemble > 0.001) {
                    let edgeV = latticeEdgePoint((fp - flow) * 0.5) * 2.0 + flow;
                    let tgt = clamp(edgeV, n + g + vec3<f32>(0.02), n + g + vec3<f32>(0.98));
                    let dock = smoothstep(0.0, 1.0,
                        assemble * 1.5 - hh.z * 0.6 + 0.2 * sin(time * 0.35 + hh.x * 6.2831));
                    let reach = exp(-length(edgeV - fp) * 0.45);
                    fp = mix(fp, tgt, dock * reach);
                }

                let r = fp - x;
                let d = dot(r, r);

                if (d < res.x) {
                    res.y = res.x;
                    res.x = d;
                    cell = fp;
                    id = hh;
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return Voro(vec2<f32>(sqrt(res.x), sqrt(res.y)), cell, id);
}

// Idea 1: Kuramoto nanite sync. Mean-field Kuramoto reduces, per oscillator, to the Adler equation
//   dθ/dt = Δω - K sin θ,  θ = φ_i - Ψ
// which has a closed form, so it is stateless: |Δω| <= K locks at θ* = asin(Δω/K); otherwise the
// phase slips with period 2π/√(Δω²-K²). Ψ is a travelling mean-field phase, so locked nanites flash
// in sweeping waves. K rises with Geometric Order (bass kicks it); at K = 0 every nanite free-runs.
fn kuramotoBlink(id: vec3<f32>, cellWorld: vec3<f32>, K: f32, time: f32) -> f32 {
    let psi = 2.2 * time - dot(cellWorld, vec3<f32>(0.9, 0.35, 0.6));
    var dw = (id.x - 0.5) * 2.4;
    dw = select(dw, 0.001, abs(dw) < 0.001);
    let tau = time + id.y * 40.0;
    var theta: f32;
    if (abs(dw) <= K) {
        theta = asin(clamp(dw / K, -1.0, 1.0));
    } else {
        let w = sqrt(max(dw * dw - K * K, 0.0));
        theta = 2.0 * atan((K + w * tan(0.5 * w * tau)) / dw);
    }
    return pow(max(0.5 + 0.5 * cos(psi + theta), 0.0), 8.0);
}

fn map_density(p: vec3<f32>) -> NebulaSample {
    let density_param = u.zoom_params.x;
    let link_param = u.zoom_params.y;
    let wind_param = u.zoom_params.z;
    let order_param = u.zoom_params.w;
    let time = u.config.x;
    let aspect = u.config.z / max(u.config.w, 1.0);

    var pos = p;
    // NOTE: speed-scaled phase (HEAD) — moving Wind Speed re-phases the drift; unavoidable without persistent state.
    let t = u.config.x * (0.2 + wind_param * 0.5);

    // Mouse attractor (fixed): compared in undrifted camera space. The cursor ray crosses z = 0 at
    // xy = p_mouse * 5 (camera at z = -5, rd = (p, 1)), so the pull point now sits under the pointer, aspect-correct.
    let pm = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0 * vec2<f32>(aspect, 1.0);
    let mouse_pos = vec3<f32>(pm * 5.0, 0.0);
    let dist_to_mouse = length(pos - mouse_pos);
    let pull = exp(-dist_to_mouse * 0.5) * 2.0;

    if (dist_to_mouse > 0.01) {
        pos = mix(pos, mouse_pos, pull * 0.1);
    }

    pos.x += sin(t * 0.5) * 2.0;
    pos.z += cos(t * 0.3) * 2.0;

    let flow = vec3<f32>(t, t * 0.5, -t);
    let v = voronoi(pos * 2.0 + flow, flow, order_param, time);
    let cell_density = 1.0 - v.f.x;
    let link_density = v.f.y - v.f.x;

    var density = cell_density * (0.5 + density_param * 0.5);
    density += link_density * link_param * 0.5;

    var q = pos;
    q.x = q.x - round(q.x / 4.0) * 4.0;
    q.y = q.y - round(q.y / 4.0) * 4.0;
    q.z = q.z - round(q.z / 4.0) * 4.0;

    let box_d = length(max(abs(q) - vec3<f32>(0.5), vec3<f32>(0.0))) - 0.1;
    // Fixed: HEAD smoothstep(0.5, 0.0, x) had reversed edges; same curve, spec-safe form.
    let shape_density = 1.0 - smoothstep(0.0, 0.5, box_d);

    // Bass swells the constellation links (correct audio source)
    let bass = plasmaBuffer[0].x;
    let audio_react = bass * 0.5;

    density = mix(density, density * shape_density * 2.0, order_param);
    density += audio_react * link_density;

    // Idea 1: coupling K from Geometric Order; bass kicks it (audio rides along, not the idea).
    let K = order_param * 1.6 * (1.0 + bass * 0.6);
    let blink = kuramotoBlink(v.id, (v.cell - flow) * 0.5, K, time);

    // Idea 3: face dust — thin sheets where F2 ≈ F1 (the Voronoi faces between nanites), thinned inside
    // bright cell cores so the dark lanes sit *between* the glowing nanites.
    let face = 1.0 - smoothstep(0.0, 0.1, link_density);
    let dust = face * (1.0 - smoothstep(0.35, 0.7, cell_density));

    return NebulaSample(max(0.0, density - 0.3), blink, 1.0 - smoothstep(0.0, 0.3, v.f.x), dust);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) {
        return;
    }
    let uv = vec2<f32>(f32(global_id.x) / res.x, f32(global_id.y) / res.y);
    let p = (uv - 0.5) * 2.0 * vec2<f32>(res.x / res.y, 1.0);

    // Audio reactivity: treble sparkles the nanite glow
    let treble = plasmaBuffer[0].z;
    let bass = plasmaBuffer[0].x;

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(p, 1.0));

    var col = vec3<f32>(0.0);
    var t = 0.0;
    var density_sum = 0.0;
    var firstHitT = -1.0;
    var trans = 1.0; // Idea 3: Beer-Lambert transmittance through the face dust

    for (var i = 0; i < 60; i = i + 1) {
        let pos = ro + rd * t;
        let s = map_density(pos);
        let d = s.density;
        let dt = max(0.05, 0.1 - d*0.05);

        if (d > 0.01) {
            // Idea 1: the cyan nanite glow carries the Kuramoto flash (mean gain ≈ 1 so the average look holds),
            // plus a white-cyan hot core on the flashing nanite itself.
            let biolum = vec3<f32>(0.0, 0.8, 1.0) * d * (0.75 + 1.3 * s.blink)
                       + vec3<f32>(0.75, 1.0, 1.0) * d * s.blink * s.core * 0.8;
            let plasma = vec3<f32>(1.0, 0.0, 0.8) * d * u.zoom_params.y;
            let gold = vec3<f32>(1.0, 0.8, 0.0) * d * u.zoom_params.w;

            let local_col = (biolum + plasma + gold) * (1.0 + treble * 0.8);

            let atten = exp(-t * 0.2);
            col += local_col * atten * 0.1 * trans;
            density_sum += d * 0.1;
            firstHitT = select(firstHitT, t, firstHitT < 0.0);
        }

        // Idea 3: dust absorbs light from everything behind it (emission-only HEAD had no extinction).
        trans *= exp(-0.7 * s.dust * dt);

        if (density_sum > 0.95 || trans < 0.02) {
            break;
        }

        t += dt;
    }
    // (Ray length stays HEAD's: 60 steps x <= 0.1, so t <= 6 — the march ends just past the z = 0 lattice plane.)

    let coverage = min(density_sum + (1.0 - trans) * 0.35, 1.0);
    // Fixed: HEAD's (1 - |p|*0.5) went negative in 16:9 corners and pow() below turned them NaN.
    let bg = vec3<f32>(0.01, 0.02, 0.05) * max(1.0 - length(p)*0.5, 0.0);
    col = col + bg * (1.0 - coverage);

    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.8));

    // Bass-warmed tint (HEAD called this "chromatic aberration"; it is a flat per-channel tint, not an offset)
    let hitDepth = select(0.0, clamp(1.0 - firstHitT / 10.0, 0.0, 1.0), firstHitT >= 0.0);
    let caStr = 0.003 * (1.0 + bass) + hitDepth * 0.001;
    col = max(vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5), vec3<f32>(0.0));

    // Alpha: accumulated nebula opacity (emission + dust) over the cosmic void, never flat 1.0
    let alpha = clamp(coverage + length(bg), 0.0, 1.0);
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);

    let coord = vec2<i32>(global_id.xy);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(hitDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
