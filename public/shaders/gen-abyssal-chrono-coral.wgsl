// ----------------------------------------------------------------
// Abyssal Chrono-Coral
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
    zoom_params: vec4<f32>,  // x=Coral Density, y=Branch Complexity, z=Bioluminescence Glow, w=Time Dilation Field
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Rotation
fn rotX(angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// 3D FBM noise
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                       dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
                   mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                       dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                       dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
                   mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                       dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        f += amp * noise(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return f;
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// SDF
fn map(p: vec3<f32>, time: f32) -> f32 {
    var pos = p;

    let audio = u.config.y;
    let coralDensity = u.zoom_params.x; // default 0.5
    let branchComplexity = u.zoom_params.y; // default 4.0

    // Domain warping
    pos += vec3<f32>(fbm(pos * 0.5 + time * 0.2), fbm(pos * 0.5 - time * 0.3), fbm(pos * 0.5 + time * 0.1)) * 1.5;

    // KIFS Fractal
    var d = 1000.0;
    var scale = 1.0;

    let iters = i32(clamp(branchComplexity, 1.0, 8.0));

    for (var i = 0; i < iters; i++) {
        pos = abs(pos) - vec3<f32>(1.2, 0.8, 1.5) * coralDensity;
        pos *= rotY(0.5 + audio * 0.1);
        pos *= rotX(0.3);
        pos *= rotZ(0.2);

        let cylinder = length(pos.xy) - 0.2 / scale * (1.0 + audio);
        d = smin(d, cylinder, 0.5 / scale);

        scale *= 1.3;
    }

    // Base surface
    let ground = pos.y + 2.0;
    d = smin(d, ground, 1.0);

    return d;
}

fn getNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time);
    return normalize(vec3<f32>(
        map(p + e.xyy, time) - d,
        map(p + e.yxy, time) - d,
        map(p + e.yyx, time) - d
    ));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let id = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (id.x >= dims.x || id.y >= dims.y) {
        return;
    }

    var uv = (id - 0.5 * dims) / dims.y;

    let time = u.config.x;
    let audio = u.config.y;
    let mouse = u.zoom_config.yz;
    let mouseActive = u.zoom_config.x; // Mouse activity

    let timeDilation = u.zoom_params.w; // default 0.2

    // Mouse interaction: Gravity well time dilation
    var dilatedTime = time;

    // Simple mapped mouse pos for the effect
    let mouseWorldPos = vec3<f32>(mouse.x * 10.0, mouse.y * 10.0, 5.0);

    var ro = vec3<f32>(0.0, 0.0, -time * 2.0); // Camera drifts forward
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Basic camera rotation
    rd *= rotY(sin(time * 0.2) * 0.3);
    rd *= rotX(cos(time * 0.15) * 0.2);

    // Apply time dilation based on mouse
    if (mouseActive > 0.5) {
       let distToMouse = length(ro - mouseWorldPos);
       dilatedTime += (1.0 / (distToMouse + 0.1)) * timeDilation * 50.0;
    }

    var t = 0.0;
    var d = 0.0;
    var p = vec3<f32>(0.0);

    var accum = 0.0;
    var glow = 0.0;
    let bioGlow = u.zoom_params.z; // default 1.0

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        d = map(p, dilatedTime);

        // Volumetric accumulation
        accum += exp(-d * 2.0) * 0.05 * bioGlow * (1.0 + audio * 2.0);

        if (d < 0.001 || t > 30.0) {
            break;
        }

        t += d * 0.6; // Smaller step size for detailed fractals
        glow += 0.01 / (0.01 + d * d);
    }

    var col = vec3<f32>(0.0, 0.05, 0.1); // Deep abyssal blue ambient

    if (t < 30.0) {
        let n = getNormal(p, dilatedTime);
        let l = normalize(vec3<f32>(-1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Coloring based on position and sdf value (approximating depth/subsurface)
        let baseCol = mix(vec3<f32>(0.0, 0.2, 0.4), vec3<f32>(0.1, 0.8, 0.9), fresnel);
        let tipCol = vec3<f32>(0.9, 0.1, 0.6) * (1.0 + audio);

        col = mix(baseCol, tipCol, accum);
        col += vec3<f32>(0.2, 0.6, 0.8) * fresnel * 0.5;
        col *= diff * 0.8 + 0.2;
    }

    // Add glowing fog
    col += vec3<f32>(0.1, 0.3, 0.6) * accum * 0.5;
    col += vec3<f32>(0.8, 0.2, 0.5) * glow * 0.05;

    // Add simple ambient starlight
    col += fbm(rd * 50.0) * vec3<f32>(0.5, 0.7, 1.0) * 0.1;

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}