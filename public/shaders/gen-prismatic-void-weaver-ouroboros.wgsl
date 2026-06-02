// ----------------------------------------------------------------
// Prismatic Void-Weaver Ouroboros
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
    zoom_params: vec4<f32>,  // x=Twist Density, y=Plasma Glow, z=Void Gravity, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 3D Noise for fractal scales
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxy * f);

    let n = i.x + i.y * 157.0 + i.z * 113.0;

    // Smooth random interpolation
    return mix(
        mix(mix(fract(sin(n + 0.0) * 43758.5453123), fract(sin(n + 1.0) * 43758.5453123), u.x),
            mix(fract(sin(n + 157.0) * 43758.5453123), fract(sin(n + 158.0) * 43758.5453123), u.x), u.y),
        mix(mix(fract(sin(n + 113.0) * 43758.5453123), fract(sin(n + 114.0) * 43758.5453123), u.x),
            mix(fract(sin(n + 270.0) * 43758.5453123), fract(sin(n + 271.0) * 43758.5453123), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for(var i=0; i<4; i++) {
        f += amp * noise3(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return f;
}

// Polynomial smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdfOuroboros(p_in: vec3<f32>, time: f32) -> f32 {
    var p = p_in;

    // Void Gravity (mouse interaction)
    let mx = (u.zoom_config.y * 2.0 - 1.0) * 2.0;
    let my = (u.zoom_config.z * 2.0 - 1.0) * 2.0;
    let voidCenter = vec3<f32>(mx, -my, 0.0);

    let distToVoid = length(p - voidCenter);
    let gravity = u.zoom_params.z;

    // Gravitational lensing/bending
    if (distToVoid > 0.0) {
        let pull = gravity / (distToVoid * distToVoid + 0.1);
        p -= normalize(p - voidCenter) * pull * 0.1;
    }

    // Twist Density
    let twist = u.zoom_params.x;
    let angle = atan2(p.z, p.x);

    // Transform to torus space
    let t_xy = vec2<f32>(length(p.xz) - 2.5, p.y);

    // Twist the cross section
    let rot = rotate2D(angle * twist + time * 0.5);
    var q = vec3<f32>(rot * t_xy, 0.0);

    // Base Torus
    let baseSdf = length(t_xy) - 0.8;

    // Fractal Scales
    let audioReact = u.zoom_params.w;
    let audio = u.config.y * audioReact * 2.0;
    let scaleDisplacement = fbm(p * 3.0 + vec3<f32>(time * 0.2)) * 0.2;

    return baseSdf - scaleDisplacement * (1.0 + audio);
}

fn getNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        sdfOuroboros(p + e.xyy, time) - sdfOuroboros(p - e.xyy, time),
        sdfOuroboros(p + e.yxy, time) - sdfOuroboros(p - e.yxy, time),
        sdfOuroboros(p + e.yyx, time) - sdfOuroboros(p - e.yyx, time)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
    let time = u.config.x;

    var ro = vec3<f32>(0.0, 0.0, -6.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slow camera rotation
    let camRot = rotate2D(time * 0.1);
    let new_ro_xz = camRot * vec2<f32>(ro.x, ro.z);
    ro.x = new_ro_xz.x;
    ro.z = new_ro_xz.y;
    let new_rd_xz = camRot * vec2<f32>(rd.x, rd.z);
    rd.x = new_rd_xz.x;
    rd.z = new_rd_xz.y;

    var dO = 0.0;
    var dS = 0.0;
    var p = ro;

    // Raymarching
    for(var i=0; i<MAX_STEPS; i++) {
        p = ro + rd * dO;
        dS = sdfOuroboros(p, time);
        dO += dS * 0.8; // Step size reduction for twisted SDFs
        if(dS < SURF_DIST || dO > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.0);

    let mx = (u.zoom_config.y * 2.0 - 1.0) * 2.0;
    let my = (u.zoom_config.z * 2.0 - 1.0) * 2.0;
    let voidCenter = vec3<f32>(mx, -my, 0.0);

    // Background / Void
    let distToVoidBg = length(ro + rd * min(dO, 20.0) - voidCenter);
    let voidGlow = exp(-distToVoidBg * 0.5) * vec3<f32>(0.5, 0.1, 0.8) * u.zoom_params.y;

    if(dO < MAX_DIST) {
        let n = getNormal(p, time);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));

        // Lighting
        let diff = max(dot(n, l), 0.0);
        let viewDir = normalize(ro - p);
        let refl = reflect(-l, n);
        let spec = pow(max(dot(viewDir, refl), 0.0), 32.0);

        // Chromatic dispersion color
        let matCol = vec3<f32>(
            0.5 + 0.5 * sin(time + p.x * 2.0 + 0.0),
            0.5 + 0.5 * sin(time + p.y * 2.0 + 2.0),
            0.5 + 0.5 * sin(time + p.z * 2.0 + 4.0)
        ) * 0.8 + vec3<f32>(0.2);

        // Dark matter core darkening
        let darkMatter = clamp(length(p.xz) - 1.5, 0.0, 1.0);

        col = matCol * diff * darkMatter + spec * vec3<f32>(0.8, 0.9, 1.0);

        // Plasma aura
        let audioReact = u.config.y * u.zoom_params.w;
        let emission = clamp(fbm(p * 5.0 - vec3<f32>(time)), 0.0, 1.0) * u.zoom_params.y * (1.0 + audioReact);
        col += matCol * emission * vec3<f32>(1.5, 0.5, 2.0);

        // Distance fog
        col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.02 * dO * dO));
    }

    col += voidGlow;

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
