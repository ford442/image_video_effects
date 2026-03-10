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
    config: vec4<f32>,       // x=Time, y=MouseClickCount/Audio, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Complexity, y=Iridescence, z=CrystalScale, w=FogDensity
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Prismatic Bismuth Lattice
// Category: generative
// ----------------------------------------------------------------

const PI: f32 = 3.14159265359;

// --- Noise Functions ---
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - vec2<f32>(2.0) * f);

    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)),
                   hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)),
                   hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pos = p;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 4; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// --- SDF Primitives ---
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn mat2(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// --- Map Function ---
fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let time = u.config.x;
    let audio = u.config.y; // Audio-reactive folding

    // Mouse-driven localized spatial twist
    let mouse = u.zoom_config.yz;
    let camZ = time * 2.0;
    let mouseX = (mouse.x - 0.5) * 20.0;
    let mouseY = -(mouse.y - 0.5) * 20.0;
    let warpCenter = vec3<f32>(mouseX, mouseY, camZ + 10.0);

    let distToMouse = length(p - warpCenter);
    let warpRadius = 8.0;
    if (distToMouse < warpRadius) {
        let twistFactor = (1.0 - distToMouse / warpRadius) * 2.0;
        let r = mat2(twistFactor * sin(time));
        let xz = r * p.xz;
        p.x = xz.x;
        p.z = xz.y;
    }

    // Domain Repetition
    let scale = u.zoom_params.z; // Crystal Scale
    let c = vec3<f32>(4.0 * scale);
    var q = p;
    q = (fract(q / c + vec3<f32>(0.5)) - vec3<f32>(0.5)) * c;

    // Recursive Box for Hopper Crystal
    let complexity = i32(u.zoom_params.x); // 1 to 6
    var d = 1000.0;

    // Audio-reactive folding effect
    let fold = 1.0 + audio * 0.1 * sin(time * 2.0);

    // Generate step sizes based on ID
    let id = floor(p / c + vec3<f32>(0.5));
    let h = hash(id.xz + vec2<f32>(id.y));

    var size = vec3<f32>(1.5 * scale);
    var current_d = sdBox(q, size);

    for (var i = 0; i < complexity; i++) {
        let fi = f32(i);
        size -= vec3<f32>(0.2 * scale * fold);
        var inner_box = sdBox(q + vec3<f32>(0.0, 0.1 * fi * scale, 0.0), size);

        if (i % 2 == 1) {
            current_d = max(current_d, -inner_box);
        } else {
            current_d = min(current_d, inner_box);
        }
    }

    // Add subtle displacement
    current_d += fbm(p.xz * 2.0) * 0.1 * scale;
    d = current_d;

    return vec2<f32>(d, h);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var mat = 0.0;
    for(var i=0; i<100; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        mat = res.y;
        if(d < 0.001 || t > 50.0) { break; }
        t += d;
    }
    return vec2<f32>(t, mat);
}

// Thin-film interference iridescence
fn pal(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(vec3<f32>(2.0 * PI) * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = (vec2<f32>(global_id.xy) - resolution * vec2<f32>(0.5)) / vec2<f32>(resolution.y);
    let time = u.config.x;

    // Camera setup
    let camZ = time * 2.0;
    let ro = vec3<f32>(0.0, 0.0, camZ);
    let target = vec3<f32>(0.0, 0.0, camZ + 1.0);

    let forward = normalize(target - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    let rd = normalize(forward + right * vec3<f32>(uv.x) + up * vec3<f32>(uv.y));

    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;

    var color = vec3<f32>(0.0);
    let fogDensity = u.zoom_params.w;
    let fogColor = vec3<f32>(0.05, 0.0, 0.1); // Deep purple/black void

    if (t < 50.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);

        let viewDir = normalize(ro - p);
        let ndotv = max(dot(n, viewDir), 0.0);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 32.0);

        // Iridescence / Thin-film interference
        let irid_strength = u.zoom_params.y;
        let thickness = mat + u.config.y * 0.1; // Mat is hash, adds variation + audio react

        // Cosine based palette for iridescence
        let a = vec3<f32>(0.5, 0.5, 0.5);
        let b = vec3<f32>(0.5, 0.5, 0.5);
        let c = vec3<f32>(1.0, 1.0, 1.0);
        let d = vec3<f32>(0.0, 0.33, 0.67);

        // The color shifts based on view angle and thickness
        let irid_color = pal(ndotv * 2.0 + thickness, a, b, c, d);

        // Base metallic color
        let base_color = vec3<f32>(0.2, 0.2, 0.2);

        // Mix base and iridescence
        var mat_color = mix(base_color, irid_color, vec3<f32>(irid_strength));

        color = mat_color * vec3<f32>(diff * 0.5 + 0.5) + vec3<f32>(spec);

        // Audio reactive glow on edges (simulated by ndotv being small)
        let edge = smoothstep(0.4, 0.0, ndotv);
        color += irid_color * vec3<f32>(edge * u.config.y * 2.0);

        // Volumetric Prismatic Fog
        let fogAmount = 1.0 - exp(-t * fogDensity * 0.1);
        color = mix(color, fogColor, vec3<f32>(fogAmount));
    } else {
        color = fogColor;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 50.0, 0.0, 0.0, 0.0));
}
