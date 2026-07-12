// ═══════════════════════════════════════════════════════════════
//  Neon Edge Diffusion
//  Category: artistic
//  Features: edge-detection, neon-glow, shared-memory, hex-bokeh, upgraded-rgba
// ═══════════════════════════════════════════════════════════════
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.866),
    vec2<f32>(-0.5, 0.866), vec2<f32>(-1.0, 0.0), vec2<f32>(-0.5, -0.866), vec2<f32>(0.5, -0.866)
);
var<workgroup> tile: array<array<vec3<f32>, 18>, 18>;

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>, @builtin(local_invocation_id) lid: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    let pixel = vec2<i32>(gid.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;
    let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;
    let bass = plasmaBuffer[0].x; let treble = plasmaBuffer[0].z;
    let base = vec2<i32>(gid.xy) - vec2<i32>(lid.xy) - vec2<i32>(1);
    for (var y = 0; y < 18; y = y + 1) {
        for (var x = 0; x < 18; x = x + 1) {
            let sp = clamp(base + vec2<i32>(x, y), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
            tile[y][x] = textureLoad(readTexture, sp, 0).rgb;
        }
    }
    workgroupBarrier();
    let lx = i32(lid.x) + 1; let ly = i32(lid.y) + 1;
    let gx = length(tile[ly][lx+1] - tile[ly][lx-1]);
    let gy = length(tile[ly+1][lx] - tile[ly-1][lx]);
    var edge = sqrt(gx * gx + gy * gy);
    let mouse = u.zoom_config.yz;
    edge *= 1.0 + smoothstep(0.2, 0.0, distance(uv, mouse)) * 2.0 * (1.0 + bass * 0.5);
    let radius = (0.003 + p2 * 0.015) * (1.0 + bass * 0.2);
    var glow = vec3<f32>(0.0); var wt = 0.0;
    for (var i = 0; i < 7; i = i + 1) {
        let off = HEX_TAPS[i] * radius;
        let s = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let w = select(0.5, 1.0, i == 0);
        glow += s * w; wt += w;
    }
    var emission = vec3<f32>(edge * 4.0, edge * (1.1 - p4) * 3.0, edge * (0.3 + p4) * 5.0) * (1.0 + p1);
    emission = mix(emission, glow * edge * 5.0 * (1.0 + treble), 0.5);
    for (var i = 0; i < 50; i = i + 1) {
        let r = u.ripples[i];
        let a = time - r.z;
        let hit = step(0.0, r.z) * step(0.0, a) * step(a, 2.0);
        let pulse = sin(distance(uv, r.xy) * 50.0 - a * 10.0) * exp(-a) * hit;
        emission += vec3<f32>(pulse * (1.0 + p3), pulse * 0.7, pulse * 1.3) * r.w;
    }
    emission = aces(emission * (1.0 + bass * 0.2));
    let intensity = luma(emission);
    let alpha = clamp(intensity * (0.2 + p1 * 0.6), 0.0, 0.95);
    let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;
    textureStore(writeTexture, pixel, vec4<f32>(emission + dither, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(edge, intensity, bass, alpha));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth * (1.0 - alpha * 0.5), 0.0, 0.0, 0.0));
}
