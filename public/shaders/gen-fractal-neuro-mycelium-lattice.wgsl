// ═══════════════════════════════════════════════════════════════════
//  Fractal Neuro-Mycelium Lattice
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: action-potential runners along Voronoi edges; synapse flash at nodes
//  A packing: ACES display RGBA (C unused)
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Branch Density, .y = Flow Speed, .z = Glow Intensity, .w = Audio Reactivity
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS = 100;
const MAX_DIST = 30.0;
const SURF_DIST = 0.01;
const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.001), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn voronoi_edges(x: vec3<f32>, flow: f32) -> f32 {
    let p = floor(x);
    let f = fract(x);

    var mb = vec3<f32>(0.0);
    var res = vec3<f32>(8.0);
    var center = vec3<f32>(0.0);

    for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
            for (var k = -1; k <= 1; k++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash33(p + b) + sin(flow + hash33(p + b) * 10.0) * 0.2;
                let d = dot(r, r);

                if (d < res.x) {
                    res.z = res.y;
                    res.y = res.x;
                    res.x = d;
                    mb = b;
                    center = r;
                } else if (d < res.y) {
                    res.z = res.y;
                    res.y = d;
                } else if (d < res.z) {
                    res.z = d;
                }
            }
        }
    }

    var edge_dist = 8.0;
    for (var i = -2; i <= 2; i++) {
        for (var j = -2; j <= 2; j++) {
            for (var k = -2; k <= 2; k++) {
                let b = mb + vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash33(p + b) + sin(flow + hash33(p + b) * 10.0) * 0.2;
                if (dot(r - center, r - center) > 0.00001) {
                    let d = dot(center + r, normalize(r - center));
                    edge_dist = min(edge_dist, d);
                }
            }
        }
    }

    return edge_dist;
}

// returns (sdf, edgeDist, nodeDist)
fn map(p: vec3<f32>, audio: f32) -> vec3<f32> {
    let density = max(u.zoom_params.x, 0.1);
    let flow_speed = u.zoom_params.y;
    let t = u.config.x * flow_speed;

    var pos = p;

    let mouse_pos = (u.zoom_config.yz - 0.5) * 2.0;
    let m_dist = length(pos.xy - mouse_pos * 5.0);
    let pull = smoothstep(3.0, 0.0, m_dist);
    pos.x -= mouse_pos.x * pull * 2.0;
    pos.y -= mouse_pos.y * pull * 2.0;

    pos *= density;

    let d_edges = voronoi_edges(pos, t);

    let base_radius = 0.05 / density;
    let pulse = sin(p.z * 5.0 - t * 10.0) * 0.5 + 0.5;
    let radius = base_radius + pulse * 0.02 * audio * u.zoom_params.w;

    let lattice = abs(d_edges) - radius;
    let node_field = length(fract(pos + 0.5) - 0.5);
    let nodes = node_field - radius * 3.0;

    let d = smin(lattice / density, nodes / density, 0.2 / density);

    return vec3<f32>(d, d_edges, node_field);
}

fn get_normal(p: vec3<f32>, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, audio).x - map(p - e.xyy, audio).x,
        map(p + e.yxy, audio).x - map(p - e.yxy, audio).x,
        map(p + e.yyx, audio).x - map(p - e.yyx, audio).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(id.x) + 0.5, f32(id.y) + 0.5);
    let uv = (fragCoord - 0.5 * resolution) / resolution.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReact = u.zoom_params.w;
    let audio = (bass * 0.55 + mids * 0.35 + treble * 0.10) * audioReact;

    let time = u.config.x * u.zoom_params.y;
    var ro = vec3<f32>(0.0, 0.0, -time * 2.0);
    var ta = vec3<f32>(0.0, 0.0, ro.z - 1.0);

    let mouse = (u.zoom_config.yz - 0.5) * 2.0;
    ro.x += mouse.x * 2.0;
    ro.y -= mouse.y * 2.0;

    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    var dO = 0.0;
    var dS = 0.0;
    var accum = 0.0;
    var p = ro;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let map_res = map(p, audio);
        dS = map_res.x;
        accum += smoothstep(0.1, 0.0, map_res.y) * 0.05;

        if (dS < SURF_DIST) {
            break;
        }
        if (dO > MAX_DIST) {
            break;
        }
        dO += dS;
    }

    var col = vec3<f32>(0.0);
    var runner = 0.0;
    var synapse = 0.0;
    let hit = dO < MAX_DIST;

    if (hit) {
        let n = get_normal(p, audio);
        let light = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let dif = max(dot(n, light), 0.0);

        let sss_dist = 0.1;
        let sss_sample = map(p - n * sss_dist, audio).x;
        let sss = smoothstep(-sss_dist, 0.0, sss_sample);

        let hitMap = map(p, audio);
        let flow_speed = u.zoom_params.y;
        // Idea 1 — action-potential travels in Voronoi-edge distance, not p.z
        let apPhase = fract(hitMap.y * 6.0 - u.config.x * (1.4 + flow_speed * 2.2) - bass * 0.4);
        runner = exp(-pow((apPhase - 0.5) * 9.0, 2.0));

        // Idea 2 — synapse flash at Voronoi sites when the runner arrives
        let nodeProx = 1.0 - smoothstep(0.0, 0.18, hitMap.z);
        synapse = nodeProx * smoothstep(0.35, 0.72, runner);

        let pulse = sin(p.z * 5.0 - u.config.x * 10.0) * 0.5 + 0.5;
        let emit = pulse * audio * u.zoom_params.w * u.zoom_params.z;

        let base_col = vec3<f32>(0.1, 0.3, 0.8) * sss + vec3<f32>(0.8, 0.9, 1.0) * dif * 0.2;
        let glow_col = vec3<f32>(0.0, 1.0, 0.8) * emit;
        col = base_col + glow_col;
        col += vec3<f32>(0.35, 1.0, 0.55) * runner * u.zoom_params.z * 0.85;
        col += vec3<f32>(1.0, 0.95, 0.55) * synapse * (1.4 + treble);

        col = mix(col, vec3<f32>(0.01, 0.02, 0.05), smoothstep(0.0, MAX_DIST, dO));
    }

    col += vec3<f32>(0.1, 0.4, 0.9) * accum * u.zoom_params.z * 0.5;

    let display = acesToneMap(col);
    let alpha = clamp(
        select(0.04, 0.35, hit) + runner * 0.35 + synapse * 0.4 + accum * 0.5,
        0.04,
        1.0
    );
    let depth = select(0.0, clamp(1.0 - dO / MAX_DIST, 0.0, 1.0), hit);
    let coord = vec2<i32>(id.xy);
    let outColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
