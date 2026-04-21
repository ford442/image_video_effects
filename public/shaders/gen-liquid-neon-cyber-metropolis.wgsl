// ----------------------------------------------------------------
// Liquid-Neon Cyber-Metropolis
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
    zoom_params: vec4<f32>,  // x=Neon Intensity, y=City Density, z=Audio Reactivity, w=Gravity Warp Strength
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn opSmoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

fn opSmoothSubtraction(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 - 0.5 * (d2 + d1) / k, 0.0, 1.0);
    return mix(d2, -d1, h) + k * h * (1.0 - h);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

struct MapResult {
    d: f32,
    mat: f32, // 0.0 = concrete, 1.0 = neon
}

fn map(pos_in: vec3<f32>) -> MapResult {
    var p = pos_in;

    // Gravity warp (Mouse interaction)
    // u.zoom_config.y, z = MouseX, MouseY (-1 to 1)
    let warpCenter = vec3<f32>(u.zoom_config.y * 10.0, 0.0, u.zoom_config.z * 10.0);
    let diff = p - warpCenter;
    let distToCenter = length(diff);
    let warpStrength = u.zoom_params.w; // Gravity Warp Strength
    let warpRadius = 15.0;
    if (distToCenter < warpRadius) {
        let warpFactor = pow(1.0 - distToCenter/warpRadius, 2.0) * warpStrength;
        p -= normalize(diff) * warpFactor * 5.0;
    }

    // Infinite domain repetition
    let cellDensity = u.zoom_params.y; // City Density (10.0 default)
    let cellSpacing = 50.0 / cellDensity;
    let gridId = floor(p.xz / cellSpacing);
    p.x = p.x - cellSpacing * round(p.x / cellSpacing);
    p.z = p.z - cellSpacing * round(p.z / cellSpacing);

    // Audio Reactivity
    let audio = u.config.y * u.zoom_params.z;

    // City block height variation
    let h = hash3(vec3<f32>(gridId.x, 0.0, gridId.y));
    let baseHeight = 2.0 + h.x * 5.0 + audio * 3.0 * h.y;

    // Concrete Skyscraper Base
    var d_concrete = sdBox(p - vec3<f32>(0.0, baseHeight, 0.0), vec3<f32>(cellSpacing*0.35, baseHeight, cellSpacing*0.35));

    // KIFS Top detail
    var q = p - vec3<f32>(0.0, baseHeight * 2.0, 0.0);
    for (var i = 0; i < 3; i++) {
        q = abs(q) - vec3<f32>(0.1, 0.5, 0.1);
        let rotYZ = rotate2D(0.5);
        let qYZ = rotYZ * vec2<f32>(q.y, q.z);
        q.y = qYZ.x; q.z = qYZ.y;
    }
    let d_kifs = sdBox(q, vec3<f32>(cellSpacing*0.1, 1.0, cellSpacing*0.1));
    d_concrete = opSmoothUnion(d_concrete, d_kifs, 0.5);

    // Neon Veins (Carved out of concrete using smooth subtraction)
    // Create a pulsing vein pattern
    let veinThickness = 0.05 + 0.05 * sin(u.config.x * 2.0 + p.y * 5.0);
    let d_veins = sdBox(p - vec3<f32>(0.0, baseHeight, 0.0), vec3<f32>(cellSpacing*0.36, baseHeight*0.9, cellSpacing*0.36)) - veinThickness;

    d_concrete = opSmoothSubtraction(d_veins, d_concrete, 0.1);

    var res: MapResult;
    if (d_concrete < d_veins) {
        res.d = d_concrete;
        res.mat = 0.0;
    } else {
        res.d = d_veins;
        res.mat = 1.0;
    }

    // Ground plane
    let d_ground = p.y + 0.1;
    if (d_ground < res.d) {
        res.d = d_ground;
        res.mat = 0.0;
    }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize( e.xyy*map( p + e.xyy ).d +
                      e.yyx*map( p + e.yyx ).d +
                      e.yxy*map( p + e.yxy ).d +
                      e.xxx*map( p + e.xxx ).d );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;

    // Camera setup
    let time = u.config.x;
    let camRadius = 25.0;
    let camSpeed = time * 0.2;
    var ro = vec3<f32>(sin(camSpeed) * camRadius, 10.0 + sin(time*0.5)*2.0, cos(camSpeed) * camRadius);
    let ta = vec3<f32>(0.0, 2.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var t = 0.0;
    let max_steps = 100;
    let max_dist = 100.0;
    var mapRes: MapResult;
    var glow = 0.0;

    for (var i = 0; i < max_steps; i++) {
        let p = ro + rd * t;
        mapRes = map(p);

        // Volumetric neon bloom accumulation
        if (mapRes.mat == 1.0) {
           glow += 0.01 / (0.01 + abs(mapRes.d)) * u.zoom_params.x; // Neon Intensity
        }

        if (abs(mapRes.d) < 0.001 || t > max_dist) { break; }
        t += mapRes.d * 0.7; // slightly reduced step size for safety
    }

    var col = vec3<f32>(0.0);

    if (t < max_dist) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.5));
        let dif = clamp(dot(n, lightDir), 0.0, 1.0);
        let amb = 0.1;

        if (mapRes.mat == 0.0) {
            // Concrete
            col = vec3<f32>(0.05, 0.05, 0.08) * (dif + amb);
            // Fake reflections (rain-slicked look)
            let ref = reflect(rd, n);
            col += vec3<f32>(0.1) * clamp(dot(ref, lightDir), 0.0, 1.0);
        } else {
            // Neon
            let neonColor = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(time + p.y)*0.5+0.5);
            col = neonColor * u.zoom_params.x; // Neon Intensity
        }

        // Fog
        let fogAmount = 1.0 - exp(-t * 0.02);
        col = mix(col, vec3<f32>(0.01, 0.01, 0.03), fogAmount);
    }

    // Add Neon Bloom
    let bloomColor = mix(vec3<f32>(0.0, 0.5, 1.0), vec3<f32>(1.0, 0.0, 0.5), sin(time*0.5)*0.5+0.5);
    col += bloomColor * glow * 0.02;

    // Output
    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
