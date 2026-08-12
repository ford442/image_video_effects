// ----------------------------------------------------------------
// Prismatic Quantum-Glass Chrysalis-Engine
// Category: generative
// ----------------------------------------------------------------

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
  resolution: vec2<f32>,
  time: f32,
  frame: u32,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  view_matrix: mat4x4<f32>,
  proj_matrix: mat4x4<f32>,
  camera_pos: vec3<f32>,
  config: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  var q = abs(p);
  return (q.x + q.y + q.z - s) * 0.57735027;
}

fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let q = abs(p);
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735);
    var p2 = q.xy;
    p2 = p2 - 2.0 * min(dot(k.xy, p2), 0.0) * k.xy;
    let d1 = p2 - vec2<f32>(clamp(p2.x, -k.z * h.x, k.z * h.x), h.x);
    let d2 = vec2<f32>(length(d1) * sign(d1.y), q.z - h.y);
    return min(max(d2.x, d2.y), 0.0) + length(max(d2, vec2<f32>(0.0)));
}

// 3D Voronoi / noise helper for cuts
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn voronoi3(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec3<f32>(8.0);
    var res = vec2<f32>(8.0);
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
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
    return sqrt(res);
}

fn map(p: vec3<f32>) -> f32 {
    let mouse = u.zoom_config.yz;
    let rSpeed = u.zoom_params.z; // Core Rotation Speed

    var pos = p;
    pos = vec3<f32>(rot(u.time * rSpeed * 0.5) * pos.xy, pos.z);
    pos = vec3<f32>(pos.x, rot(u.time * rSpeed * 0.7) * pos.yz);

    let d1 = sdOctahedron(pos, 2.0);
    let d2 = sdHexPrism(pos, vec2<f32>(1.5, 1.8));
    var d = max(d1, d2);

    // cuts
    let v = voronoi3(pos * 2.0);
    let crack = (v.y - v.x) * 0.5;
    d = max(d, -crack + 0.1);

    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let id = vec2<f32>(global_id.xy);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let uv = (id - 0.5 * dims) / min(dims.x, dims.y);
    let mouse = u.zoom_config.yz;

    // Parameters
    let ior = mix(1.0, 2.5, u.zoom_params.x);
    let plasmaIntensity = mix(0.0, 3.0, u.zoom_params.y);
    let chromDisp = mix(0.0, 1.0, u.zoom_params.w);

    // Audio ripple impact (audio-reactive)
    var audioReact = 0.0;
    if (u.ripples[0].x > 0.0) {
       audioReact = u.ripples[0].x * 0.1;
    }

    // Camera
    var ro = vec3<f32>(0.0, 0.0, -5.0 + audioReact);
    ro = vec3<f32>(rot(mouse.x * 6.28) * ro.xz, ro.y).xzy;
    ro = vec3<f32>(ro.x, rot(mouse.y * 3.14) * ro.yz);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var t = 0.0;
    var hit = false;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001) { hit = true; break; }
        if (t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    let bgCol = vec3<f32>(0.02, 0.0, 0.08) - length(uv)*0.1;
    col = bgCol;

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // internal liquid plasma (volumetric-like estimation via SDF value deep inside)
        let internalP = p - n * 0.1;
        let plasmaDist = map(internalP);
        let plasmaCol = vec3<f32>(1.0, 0.2, 0.8) * exp(-abs(plasmaDist) * 5.0) * plasmaIntensity;
        let cyanCore = vec3<f32>(0.0, 0.8, 1.0) * exp(-abs(plasmaDist) * 10.0) * plasmaIntensity * 2.0;

        // Refraction / thin film
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let thinFilm = vec3<f32>(
           sin(fresnel * 10.0 + chromDisp) * 0.5 + 0.5,
           sin(fresnel * 15.0) * 0.5 + 0.5,
           sin(fresnel * 20.0 - chromDisp) * 0.5 + 0.5
        ) * 0.5;

        let glass = mix(vec3<f32>(0.1, 0.1, 0.2), thinFilm, fresnel);
        col = glass + plasmaCol + cyanCore;

        // Chromatic aberration fake trail
        col += vec3<f32>(chromDisp * 0.2, 0.0, 0.0) * fract(u.time);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
