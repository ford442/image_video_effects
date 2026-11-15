// ═══════════════════════════════════════════════════════════════════
//  Harmonic Ferrofluid Kinetics
//  Category: generative
//  Features: mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: Rosensweig tip pinch; crest glint; three-tap crevice AO
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    let q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn voronoi(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    var res = 8.0;
    for (var k = -1; k <= 1; k = k + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            for (var i = -1; i <= 1; i = i + 1) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = vec3<f32>(b) - f + hash3(p + b);
                res = min(res, dot(r, r));
            }
        }
    }
    return sqrt(res);
}

fn map(p: vec3<f32>) -> f32 {
    var pos = p;
    let time = u.config.x * u.zoom_params.y;

    pos.x += sin(pos.z * 0.5 + time) * 0.5;
    pos.z += cos(pos.x * 0.5 + time * 0.8) * 0.5;

    var h = 0.0;
    let spike_scale = max(u.zoom_params.x * 5.0, 0.05);
    let spikes = voronoi(pos * spike_scale) * (2.0 / spike_scale);
    let spikeField = 1.0 - smoothstep(0.0, 0.5, spikes);
    // ── Idea 1: Rosensweig tip pinch ────────────────────────────────
    // The inverted Voronoi spike stays. A power above 1 drops the
    // shoulders and leaves the crest, which is how a real spike pinches.
    h += pow(max(spikeField, 0.0), 1.75);

    let mouse = u.zoom_config.yz;
    let mouse_pos = vec3<f32>((mouse.x - 0.5) * 10.0, 0.0, (mouse.y - 0.5) * 10.0);
    let dist_to_mouse = length(p.xz - mouse_pos.xz);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    h += exp(-dist_to_mouse * 2.0) * 1.5 * held;

    return (p.y - h) * 0.5;
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

fn aoTap(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
    return clamp(map(p + n * h) / max(h * 0.5, 1e-4), 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) { return; }
    let coord = vec2<i32>(id.xy);

    var uv = vec2<f32>(id.xy) / resolution;
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / max(resolution.y, 1.0);

    let ro = vec3<f32>(0.0, 3.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var d0 = 0.0;
    var p = ro;
    var surfaced = false;

    for (var i = 0; i < MAX_STEPS; i = i + 1) {
        p = ro + rd * d0;
        let dS = map(p);
        d0 += dS;
        if (dS < SURF_DIST) {
            surfaced = true;
            break;
        }
        if (d0 > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.05, 0.05, 0.08);
    var fresnel = 0.0;
    var crest = 0.0;
    if (surfaced) {
        let n = get_normal(p);
        let light_dir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let view_dir = normalize(ro - p);
        let half_vec = normalize(light_dir + view_dir);
        let diff = max(dot(n, light_dir), 0.0);
        let spec_power = u.zoom_params.z * 100.0 + 10.0;
        let spec = pow(max(dot(n, half_vec), 0.0), spec_power);
        fresnel = 1.0 - max(dot(n, view_dir), 0.0);
        let iridescence = 0.5 + 0.5 * cos(u.config.x + fresnel * 5.0 + vec3<f32>(0.0, 2.0, 4.0));
        let base_color = vec3<f32>(0.1, 0.1, 0.12);
        col = base_color * diff + iridescence * spec;

        // ── Idea 3: three-tap crevice AO (§12.2E) ───────────────────
        let ao = clamp(aoTap(p, n, 0.08) * 0.5 + aoTap(p, n, 0.22) * 0.3 + aoTap(p, n, 0.5) * 0.2, 0.0, 1.0);
        col *= ao;

        let subsurface = vec3<f32>(0.8, 0.3, 0.1) * fresnel * u.zoom_params.w * ao;
        col += subsurface;

        // ── Idea 2: crest glint ─────────────────────────────────────
        // p.y is the spike height at the hit. An upward normal alone
        // would also light the flat sheet, so the glint asks for both.
        crest = smoothstep(0.62, 0.98, p.y) * smoothstep(0.5, 0.9, n.y);
        col += vec3<f32>(0.85, 0.92, 1.0) * crest * spec * (0.35 + u.zoom_params.z);

        col = mix(col, vec3<f32>(0.05, 0.05, 0.08), 1.0 - exp(-0.02 * d0 * d0));
    }

    let coverage = select(0.0, 1.0, surfaced);
    let alpha = clamp(0.06 + coverage * (0.5 + fresnel * 0.35 + crest * 0.2), 0.0, 1.0);
    let mapped = aces(max(col, vec3<f32>(0.0)));
    let outCol = vec4<f32>(mapped, alpha);
    let depth = select(1.0, clamp(d0 / MAX_DIST, 0.0, 1.0), surfaced);
    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
