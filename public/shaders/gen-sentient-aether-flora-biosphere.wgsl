// ----------------------------------------------------------------
// Sentient Aether-Flora Biosphere
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// --- Helper Functions ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Noise, SDF Primitives (sdCylinder, sdSphere), opTwist, opRep
fn sdCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn opTwist(p: vec3<f32>, k: f32) -> vec3<f32> {
    let c = cos(k * p.y);
    let s = sin(k * p.y);
    let m = mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
    let xz = m * p.xz;
    return vec3<f32>(xz.x, p.y, xz.y);
}

// --- Raymarching ---
// map(pos): returns vec2 (distance, material_id)
fn map(pos: vec3<f32>) -> vec2<f32> {
    // Domain Repetition
    let c = vec3<f32>(5.0, 0.0, 5.0);
    let rep_pos = vec3<f32>(pos.x - c.x * floor(pos.x / c.x), pos.y, pos.z - c.z * floor(pos.z / c.z)) - vec3<f32>(c.x * 0.5, 0.0, c.z * 0.5);

    // Flora stems (twisted cylinders)
    var mouse_x = u.zoom_config.y * 2.0 - 1.0;
    let twist_k = 0.5 + 0.2 * sin(u.config.x) + mouse_x * 0.5;
    let twisted_pos = opTwist(rep_pos, twist_k);
    let stem_d = sdCylinder(twisted_pos, 4.0, 0.2);

    // Petals (KIFS-like folded planes + spheres)
    var petal_pos = rep_pos;
    petal_pos.y -= 3.0; // move up
    petal_pos.x = abs(petal_pos.x) - 0.5;
    petal_pos.z = abs(petal_pos.z) - 0.5;
    let bloom_intensity = u.zoom_params.x; // param 1
    let flora_density = u.zoom_params.y; // param 2

    // audio reactivity
    let audio_react = u.zoom_params.w * u.config.y; // using click count as proxy if no audio data
    let petal_d = sdSphere(petal_pos, 1.0 + 0.5 * sin(u.config.x * 2.0 + audio_react));

    let d = smin(stem_d, petal_d, 0.5);

    var mat_id = 1.0;
    if (petal_d < stem_d) { mat_id = 2.0; }

    return vec2<f32>(d, mat_id);
}

// calcNormal(pos): returns vec3 normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy).x +
        e.yyx * map(p + e.yyx).x +
        e.yxy * map(p + e.yxy).x +
        e.xxx * map(p + e.xxx).x
    );
}

// --- Main Compute Shader ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // 1. Setup UVs and Ray (Camera)
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(global_id.xy);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;

    var ro = vec3<f32>(u.config.x * 2.0, 2.0, u.config.x * 2.0 - 5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // camera rotation based on mouse
    let mouse_y = u.zoom_config.z * 2.0 - 1.0;
    let rot = rotate2D(mouse_y);
    rd = vec3<f32>(rd.x, rot[0][0]*rd.y + rot[0][1]*rd.z, rot[1][0]*rd.y + rot[1][1]*rd.z);

    // 2. Raymarch loop
    var t = 0.0;
    var max_t = 50.0;
    var d = 0.0;
    var mat_id = 0.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let map_res = map(p);
        d = map_res.x;
        mat_id = map_res.y;
        if(d < 0.001 || t > max_t) { break; }
        t += d;
    }

    // 3. Shading & Subsurface Scattering approximation
    var color = vec3<f32>(0.0);

    if (t < max_t) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));

        let diff = max(dot(n, l), 0.0);
        let amb = 0.2 + 0.8 * clamp(0.5 + 0.5 * n.y, 0.0, 1.0);

        // base color
        var base_color = vec3<f32>(0.1, 0.8, 0.3); // stem
        if (mat_id == 2.0) {
            base_color = vec3<f32>(0.8, 0.2, 0.6); // petal
        }

        // subsurface scattering approximation
        let sss_sample_dist = 0.5;
        let sss_d = map(p + rd * sss_sample_dist).x;
        let sss = smoothstep(0.0, sss_sample_dist, sss_sample_dist - sss_d);

        // Audio-reactive color shifting
        let audio_react = u.zoom_params.w * u.config.y; // parameter 4
        let color_shift = vec3<f32>(0.5 + 0.5 * sin(u.config.x + p.x), 0.5 + 0.5 * sin(u.config.x + p.y), 0.5 + 0.5 * sin(u.config.x + p.z));
        let shifted_color = mix(base_color, color_shift, audio_react * 0.5);

        color = shifted_color * diff + shifted_color * amb + shifted_color * sss * 0.5;

        // fog
        let fog = exp(-0.02 * t * t);
        color = mix(vec3<f32>(0.05, 0.0, 0.1), color, fog);
    } else {
        // background
        color = vec3<f32>(0.05, 0.0, 0.1);
    }

    // 4. Volumetric Spore accumulation (secondary raymarch step or analytic intersection)
    let spore_count = u.zoom_params.z; // param 3
    var spore_color = vec3<f32>(0.0);

    // simple volumetric spores
    let spore_freq = 2.0;
    var st = 0.0;
    for(var j=0; j<20; j++) {
        let sp = ro + rd * st;
        // domain repeat spores
        let csp = vec3<f32>(spore_freq);
        let rep_sp = sp - csp * floor(sp / csp) - csp * 0.5;

        // mouse gravity well
        let mouse_pos_3d = ro + rd * 5.0 + vec3<f32>(u.zoom_config.y*2.0-1.0, u.zoom_config.z*2.0-1.0, 0.0) * 10.0;
        let dist_to_mouse = length(sp - mouse_pos_3d);
        let gravity = 1.0 / (1.0 + dist_to_mouse * dist_to_mouse);

        let sd = length(rep_sp) - (0.05 + 0.05 * gravity); // Spores grow near mouse

        if (sd < 0.1) {
            spore_color += vec3<f32>(0.5, 0.8, 1.0) * 0.1 * spore_count / 100.0;
        }
        st += 0.5;
    }

    color += spore_color;

    // 6. Output to writeTexture
    let finalColor = vec4<f32>(color, 1.0);
    textureStore(writeTexture, coords, finalColor);
}
