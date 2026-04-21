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
    mat: f32, // 0.0 = concrete, 1.0 = neon
};

fn map(p_in: vec3<f32>) -> MapResult {
    var p = p_in;

    // === Gravity Warp (Mouse Interaction) ===
    let mousePos = vec3<f32>(
        (u.zoom_config.y - 0.5) * 20.0,
        0.0,
        (u.zoom_config.z - 0.5) * 20.0
    );
    let distToMouse = length(p.xz - mousePos.xz);
    let warpStrength = u.zoom_params.w;
    if (distToMouse < 12.0 && warpStrength > 0.0) {
        let warpAmt = (12.0 - distToMouse) / 12.0;
        let warpDir = normalize(vec3<f32>(p.x - mousePos.x, 0.0, p.z - mousePos.z));
        p.x -= warpDir.x * warpAmt * warpStrength * 6.0;
        p.z -= warpDir.z * warpAmt * warpStrength * 6.0;
    }

    // === City Density & Repetition ===
    let density = max(1.0, 30.0 - u.zoom_params.y); // higher slider = denser city
    let repSize = density * 0.22;

    let cellId = floor((p.xz + repSize * 0.5) / repSize);
    var q = p;
    q.x = (fract(p.x / repSize + 0.5) - 0.5) * repSize;
    q.z = (fract(p.z / repSize + 0.5) - 0.5) * repSize;

    // === Audio Reactivity + Height Variation ===
    let audioAmp = u.config.y * u.zoom_params.z;
    let hHash = fract(sin(dot(cellId, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let baseHeight = 2.5 + hHash * 9.0;
    let animHeight = baseHeight + sin(u.config.x * 2.5 + hHash * 12.0) * audioAmp * 3.5;

    // Base building
    let bSize = vec3<f32>(repSize * 0.36, animHeight, repSize * 0.36);
    var dConcrete = boxSDF(q - vec3<f32>(0.0, animHeight * 0.5, 0.0), bSize);

    // KIFS architectural detail on top
    var kifsP = q - vec3<f32>(0.0, animHeight * 1.8, 0.0);
    for (var i = 0; i < 4; i++) {
        kifsP = abs(kifsP) - vec3<f32>(0.18, 0.55, 0.18);
        let r = rot2D(0.45 + sin(u.config.x * 0.1) * 0.1);
        let kxy = r * kifsP.xy;
        kifsP.x = kxy.x; kifsP.y = kxy.y;
    }
    let dKifs = boxSDF(kifsP, vec3<f32>(0.12, 1.8, 0.12));
    dConcrete = min(dConcrete, dKifs);

    // Neon veins (slightly larger + pulsing)
    let neonSize = vec3<f32>(repSize * 0.39, animHeight * 1.15, repSize * 0.39);
    var dNeon = boxSDF(q - vec3<f32>(0.0, animHeight * 0.5, 0.0), neonSize)
                + 0.08 * sin(q.y * 14.0 - u.config.x * 6.0);

    // Ground plane
    let dFloor = p.y + 0.05;
    dConcrete = smin(dConcrete, dFloor, 0.6);

    // Final result
    var res: MapResult;
    res.d = smin(dConcrete, dNeon, 0.15);

    if (dNeon < dConcrete - 0.03) {
        res.mat = 1.0; // neon
    } else {
        res.mat = 0.0; // concrete
    }

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

    // Camera
    let time = u.config.x;
    let camTime = time * 0.15;
    var ro = vec3<f32>(
        sin(camTime) * 28.0,
        14.0 + sin(time * 0.3) * 3.0,
        cos(camTime) * 28.0 + 8.0
    );

    // Mouse influence on camera
    let mx = (u.zoom_config.y - 0.5) * 12.0;
    let my = (u.zoom_config.z - 0.5) * 8.0;
    ro.x += mx;
    ro.y += my * 0.6;

    let ta = vec3<f32>(mx * 0.6, 3.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.2 * cw);

    // Raymarching
    var t = 0.0;
    var hit = false;
    var mat = 0.0;
    var glow = 0.0;
    let maxSteps = 160;
    let maxDist = 120.0;

    for (var i = 0; i < maxSteps; i++) {
        let p = ro + rd * t;
        let resMap = map(p);

        if (resMap.d < 0.001) {
            hit = true;
            mat = resMap.mat;
            break;
        }
        if (t > maxDist) { break; }

        t += resMap.d * 0.75;

        // Neon glow accumulation
        if (resMap.mat > 0.5) {
            glow += 0.012 / (0.08 + abs(resMap.d)) * u.zoom_params.x;
        }
    }

    // Shading
    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        let lig = normalize(vec3<f32>(0.6, 1.0, -0.4));
        let dif = max(dot(n, lig), 0.0);
        let amb = 0.12 + 0.88 * max(n.y, 0.0);

        if (mat < 0.5) {
            // Concrete
            col = vec3<f32>(0.045, 0.05, 0.07) * (dif * 0.7 + amb);
            
            // Subtle scanning lines
            let scan = fract(length(p.xz) * 0.08 - time * 3.0);
            if (scan < 0.04) {
                col += vec3<f32>(0.0, 0.4, 0.9) * (0.6 - scan * 15.0);
            }
        } else {
            // Neon
            let hue = fract(p.y * 0.04 + time * 0.25);
            let neonCol = mix(vec3<f32>(0.0, 1.0, 1.2), vec3<f32>(1.1, 0.0, 1.1), hue);
            col = neonCol * (1.8 + sin(time * 8.0 + p.y * 10.0) * 0.6) * u.zoom_params.x;
        }

        // Fake specular reflection
        if (mat < 0.5) {
            let ref = reflect(rd, n);
            let refGlow = max(0.0, dot(ref, vec3<f32>(0.0, 1.0, 0.0))) * 0.35;
            col += vec3<f32>(0.1, 0.7, 1.0) * refGlow * u.zoom_params.x;
        }
    }

    // Global neon bloom
    let bloomCol = mix(vec3<f32>(0.0, 0.85, 1.1), vec3<f32>(1.0, 0.1, 0.9), sin(time * 0.8) * 0.5 + 0.5);
    col += bloomCol * glow * 0.13;

    // Fog
    col = mix(col, vec3<f32>(0.008, 0.012, 0.035), 1.0 - exp(-0.0008 * t * t));

    // Tonemapping + gamma
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}