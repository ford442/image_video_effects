// ----------------------------------------------------------------
// Superfluid Quantum-Foam
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
    zoom_params: vec4<f32>,  // x=Boiling Volatility, y=Vortex Radius, z=Radiation Glow, w=Current Speed
    custom_params: vec4<f32>,
};

fn hash13(p3: vec3<f32>) -> f32 {
    var p3_mod = fract(p3 * 0.1031);
    p3_mod += dot(p3_mod, p3_mod.yzx + 33.33);
    return fract((p3_mod.x + p3_mod.y) * p3_mod.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    pos.x += sin(u.config.x * 0.2 + u.config.y) * 2.0;

    let spacing = 3.0;
    var cell = floor(pos / spacing);
    pos = pos - spacing * round(pos / spacing);

    // Mouse Vortex
    let mouse_pos = vec3<f32>((u.zoom_config.y * 2.0 - 1.0) * 10.0, 0.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        let pull = normalize(mouse_pos - p) * (u.zoom_params.y - dist_to_mouse) * 0.5;
        pos = pos + pull;
        // Vortex Twist
        let s = sin(dist_to_mouse);
        let c = cos(dist_to_mouse);
        let rot = mat2x2<f32>(c, -s, s, c);
        let xz = pos.xz * rot;
        pos.x = xz.x;
        pos.z = xz.y;
    }

    // Audio-reactive boiling
    let boil = hash13(cell) * sin(u.config.x * 3.0 + u.config.y * 5.0) * u.zoom_params.x;
    let radius = 1.0 + boil;

    let d = length(pos) - radius;

    // Smooth union for foam look (simulated in isolation, but opSmoothUnion is better across cells)
    return vec2<f32>(d, hash13(cell));
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize( e.xyy*map( p + e.xyy ).x +
                      e.yyx*map( p + e.yyx ).x +
                      e.yxy*map( p + e.yxy ).x +
                      e.xxx*map( p + e.xxx ).x );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dims = textureDimensions(writeTexture);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);

    let ro = vec3<f32>(0.0, 0.0, -8.0 + u.config.x * u.zoom_params.w);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat_id = 0.0;
    var glow = 0.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);

        // Accumulate volumetric glow for hawking radiation
        if(res.x < 0.5) {
            glow += (0.5 - res.x) * 0.1 * u.zoom_params.z;
        }

        if(res.x < 0.001 || t > 40.0) {
            mat_id = res.y;
            break;
        }
        t += res.x * 0.5; // slow march for soft surfaces
    }

    var col = vec3<f32>(0.02, 0.0, 0.05); // Void background
    if (t < 40.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        // Iridescent Thin-Film
        let ndotv = clamp(dot(n, v), 0.0, 1.0);
        let iridescence = 0.5 + 0.5 * cos(6.28318 * (vec3<f32>(1.0, 1.0, 1.0) * ndotv + vec3<f32>(0.0, 0.33, 0.67)));

        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = clamp(dot(n, lig), 0.0, 1.0);

        let baseColor = mix(vec3<f32>(0.1, 0.1, 0.2), vec3<f32>(iridescence), 0.6);

        col = baseColor * dif;
        col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.02 * t * t));
    }

    // Add hawking radiation glow
    let flash = vec3<f32>(0.8, 0.1, 1.0) * glow * (1.0 + sin(u.config.y * 10.0));
    col += flash;

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
