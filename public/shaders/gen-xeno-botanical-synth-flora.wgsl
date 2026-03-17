// ═══════════════════════════════════════════════════════════════
//  Xeno-Botanical Synth-Flora
//  Category: generative
//  Features: Extraterrestrial Foliage, Bioluminescent Blooming, Subsurface Cyber-Scattering, Volumetric Spore Swarm, Interactive Repulsion
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

// Helpers
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1311));
    p3 = p3 + vec3<f32>(dot(p3, p3.yzx + vec3<f32>(19.19)));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - vec2<f32>(2.0) * f);
    return mix(
        mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var p2 = p.xy;
    var f = 0.0;
    var amp = 0.5;
    for (var i = 0; i < 4; i++) {
        f += amp * noise(p2);
        p2 *= vec2<f32>(2.0);
        amp *= 0.5;
    }
    return f;
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(vec3<f32>(6.28318) * (c * vec3<f32>(t) + d));
}

fn opTwist(p: vec3<f32>, k: f32) -> vec3<f32> {
    let c = cos(k * p.y);
    let s = sin(k * p.y);
    let m = mat2x2<f32>(c, -s, s, c);
    let q = vec3<f32>(m * p.xz, p.y);
    return vec3<f32>(q.x, q.z, q.y);
}

fn sdCappedCone(p: vec3<f32>, h: f32, r1: f32, r2: f32) -> f32 {
    let q = vec2<f32>(length(p.xz), p.y);
    let k1 = vec2<f32>(r2, h);
    let k2 = vec2<f32>(r2 - r1, 2.0 * h);
    let ca = vec2<f32>(q.x - min(q.x, select(r2, r1, q.y < 0.0)), abs(q.y) - h);
    let cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    let s = select(1.0, -1.0, cb.x < 0.0 && ca.y < 0.0);
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

fn sdCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Map Function
fn map(p: vec3<f32>) -> vec2<f32> {
    var p_warp = p;

    // Interactive Repulsion (Mouse Interaction)
    let mouse_world = vec3<f32>((u.config.z - 0.5) * 10.0, -(u.config.w - 0.5) * 10.0, 0.0);
    let dist_to_mouse = length(p_warp.xy - mouse_world.xy);
    let repulsion = (1.0 - smoothstep(0.0, 2.0, dist_to_mouse)) * 1.5;
    p_warp.x += repulsion * sign(p_warp.x - mouse_world.x);
    p_warp.y += repulsion * sign(p_warp.y - mouse_world.y);

    // Growth Warp
    p_warp.y += sin(p_warp.x * u.zoom_params.w) * 0.5; // u.zoom_params.w is Growth Warp

    // Domain Repetition
    let cell_size = 4.0 / u.zoom_params.x; // u.zoom_params.x is Flora Density
    var q = p_warp;
    q.x = q.x - cell_size * floor(q.x / cell_size) - cell_size * 0.5;
    q.z = q.z - cell_size * floor(q.z / cell_size) - cell_size * 0.5;

    // Organic vines and fractal blooms
    var d1 = sdCappedCone(opTwist(q, 1.5), 2.0, 0.1, 0.5);

    // FBM displacement
    let disp = fbm(p_warp * vec3<f32>(2.0)) * 0.2;
    d1 -= disp;

    return vec2<f32>(d1, 1.0); // ID 1 for flora
}

// Shading & Lighting
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    );
    return normalize(n);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let uv = (vec2<f32>(id.xy) - 0.5 * dims) / min(dims.x, dims.y);

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var m = 0.0;
    for (var i = 0; i < 64; i++) {
        let p = ro + rd * vec3<f32>(t);
        let d = map(p);
        if (d.x < 0.001 || t > 20.0) {
            m = d.y;
            break;
        }
        t += d.x * 0.5; // Dynamic step size
    }

    var col = vec3<f32>(0.0);
    if (t < 20.0) {
        let p = ro + rd * vec3<f32>(t);
        let n = calcNormal(p);

        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        // Bioluminescence modulated by u.config.y and bloom_intensity
        let baseCol = palette(p.y * 0.5 + u.config.x);
        let bloom = u.zoom_params.y * (0.5 + 0.5 * sin(u.config.y * 10.0 + p.z)); // u.zoom_params.y is Bloom Intensity

        // Subsurface cyber-scattering approximation
        let sss = max(0.0, map(p + n * vec3<f32>(0.1)).x);
        let cyberGlow = u.zoom_params.z * sss; // u.zoom_params.z is Cyber-Circuit Glow

        col = baseCol * vec3<f32>(diff) + vec3<f32>(bloom) * vec3<f32>(0.2, 0.8, 1.0) + vec3<f32>(cyberGlow) * vec3<f32>(1.0, 0.2, 0.5);
    }

    // Volumetric spore swarm
    col += vec3<f32>(0.8, 0.9, 1.0) * vec3<f32>(noise(uv * vec2<f32>(10.0) + vec2<f32>(u.config.x * 2.0)) * 0.1);

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
