// ----------------------------------------------------------------
// Luminescent Quantum-Flora Symphony
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Petal Complexity, y=Gravity Twist, z=Spore Density, w=Core Intensity
    ripples: array<vec4<f32>, 50>,
};

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var p_warp = p;
    // Mouse tension-string interaction
    let mouse = u.zoom_config.yz;
    let delta = p_warp.xy - vec2<f32>(mouse.x * 2.0, mouse.y * 2.0);
    let dist = length(delta);
    let twist_factor = u.zoom_params.y / (1.0 + dist * dist * 4.0);
    let audioBass = plasmaBuffer[0].x;

    // Apply localized twist
    let angle = twist_factor * 3.14159;
    let s = sin(angle);
    let c = cos(angle);
    p_warp.x = delta.x * c - delta.y * s + mouse.x * 2.0;
    p_warp.y = delta.x * s + delta.y * c + mouse.y * 2.0;

    // KIFS Fractal generation driven by u.zoom_params.x...
    let t = u.config.x * 0.5;

    var pos = p_warp;
    var d = 1000.0;

    for (var i = 0; i < 4; i++) {
        pos.y = abs(pos.y) - u.zoom_params.x * 0.2;
        let r = rot2D(t * 0.2 + f32(i) * 0.5 + audioBass * 0.1);
        pos.x = r[0].x * pos.x + r[1].x * pos.y;
        pos.y = r[0].y * pos.x + r[1].y * pos.y;

        let sphere = length(pos) - 0.5;
        d = smin(d, sphere, 0.2);
    }

    return vec2<f32>(d, 1.0); // ID 1.0
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }
    let uv = vec2<f32>(f32(id.x) / f32(dimensions.x), f32(id.y) / f32(dimensions.y)) * 2.0 - 1.0;
    let aspect = f32(dimensions.x) / f32(dimensions.y);
    let screen_uv = vec2<f32>(uv.x * aspect, uv.y);

    // Core pixel calculation and shading logic...
    var ro = vec3<f32>(0.0, 0.0, 3.0);
    var rd = normalize(vec3<f32>(screen_uv, -1.0));

    var t = 0.0;
    var col = vec3<f32>(0.0);
    for (var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d.x < 0.001) {
            col = vec3<f32>(0.2, 0.8, 1.0) * (1.0 - f32(i)/64.0) * u.zoom_params.w;
            break;
        }
        t += d.x;
        // Spore density / volumetric approx
        if (t > 10.0) { break; }
        col += vec3<f32>(0.01, 0.05, 0.1) * u.zoom_params.z;
    }

    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(col, 1.0));
}
