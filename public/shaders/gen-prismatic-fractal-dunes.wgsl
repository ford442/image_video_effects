// ----------------------------------------------------------------
// Prismatic Fractal-Dunes
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
    zoom_params: vec4<f32>,  // x=Dune Complexity, y=Prism Dispersion, z=Geyser Height, w=Wind Speed
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var mat = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = mat * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn map(p: vec3<f32>) -> vec2<f32> {
    let time = u.config.x * u.zoom_params.w * 0.5;
    let audio = u.config.y;
    let complexity = u.zoom_params.x;

    // Terrain heightmap using domain warped FBM
    var wp = p.xz;
    wp += vec2<f32>(fbm(wp + time, 4), fbm(wp - time, 4)) * 0.5;
    let h = fbm(wp, i32(complexity)) * 2.0;

    // Smooth-min crater for mouse interaction
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let mouse_world = vec2<f32>(mouse.x * 10.0, mouse.y * 10.0);
    let d_mouse = length(p.xz - mouse_world);
    let crater = smoothstep(0.0, 3.0, d_mouse) * 2.0 - 1.5;

    let d_terrain = p.y + h + crater;

    // KIFS crystal geysers
    var q = p;
    q.y -= h;
    let height_mod = u.zoom_params.z * audio * 2.0;

    for (var i = 0; i < 4; i++) {
        q = abs(q) - vec3<f32>(0.5, 1.0 + height_mod, 0.5);
        let new_xz = rotate2D(time + f32(i)) * vec2<f32>(q.x, q.z);
        q.x = new_xz.x;
        q.z = new_xz.y;
        let new_xy = rotate2D(time * 0.5) * vec2<f32>(q.x, q.y);
        q.x = new_xy.x;
        q.y = new_xy.y;
    }
    let d_crystals = (length(q) - 0.2) * 0.8;

    if (d_terrain < d_crystals) {
        return vec2<f32>(d_terrain, 1.0); // 1.0 for terrain
    } else {
        return vec2<f32>(d_crystals, 2.0); // 2.0 for crystals
    }
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e.x, e.y, e.y)).x - map(p - vec3<f32>(e.x, e.y, e.y)).x,
        map(p + vec3<f32>(e.y, e.x, e.y)).x - map(p - vec3<f32>(e.y, e.x, e.y)).x,
        map(p + vec3<f32>(e.y, e.y, e.x)).x - map(p - vec3<f32>(e.y, e.y, e.x)).x
    ));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;

    // Parameters
    let duneComplexity = u.zoom_params.x;
    let dispersion = u.zoom_params.y;
    let geyserHeight = u.zoom_params.z;
    let windSpeed = u.zoom_params.w;

    // Ray setup
    let ro = vec3<f32>(0.0, 3.0, -5.0 + time * windSpeed);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var m = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d.x < 0.001 || t > 50.0) {
            m = d.y;
            break;
        }
        t += d.x;
    }

    var col = vec3<f32>(0.05, 0.05, 0.1) * (uv.y + 0.5);

    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let l1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let l2 = normalize(vec3<f32>(-1.0, 0.5, 1.0));

        let diff1 = max(dot(n, l1), 0.0);
        let diff2 = max(dot(n, l2), 0.0);

        // Chromatic dispersion pseudo-effect
        let viewDir = -rd;
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        if (m == 1.0) { // Terrain
            let sandCol = vec3<f32>(0.8, 0.6, 0.4);
            let prismOff = vec3<f32>(dispersion * 0.1, 0.0, -dispersion * 0.1);
            let r = max(dot(calcNormal(p + vec3<f32>(prismOff.x, prismOff.x, prismOff.y)), l1), 0.0);
            let g = max(dot(calcNormal(p), l1), 0.0);
            let b = max(dot(calcNormal(p + vec3<f32>(prismOff.z, prismOff.z, prismOff.y)), l1), 0.0);
            col = sandCol * vec3<f32>(r, g, b) + diff2 * vec3<f32>(0.2, 0.3, 0.5);
            col += fresnel * vec3<f32>(1.0, 0.8, 0.6);
        } else { // Crystals
            let crystalBase = vec3<f32>(0.1, 0.8, 0.9);
            col = crystalBase * diff1 * (1.0 + audio * 2.0);
            col += fresnel * vec3<f32>(1.0, 0.2, 0.8) * audio * 3.0;
        }
    }

    // Fog
    col = mix(col, vec3<f32>(0.05, 0.05, 0.1), 1.0 - exp(-0.02 * t));

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
