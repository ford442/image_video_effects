// ----------------------------------------------------------------
// Kinetic Neo-Brutalist Megastructure
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
    zoom_params: vec4<f32>,  // x=Block Density, y=Repulsion Radius, z=Neon Intensity, w=Travel Speed
    ripples: array<vec4<f32>, 50>,
};

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn hash13(p3: vec3<f32>) -> f32 {
    var p3_mod = fract(p3 * 0.1031);
    p3_mod += dot(p3_mod, p3_mod.yzx + 33.33);
    return fract((p3_mod.x + p3_mod.y) * p3_mod.z);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    pos.x += sin(u.config.x * 0.5 + u.config.y) * 2.0;

    let spacing = 4.0;
    var cell = floor(pos / spacing);
    pos = pos - spacing * round(pos / spacing);

    var d = sdBox(pos, vec3<f32>(1.5, 1.8, 1.5));
    let d_sub = sdBox(pos, vec3<f32>(1.6, 0.5, 0.5));
    d = max(d, -d_sub);

    let resX = u.config.z;
    let resY = u.config.w;
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * 10.0;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0) * 10.0;

    let mouse_pos = vec3<f32>(mouseX, mouseY, 5.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        d += (u.zoom_params.y - dist_to_mouse) * 0.5;
    }

    return vec2<f32>(d, hash13(cell));
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize( e.xyy*map( p + e.xyy ).x +
                      e.yyx*map( p + e.yyx ).x +
                      e.yxy*map( p + e.yxy ).x +
                      e.xxx*map( p + e.xxx ).x );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dims = vec2<i32>(i32(u.config.z), i32(u.config.w));
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);

    let ro = vec3<f32>(0.0, 0.0, -10.0 + u.config.x * u.zoom_params.w);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat_id = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if(res.x < 0.001 || t > 50.0) {
            mat_id = res.y;
            break;
        }
        t += res.x;
    }

    var col = vec3<f32>(0.01);
    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = clamp(dot(n, lig), 0.0, 1.0);

        var baseColor = vec3<f32>(0.3, 0.32, 0.35);
        let neon = vec3<f32>(0.0, 1.0, 0.8) * mat_id * (0.5 + 0.5 * sin(u.config.y * 10.0));

        col = baseColor * dif * u.zoom_params.x + neon * u.zoom_params.z;
        col = mix(col, vec3<f32>(0.05, 0.05, 0.08), 1.0 - exp(-0.02 * t * t));
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
