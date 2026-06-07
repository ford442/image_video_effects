
// ----------------------------------------------------------------
// Cyber-Organic Liquid-Neon Pulsar
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Base Color Hue, y=Fiber Density, z=Pulsation Speed, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// --- Helper Functions ---
fn hash(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.3183099 + vec3<f32>(0.1, 0.1, 0.1));
    p3 = p3 + dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);

    let n = mix(
        mix(
            mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x),
            u.y
        ),
        mix(
            mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x),
            u.y
        ),
        u.z
    );
    return n;
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    var f = 0.0;
    var amp = 0.5;
    for (var i = 0; i < 4; i = i + 1) {
        f = f + amp * noise(p);
        p = p * 2.0;
        amp = amp * 0.5;
    }
    return f;
}

fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec3<f32>(8.0);
    for (var k = -1; k <= 1; k = k + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            for (var i = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + g);
                let r = g - f + o;
                let d = dot(r, r);
                if (d < m.x) {
                    m = vec3<f32>(d, m.x, m.y);
                } else if (d < m.y) {
                    m = vec3<f32>(m.x, d, m.y);
                }
            }
        }
    }
    return vec2<f32>(sqrt(m.x), sqrt(m.y));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn rot2d(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// --- SDF functions ---
fn map(p_in: vec3<f32>, time: f32, audio: f32) -> f32 {
    var p = p_in;

    // Mouse Interaction
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    // The gravity well effect
    // We treat the z plane as 0 for mouse
    let mouse_p = vec3<f32>(mouse_pos * vec2<f32>(u.config.z / u.config.w, 1.0) * 2.0, 0.0);
    let mouse_dist = length(p.xy - mouse_p.xy);
    let mouse_dir = normalize(vec3<f32>(p.xy - mouse_p.xy, p.z));

    p = p - mouse_dir * smoothstep(0.8, 0.0, mouse_dist) * 0.4;

    // Base sphere
    let d_sphere = length(p) - 1.2;

    // fBM noise for liquid deformation
    let pulse_speed = u.zoom_params.z; // param3
    let disp = fbm(p * 2.5 + time * 0.2 * pulse_speed);

    // Audio pulsation
    let pulse = audio * 0.15 * sin(time * 5.0 * pulse_speed);

    // Liquid core surface
    let core = d_sphere + disp * 0.4 + pulse;

    // Biomechanical metallic fibers using Voronoi
    let fiber_density = u.zoom_params.y; // param2
    let v = voronoi(p * fiber_density + time * 0.1);

    // We want the edges of the voronoi cells to be the fibers
    let fibers = (v.y - v.x) * 0.8;
    // Fibers are tubes along the voronoi edges
    // Subtract from a larger sphere to keep them bounded
    let d_fibers_bounds = length(p) - 1.6 - audio * 0.1;
    let d_fibers = max(d_fibers_bounds, 0.05 - fibers);

    // Blend fibers and core using smin
    return smin(core, d_fibers, 0.2);
}

fn getNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audio) - map(p - e.xyy, time, audio),
        map(p + e.yxy, time, audio) - map(p - e.yxy, time, audio),
        map(p + e.yyx, time, audio) - map(p - e.yyx, time, audio)
    ));
}

fn palette(t: f32) -> vec3<f32> {
    let base_hue = u.zoom_params.x; // param1
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557) + base_hue;
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(id.xy);

    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }

    let resolution = vec2<f32>(dimensions);
    var uv = (vec2<f32>(coords) - 0.5 * resolution) / resolution.y;

    let time = u.config.x;
    let audio = u.config.y;

    // Raymarching setup
    let ro = vec3<f32>(0.0, 0.0, -3.5);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    var p = ro;
    var glow = 0.0;

    let max_steps = 64;
    var hit = false;

    // Raymarching loop
    for (var i = 0; i < max_steps; i = i + 1) {
        p = ro + rd * t;

        // Rotate the whole scene slowly
        let r2 = rot2d(time * 0.1);
        p = vec3<f32>(r2 * p.xz, p.y).xzy;
        let r2_2 = rot2d(time * 0.05);
        p = vec3<f32>(p.x, r2_2 * p.yz);

        d = map(p, time, audio);

        if (d < 0.001) {
            hit = true;
            break;
        }

        // Accumulate volumetric glow inside the bounds
        if (length(p) < 2.0) {
            // Glow intensity based on proximity to the surface and audio
            glow = glow + (0.01 * u.zoom_params.w) / (0.01 + abs(d));
        }

        t = t + d * 0.5; // smaller steps for better detail
        if (t > 10.0) { break; }
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = getNormal(p, time, audio);

        // Lighting
        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let view_dir = normalize(ro - p);
        let refl_dir = reflect(-light_dir, n);
        let spec = pow(max(dot(view_dir, refl_dir), 0.0), 32.0);
        let rim = 1.0 - max(dot(view_dir, n), 0.0);

        // Core vs Fiber detection using Voronoi again
        let fiber_density = u.zoom_params.y;
        let v = voronoi(p * fiber_density + time * 0.1);
        let fibers = (v.y - v.x) * 0.8;

        // Base color based on position and time
        let base_col = palette(length(p) * 0.5 - time * 0.1 + u.zoom_params.x);

        if (fibers < 0.1) {
            // Metallic fibers
            col = vec3<f32>(0.1) + spec * vec3<f32>(1.0) + rim * 0.5 * base_col;
        } else {
            // Liquid Neon Core
            col = base_col * (diff * 0.5 + 0.5) + spec * 0.5;
            // Pulsing emission
            col = col + base_col * (audio * 2.0) * pow(rim, 2.0);
        }
    }

    // Add volumetric god rays / glow
    let glow_col = palette(time * 0.2 + u.zoom_params.x) * glow * 0.05 * u.zoom_params.w;
    col = col + glow_col * (1.0 + audio * 0.5);

    // Background fade
    let bg = vec3<f32>(0.02, 0.01, 0.05) * (1.0 - length(uv));
    col = mix(bg, col, clamp(t / 10.0, 0.0, 1.0));

    // Tonemapping and gamma correction
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
