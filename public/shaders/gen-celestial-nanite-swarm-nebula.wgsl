// ═══════════════════════════════════════════════════════════════════
//  Celestial Nanite-Swarm Nebula
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-06-06
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Swarm Density, y=Constellation Link, z=Wind Speed, w=Geometric Order
    ripples: array<vec4<f32>, 50>,
};

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec3<f32>(8.0);
    var res = vec2<f32>(8.0);

    for (var k: i32 = -1; k <= 1; k = k + 1) {
        for (var j: i32 = -1; j <= 1; j = j + 1) {
            for (var i: i32 = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g - f + o;
                let d = dot(r, r);

                if (d < res.x) {
                    res.y = res.x;
                    res.x = d;
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(res.x), sqrt(res.y));
}

fn map_density(p: vec3<f32>) -> f32 {
    let density_param = u.zoom_params.x;
    let link_param = u.zoom_params.y;
    let wind_param = u.zoom_params.z;
    let order_param = u.zoom_params.w;

    var pos = p;
    let t = u.config.x * (0.2 + wind_param * 0.5);

    pos.x += sin(t * 0.5) * 2.0;
    pos.z += cos(t * 0.3) * 2.0;

    let mx = (u.zoom_config.y - 0.5) * 10.0;
    let my = (u.zoom_config.z - 0.5) * 10.0;
    let mouse_pos = vec3<f32>(mx, my, 0.0);
    let dist_to_mouse = length(pos - mouse_pos);
    let pull = exp(-dist_to_mouse * 0.5) * 2.0;

    if (dist_to_mouse > 0.01) {
        pos = mix(pos, mouse_pos, pull * 0.1);
    }

    let v = voronoi(pos * 2.0 + vec3<f32>(t, t*0.5, -t));
    let cell_density = 1.0 - v.x;
    let link_density = v.y - v.x;

    var density = cell_density * (0.5 + density_param * 0.5);
    density += link_density * link_param * 0.5;

    var q = pos;
    q.x = q.x - round(q.x / 4.0) * 4.0;
    q.y = q.y - round(q.y / 4.0) * 4.0;
    q.z = q.z - round(q.z / 4.0) * 4.0;

    let box_d = length(max(abs(q) - vec3<f32>(0.5), vec3<f32>(0.0))) - 0.1;
    let shape_density = smoothstep(0.5, 0.0, box_d);

    // Bass swells the constellation links (correct audio source)
    let audio_react = plasmaBuffer[0].x * 0.5;

    density = mix(density, density * shape_density * 2.0, order_param);
    density += audio_react * link_density;

    return max(0.0, density - 0.3);
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

    for (var i = 0; i < 60; i = i + 1) {
        let pos = ro + rd * t;
        let d = map_density(pos);

        if (d > 0.01) {
            let biolum = vec3<f32>(0.0, 0.8, 1.0) * d;
            let plasma = vec3<f32>(1.0, 0.0, 0.8) * d * u.zoom_params.y;
            let gold = vec3<f32>(1.0, 0.8, 0.0) * d * u.zoom_params.w;

            let local_col = (biolum + plasma + gold) * (1.0 + treble * 0.8);

            let atten = exp(-t * 0.2);
            col += local_col * atten * 0.1;
            density_sum += d * 0.1;
            firstHitT = select(firstHitT, t, firstHitT < 0.0);
        }

        if (density_sum > 0.95) {
            break;
        }

        t += max(0.05, 0.1 - d*0.05);
    }

    let coverage = min(density_sum, 1.0);
    let bg = vec3<f32>(0.01, 0.02, 0.05) * (1.0 - length(p)*0.5);
    col = col + bg * (1.0 - coverage);

    col = pow(col, vec3<f32>(0.8));

    // Chromatic aberration
    let hitDepth = select(0.0, clamp(1.0 - firstHitT / 10.0, 0.0, 1.0), firstHitT >= 0.0);
    let caStr = 0.003 * (1.0 + bass) + hitDepth * 0.001;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Alpha: accumulated nebula opacity over the cosmic void, never flat 1.0
    let alpha = clamp(coverage + length(bg), 0.0, 1.0);
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);

    let coord = vec2<i32>(global_id.xy);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(hitDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
