// ----------------------------------------------------------------
// Neuro-Kinetic Bloom
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
    zoom_params: vec4<f32>,  // x=Bloom Extension, y=Repulsion Radius, z=Vein Glow, w=Camera Zoom
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let mouse_rot = (u.zoom_config.yz * 2.0 - 1.0) * 3.14;

    let rot_xz = pos.xz * rot(u.config.x * 0.1 + mouse_rot.x);
    pos.x = rot_xz.x;
    pos.z = rot_xz.y;

    let rot_yz = pos.yz * rot(u.config.x * 0.05 + mouse_rot.y);
    pos.y = rot_yz.x;
    pos.z = rot_yz.y;

    // Flora Repetition
    let spacing = 6.0;
    var cell = floor(pos / spacing);
    pos = pos - spacing * round(pos / spacing);

    // Audio-reactive Twist
    let twist_amount = 0.5 + sin(u.config.x * 0.5 + u.config.y) * 0.2;
    let twisted_xy = pos.xy * rot(pos.z * twist_amount);
    pos.x = twisted_xy.x;
    pos.y = twisted_xy.y;

    // Mouse Repulsion
    let mouse_pos = vec3<f32>((u.zoom_config.yz * 2.0 - 1.0) * 10.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        let push = normalize(p - mouse_pos) * (u.zoom_params.y - dist_to_mouse) * 0.5;
        pos = pos + push;
    }

    let branch_length = 3.0 + sin(u.config.y * 2.0) * u.zoom_params.x;
    let d_branch = sdCapsule(pos, vec3<f32>(0.0, 0.0, -branch_length), vec3<f32>(0.0, 0.0, branch_length), 0.3);

    // Vein displacement
    let vein = sin(pos.z * 10.0 - u.config.x * 5.0) * sin(atan2(pos.y, pos.x) * 6.0);
    let final_d = d_branch - vein * 0.05 * u.zoom_params.z;

    return vec2<f32>(final_d * 0.5, vein); // Distance and MatID (vein intensity)
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
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
    let ro = vec3<f32>(0.0, 0.0, -12.0 + u.zoom_params.w);
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

    var col = vec3<f32>(0.02, 0.05, 0.1); // Deep sea void
    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = clamp(dot(n, lig), 0.0, 1.0);

        let baseColor = vec3<f32>(0.05, 0.1, 0.15);
        let veinColor = vec3<f32>(0.0, 1.0, 0.5) * max(0.0, mat_id) * (2.0 + u.config.y);

        col = baseColor * dif + veinColor * u.zoom_params.z;
        col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * t * t));
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
