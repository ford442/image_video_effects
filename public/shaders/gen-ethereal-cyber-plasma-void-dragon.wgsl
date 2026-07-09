struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Plasma Intensity, y=Dragon Undulation Speed, z=Body Segment Density, w=Nebula Density
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Ethereal Cyber-Plasma Void-Dragon
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

const PI: f32 = 3.14159265359;

fn rot2D(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n = i.x + i.y * 157.0 + 113.0 * i.z;
    let res = mix(
        mix(
            mix(fract(sin(n + 0.0) * 43758.5453123), fract(sin(n + 1.0) * 43758.5453123), u.x),
            mix(fract(sin(n + 157.0) * 43758.5453123), fract(sin(n + 158.0) * 43758.5453123), u.x),
            u.y
        ),
        mix(
            mix(fract(sin(n + 113.0) * 43758.5453123), fract(sin(n + 114.0) * 43758.5453123), u.x),
            mix(fract(sin(n + 270.0) * 43758.5453123), fract(sin(n + 271.0) * 43758.5453123), u.x),
            u.y
        ),
        u.z
    );
    return res;
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p_mut = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(p_mut);
        p_mut = p_mut * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

struct MapResult {
    d: f32,
    mat: f32, // 0 = void, 1 = dragon body, 2 = glowing plasma
}

fn map(p: vec3<f32>) -> MapResult {
    var res = MapResult(1000.0, 0.0);

    let time = u.config.x;
    let audio = u.config.y;
    let plasma_int = u.zoom_params.x;
    let undulate_spd = u.zoom_params.y;
    let seg_density = u.zoom_params.z;

    // Dragon path
    var d_dragon = 1000.0;

    let t_und = time * undulate_spd;
    let num_segs = i32(seg_density);

    // Smooth trailing path
    var prev_pos = vec3<f32>(0.0);
    for (var i = 0; i < 40; i++) {
        if (i > num_segs) { break; }
        let fi = f32(i);
        let segment_t = t_und - fi * 0.15;

        // Undulation
        let x = sin(segment_t) * 2.0 + sin(segment_t * 0.4) * 3.0;
        let y = cos(segment_t * 0.7) * 1.5 + sin(segment_t * 1.3) * 1.0;
        let z = -fi * 0.5 + sin(segment_t * 0.2) * 2.0;

        var pos = vec3<f32>(x, y, z);

        // Mouse interaction for the head (i=0) and trailing effect
        let mx = (u.zoom_config.y - 0.5) * 10.0;
        let my = -(u.zoom_config.z - 0.5) * 10.0;
        let mouse_target = vec3<f32>(mx, my, 0.0);

        // Pull towards mouse based on segment distance from head
        let pull_factor = exp(-fi * 0.1);
        pos = mix(pos, mouse_target + vec3<f32>(0.0, 0.0, -fi * 0.5), pull_factor * 0.8);

        let radius = 0.3 + 0.2 * sin(fi * 0.3) - (fi / f32(num_segs)) * 0.2 + audio * 0.1;

        if (i > 0) {
            let d_seg = sdCapsule(p, prev_pos, pos, radius);
            d_dragon = smin(d_dragon, d_seg, 0.8);
        }
        prev_pos = pos;
    }

    // Scales/Details displacement
    let scale_noise = fbm(p * 5.0 + time * 0.5) * 0.1;
    d_dragon += scale_noise;

    // Glowing plasma core (internal)
    let d_plasma = d_dragon + 0.1 - audio * 0.05;

    if (d_dragon < res.d) {
        res.d = d_dragon;
        res.mat = 1.0;
    }
    if (d_plasma < res.d) {
        res.d = d_plasma;
        res.mat = 2.0;
    }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.001;
    return normalize(
        e.xyy * map(p + e.xyy).d +
        e.yyx * map(p + e.yyx).d +
        e.yxy * map(p + e.yxy).d +
        e.xxx * map(p + e.xxx).d
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    let uv = (fragCoord - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;

    let plasma_int = u.zoom_params.x;
    let nebula_dens = u.zoom_params.w;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, 10.0);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Mouse rotation
    let mx = (u.zoom_config.y - 0.5) * PI;
    let my = (u.zoom_config.z - 0.5) * PI;

    let rotY = rot2D(-mx);
    let rotX = rot2D(my);

    let ro_yz = rotX * ro.yz;
    ro.y = ro_yz.x;
    ro.z = ro_yz.y;
    let rd_yz = rotX * rd.yz;
    rd.y = rd_yz.x;
    rd.z = rd_yz.y;

    let ro_xz = rotY * ro.xz;
    ro.x = ro_xz.x;
    ro.z = ro_xz.y;
    let rd_xz = rotY * rd.xz;
    rd.x = rd_xz.x;
    rd.z = rd_xz.y;

    // Raymarching
    var t = 0.0;
    var mat_type = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res_map = map(p);

        if (res_map.d < 0.001) {
            mat_type = res_map.mat;
            break;
        }

        // Volumetric accumulation for plasma breath / inner glow
        if (res_map.d < 1.5) {
            glow += (0.01 / (res_map.d * res_map.d + 0.01)) * plasma_int;
        }

        t += res_map.d;
        if (t > 50.0) { break; }
    }

    var col = vec3<f32>(0.0);

    // Background Nebula
    let bg_dir = rd;
    let nebula = fbm(bg_dir * 3.0 + vec3<f32>(time * 0.1, 0.0, time * 0.05));
    let dark_matter = fbm(bg_dir * 8.0 - time * 0.2);
    let bg_col = mix(vec3<f32>(0.05, 0.0, 0.1), vec3<f32>(0.1, 0.3, 0.5), nebula) * nebula_dens;
    col += bg_col * (1.0 - dark_matter * 0.5);

    // Dragon shading
    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, 3.0));

        let diff = max(dot(n, l), 0.0);
        let view = normalize(ro - p);
        let fresnel = pow(1.0 - max(dot(n, view), 0.0), 3.0);

        if (mat_type == 1.0) {
            // Scales - Iridescent Metallic
            let iridescence = cos(fresnel * PI * 2.0 + vec3<f32>(0.0, 2.0, 4.0)) * 0.5 + 0.5;
            let base_col = vec3<f32>(0.1, 0.15, 0.2);
            col = base_col * diff + iridescence * fresnel;
        } else if (mat_type == 2.0) {
            // Internal Plasma
            col = vec3<f32>(0.0, 0.8, 1.0) * plasma_int * (1.0 + audio * 2.0);
        }
    }

    // Add accumulated volumetric glow
    let glow_col = vec3<f32>(0.1, 0.5, 1.0) * glow * 0.05;
    col += glow_col;

    // Audio flashes
    col += vec3<f32>(0.8, 0.2, 1.0) * audio * fbm(rd * 10.0 + time) * plasma_int * 0.2;

    // Tonemapping
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
