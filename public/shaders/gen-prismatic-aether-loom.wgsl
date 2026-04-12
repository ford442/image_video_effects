// ----------------------------------------------------------------
// Prismatic Aether-Loom
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Thread Density, y=Braid Complexity, z=Cosmic Wind, w=Chromatic Shift
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// Custom mod function
fn mod_f32(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn hash(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 3D Noise for Cosmic Wind
fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z
    );
}

// Domain Warped FBM
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        v += amp * noise3D(pos);
        pos = pos * 2.0 + vec3<f32>(1.5, 2.5, 3.5);
        amp *= 0.5;
    }
    return v;
}

// Color Palette for Thin-Film Interference
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// KIFS Fold
fn kifsFold(p: vec3<f32>, complexity: f32) -> vec3<f32> {
    var pos = p;
    let n1 = normalize(vec3<f32>(1.0, 1.0, 0.0));
    let n2 = normalize(vec3<f32>(0.0, 1.0, 1.0));
    let iters = i32(complexity);
    for (var i = 0; i < iters; i++) {
        pos.x = abs(pos.x);
        pos.y = abs(pos.y);
        pos.z = abs(pos.z);
        pos -= 2.0 * min(0.0, dot(pos, n1)) * n1;
        pos -= 2.0 * min(0.0, dot(pos, n2)) * n2;
        let rot = rotate2D(0.5);
        let xy = rot * pos.xy;
        pos.x = xy.x; pos.y = xy.y;
    }
    return pos;
}

// Map function
fn map(p: vec3<f32>) -> f32 {
    var pos = p;
    let density = u.zoom_params.x; // Thread Density
    let complexity = u.zoom_params.y; // Braid Complexity
    let wind = u.zoom_params.z; // Cosmic Wind

    // Cosmic Wind Displacement
    let time = u.config.x;
    let audio = u.config.y;
    let windDisp = fbm(pos * 0.5 + time * wind) * wind * (1.0 + audio * 0.5);
    pos += vec3<f32>(windDisp);

    // KIFS Braid
    pos = kifsFold(pos, complexity);

    // Infinite Cylindrical Lattice
    let spacing = 100.0 / density;
    pos.x = mod_f32(pos.x, spacing) - spacing * 0.5;
    pos.y = mod_f32(pos.y, spacing) - spacing * 0.5;

    // Cylinders along Z
    let d1 = length(pos.xy) - 0.1;
    // Cylinders along X
    let d2 = length(pos.yz) - 0.1;
    // Cylinders along Y
    let d3 = length(pos.zx) - 0.1;

    return min(min(d1, d2), d3);
}

// Normal Calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;

    let time = u.config.x;
    let audio = u.config.y;
    let chromaticShift = u.zoom_params.w;

    // Mouse Interaction
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * (res.x / res.y);
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);
    let mousePos = vec2<f32>(mouseX, mouseY);

    var ro = vec3<f32>(0.0, 0.0, -3.0 + time);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Gravity Sheer
    let mouseDist = length(uv - mousePos);
    if (mouseDist < 1.0) {
        let pull = 1.0 - smoothstep(0.0, 1.0, mouseDist);
        let angle = pull * 2.0;
        let rot = rotate2D(angle);
        let rd_xy = rot * rd.xy;
        rd.x = rd_xy.x;
        rd.y = rd_xy.y;
    }

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        t += d * 0.5;
    }

    var col = vec3<f32>(0.0);

    if (t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = -rd;
        let reflDir = reflect(-lightDir, n);
        let spec = pow(max(dot(viewDir, reflDir), 0.0), 32.0);

        // Thin-film interference
        let ndotv = max(dot(n, viewDir), 0.0);
        let phase = ndotv * chromaticShift + time * 0.5;
        let interference = palette(phase,
                                   vec3<f32>(0.5), vec3<f32>(0.5),
                                   vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));

        // Ambient Occlusion (fake)
        let ao = clamp(d / 0.1, 0.0, 1.0);

        col = (interference * diff + vec3<f32>(spec)) * ao;

        // Bioluminescent bloom mapped to audio
        let bloom = interference * audio * 2.0;
        col += bloom;
    }

    // Fog
    col = mix(col, vec3<f32>(0.0, 0.0, 0.1), 1.0 - exp(-0.05 * t * t));

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
