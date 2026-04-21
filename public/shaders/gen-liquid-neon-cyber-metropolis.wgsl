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

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

fn boxSDF(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

struct MapResult {
    d: f32,
    mat: f32, // 0.0 for concrete, 1.0 for neon
}

fn map(p_in: vec3<f32>) -> MapResult {
    var p = p_in;

    // Gravity warp based on mouse
    let mousePos = vec3<f32>((u.zoom_config.y - 0.5) * 20.0, 0.0, (u.zoom_config.z - 0.5) * 20.0);
    let distToMouse = length(p.xz - mousePos.xz);
    let warpStrength = u.zoom_params.w;
    if (distToMouse < 10.0 && warpStrength > 0.0) {
        let warpAmt = (10.0 - distToMouse) / 10.0;
        let warpOffset = normalize(p - vec3<f32>(mousePos.x, p.y, mousePos.z)) * warpAmt * warpStrength * 5.0;
        p -= warpOffset * vec3<f32>(1.0, 0.2, 1.0);
    }

    let density = max(1.0, 30.0 - u.zoom_params.y); // UI slider: City Density
    let repSize = density * 0.2;

    // Infinite Domain Repetition
    let cellId = floor((p.xz + repSize * 0.5) / repSize);
    var q = p;
    q.x = (fract(p.x / repSize + 0.5) - 0.5) * repSize;
    q.z = (fract(p.z / repSize + 0.5) - 0.5) * repSize;

    // Audio Reactivity & Height
    let audioAmp = u.config.y * u.zoom_params.z;
    let hHash = fract(sin(dot(cellId, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let baseHeight = 2.0 + hHash * 8.0;
    let animHeight = baseHeight + sin(u.config.x * 2.0 + hHash * 10.0) * audioAmp * 3.0;

    // Base Building Box
    let bSize = vec3<f32>(repSize * 0.35, animHeight, repSize * 0.35);
    var dConcrete = boxSDF(q - vec3<f32>(0.0, animHeight, 0.0), bSize);

    // KIFS Folds for Architecture
    var kifsP = q - vec3<f32>(0.0, animHeight * 2.0, 0.0);
    for (var i = 0; i < 3; i++) {
        kifsP = abs(kifsP) - vec3<f32>(0.2, 0.5, 0.2);
        let rot1 = rot2D(0.5);
        let kxy = rot1 * kifsP.xy;
        kifsP.x = kxy.x; kifsP.y = kxy.y;
        let kxz = rot1 * kifsP.xz;
        kifsP.x = kxz.x; kifsP.z = kxz.y;
    }
    let kifsBox = boxSDF(kifsP, vec3<f32>(0.1, 2.0, 0.1));
    dConcrete = min(dConcrete, kifsBox);

    // Neon Veins (smooth subtracted / intersecting)
    let neonSize = vec3<f32>(repSize * 0.4, animHeight * 1.2, repSize * 0.4);
    var dNeon = boxSDF(q - vec3<f32>(0.0, animHeight, 0.0), neonSize) + 0.1 * sin(q.y * 10.0 - u.config.x * 5.0);

    // Floor
    let dFloor = p.y;
    dConcrete = smin(dConcrete, dFloor, 0.5);

    var res: MapResult;
    // Mix them slightly
    res.d = smin(dConcrete, dNeon + 0.1, 0.2);
    if (dNeon < dConcrete + 0.05) { res.mat = 1.0; } else { res.mat = 0.0; }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }
    let uv = (fragCoord - 0.5 * res) / res.y;

    // Camera setup
    let time = u.config.x * 0.2;
    var ro = vec3<f32>(time * 5.0, 15.0, time * 5.0 - 10.0);
    var ta = ro + vec3<f32>(cos(time * 0.5), -0.5, sin(time * 0.5));

    // Mouse camera sway
    let mx = (u.zoom_config.y - 0.5) * 2.0;
    let my = (u.zoom_config.z - 0.5) * 2.0;
    ro.x += mx * 5.0;
    ro.y -= my * 5.0;
    ta.x += mx * 5.0;

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.0 * cw);

    // Raymarching
    var t = 0.0;
    var maxD = 100.0;
    var mat = 0.0;
    var glow = 0.0;
    var hit = false;

    for (var i = 0; i < 150; i++) {
        let p = ro + rd * t;
        let resMap = map(p);
        if (resMap.d < 0.001) {
            hit = true;
            mat = resMap.mat;
            break;
        }
        if (t > maxD) { break; }
        t += resMap.d;

        // Accumulate glow from neon
        if (resMap.mat > 0.5) {
            glow += 0.01 / (0.1 + abs(resMap.d)) * u.zoom_params.x;
        }
    }

    // Coloring
    var col = vec3<f32>(0.0);
    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        let albedo = vec3<f32>(0.05, 0.06, 0.08);

        let lig = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let dif = max(dot(n, lig), 0.0);
        let amb = 0.1 + 0.9 * max(n.y, 0.0);

        if (mat < 0.5) {
            col = albedo * (dif * 0.5 + amb);
            let scan = fract(length(p.xz) * 0.1 - u.config.x * 2.0);
            if (scan < 0.05) {
                col += vec3<f32>(0.0, 0.5, 1.0) * (1.0 - scan/0.05);
            }
        } else {
            let hue = fract(p.y * 0.05 + u.config.x * 0.2);
            let neonCol = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), hue);
            col = neonCol * 2.0 * u.zoom_params.x;
        }

        if (mat < 0.5) {
            let ref = reflect(rd, n);
            let refGlow = max(0.0, dot(ref, vec3<f32>(0.0, 1.0, 0.0))) * 0.2;
            col += vec3<f32>(0.0, 1.0, 1.0) * refGlow * u.zoom_params.x;
        }
    }

    let glowCol = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.0, 0.8), fract(u.config.x * 0.1));
    col += glowCol * glow * 0.1;

    col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.0005 * t * t));

    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
