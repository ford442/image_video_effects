// ----------------------------------------------------------------
// Xeno-Botanical Synth-Flora
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Flora Density, y=Bloom Intensity, z=Cyber-Circuit Glow, w=Growth Warp
    ripples: array<vec4<f32>, 50>,
};

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - 2.0 * f);
    return mix(
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), f2.x),
            mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), f2.x), f2.y),
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), f2.x),
            mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), f2.x), f2.y),
        f2.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        f += w * noise3(pos);
        pos *= 2.0;
        w *= 0.5;
    }
    return f;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn sdCappedCone(p: vec3<f32>, c: vec3<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz), p.y);
    let k1 = vec2<f32>(c.z, c.y);
    let k2 = vec2<f32>(c.z - c.x, 2.0 * c.y);
    let ca = vec2<f32>(q.x - min(q.x, (q.y < 0.0) ? c.x : c.z), abs(q.y) - c.y);
    let cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    var s = -1.0;
    if (cb.x < 0.0 && ca.y < 0.0) { s = 1.0; }
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - c;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

var<private> g_time: f32;
var<private> g_audio: f32;
var<private> g_mouse: vec2<f32>;

fn map(pos_in: vec3<f32>) -> vec2<f32> {
    var p = pos_in;
    var res = vec2<f32>(1000.0, -1.0);

    // Mouse repulsion
    let mouse_dist = length(p.xy - g_mouse * 5.0);
    let repulsion = exp(-mouse_dist * 0.5) * 1.5;
    p.x += repulsion * sign(p.x - g_mouse.x * 5.0);
    p.y += repulsion * sign(p.y - g_mouse.y * 5.0);

    // Domain Repetition for vines
    let spacing = 4.0 / max(0.1, u.zoom_params.x);
    var q = p;
    q.x = q.x - spacing * floor(q.x / spacing) - spacing * 0.5;
    q.z = q.z - spacing * floor(q.z / spacing) - spacing * 0.5;

    // Organic warping
    let warp = sin(q.y * 0.5 + g_time) * u.zoom_params.w;
    q.x += warp;
    q.z += cos(q.y * 0.6 + g_time * 0.8) * u.zoom_params.w;

    // FBM displacement for vines
    let disp = fbm(q * 2.0) * 0.3;

    // Vines (Cylinders)
    var vine_d = sdCylinder(q, vec2<f32>(0.2 + disp, 1000.0));
    if (vine_d < res.x) {
        res = vec2<f32>(vine_d, 1.0); // Material 1: Vines
    }

    // Fractal Blooms (Capped Cones)
    var b = q;
    b.y = b.y - 5.0 * floor(b.y / 5.0) - 2.5; // Repetition along Y
    b.x -= 0.5; // Offset from vine

    // Bloom twist
    let tw = 2.0;
    let s = sin(tw * b.y);
    let c = cos(tw * b.y);
    let m = mat2x2<f32>(c, -s, s, c);
    b = vec3<f32>(m * b.xz, b.y).xzy;

    let bloom_radius = 0.5 + sin(g_time * 2.0 + g_audio) * 0.2 * u.zoom_params.y;
    var bloom_d = sdCappedCone(b, vec3<f32>(0.1, 0.4, bloom_radius));
    // Add some noise to petals
    bloom_d -= fbm(b * 5.0) * 0.1;

    if (bloom_d < res.x) {
        res = vec2<f32>(bloom_d, 2.0); // Material 2: Blooms
    }

    // Liquid Metal Dewdrops
    var dew = q;
    dew.y = dew.y - 2.0 * floor(dew.y / 2.0) - 1.0;
    dew.x += 0.3;
    dew.z -= 0.3;
    var dew_d = sdSphere(dew, 0.15);
    if (dew_d < res.x) {
        res = vec2<f32>(dew_d, 3.0); // Material 3: Dewdrops
    }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

// Subsurface scattering approximation
fn getSSS(p: vec3<f32>, n: vec3<f32>, l: vec3<f32>) -> f32 {
    var sss = 0.0;
    for (var i = 1; i <= 4; i++) {
        let dist = f32(i) * 0.1;
        let d = map(p + l * dist).x;
        sss += max(0.0, dist - d);
    }
    return sss * 0.2;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resX = u.config.z;
    let resY = u.config.w;
    if (f32(id.x) >= resX || f32(id.y) >= resY) { return; }

    g_time = u.config.x;
    g_audio = u.config.y;
    // Map mouse to -1 to 1 space
    g_mouse = vec2<f32>(u.zoom_config.y, -u.zoom_config.z);
    if (u.zoom_config.y == 0.0 && u.zoom_config.z == 0.0) {
        g_mouse = vec2<f32>(0.0);
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * vec2<f32>(resX, resY)) / resY;

    // Camera setup
    var ro = vec3<f32>(0.0, g_time * 2.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Camera slight sway
    rd.xy = rot2D(sin(g_time * 0.5) * 0.1) * rd.xy;
    rd.xz = rot2D(cos(g_time * 0.3) * 0.1) * rd.xz;

    var t = 0.0;
    var m = -1.0;
    var p = vec3<f32>(0.0);

    // Raymarching
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let d = map(p);
        if (d.x < 0.001) {
            m = d.y;
            break;
        }
        if (t > 40.0) {
            break;
        }
        t += d.x * 0.5; // smaller step size for FBM
    }

    var col = vec3<f32>(0.01, 0.02, 0.05); // Dark background

    // Volumetric spores integration
    var spores = 0.0;
    var st = 0.0;
    for (var i = 0; i < 20; i++) {
        let sp = ro + rd * st;
        var spore_val = fbm(sp * 4.0 + vec3<f32>(0.0, g_time, 0.0));
        spores += max(0.0, spore_val - 0.5) * 0.1;
        st += 2.0;
    }
    col += vec3<f32>(0.2, 0.5, 0.8) * spores;

    if (m > -0.5) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));

        let dif = clamp(dot(n, l), 0.0, 1.0);
        let amb = 0.2 + 0.8 * clamp(0.5 + 0.5 * n.y, 0.0, 1.0);
        let sss = getSSS(p, n, l);

        var matCol = vec3<f32>(0.0);
        var emission = vec3<f32>(0.0);

        if (m == 1.0) {
            // Vines: Cybernetic sub-surface
            matCol = vec3<f32>(0.05, 0.15, 0.1);
            // Inner circuitry glowing through FBM gaps
            let cyber_glow = fbm(p * 10.0) * u.zoom_params.z;
            emission = vec3<f32>(0.0, 0.8, 0.5) * max(0.0, cyber_glow - 0.4) * 2.0;

            // Mix in subsurface scattering
            col = matCol * (dif + amb) + vec3<f32>(0.1, 0.4, 0.2) * sss + emission;

        } else if (m == 2.0) {
            // Blooms: Bioluminescent
            let bloom_t = g_time * 0.5 + p.y * 0.1 + g_audio;
            matCol = palette(bloom_t, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
            emission = matCol * u.zoom_params.y * (1.0 + sin(g_time * 4.0 + g_audio) * 0.5);

            col = matCol * (dif + amb) + vec3<f32>(0.5) * sss + emission;

        } else if (m == 3.0) {
            // Dewdrops: Metallic
            let ref = reflect(rd, n);
            let dome = clamp(ref.y, 0.0, 1.0);
            matCol = vec3<f32>(0.8, 0.9, 1.0);

            // Fake environment reflection
            let env = fbm(ref * 3.0 + g_time * 0.2);
            col = matCol * (dif + amb) + vec3<f32>(env * 0.5) + vec3<f32>(1.0) * pow(clamp(dot(ref, l), 0.0, 1.0), 32.0);
        }
    }

    // Fog
    col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * t));

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}