// ----------------------------------------------------------------
// Sentient Aether-Plasma Nebula-Moth
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash33(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash33(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash33(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(dot(hash33(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash33(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash33(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for(var i = 0; i < 5; i++) {
        f += amp * noise(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sceneSDF(p: vec3<f32>, time: f32, flutter: f32, audioBass: f32) -> vec2<f32> {
    var d = 1000.0;
    var matId = 0.0; // 0 = thorax, 1 = wings, 2 = glass

    // Thorax (Ellipsoid)
    let thoraxDist = sdEllipsoid(p, vec3<f32>(0.5, 0.8, 0.5));
    d = thoraxDist;
    matId = 0.0;

    // Head
    var hp = p - vec3<f32>(0.0, 1.0, 0.2);
    let headDist = sdEllipsoid(hp, vec3<f32>(0.3, 0.3, 0.3));
    if (headDist < d) {
        d = smin(d, headDist, 0.2);
    }

    // Wings
    var wp = p;
    wp.x = abs(wp.x); // symmetry
    wp.x -= 0.6;

    // Flutter animation
    let flutterAnim = sin(time * 10.0 * flutter) * 0.5 * wp.x;
    wp.y += flutterAnim;
    wp.z += flutterAnim * 0.5;

    // Wing basic shape (flattened ellipsoid)
    let wingBase = sdEllipsoid(wp, vec3<f32>(1.5, 1.2, 0.05));

    // Fractal displacement for wings
    let wingDisp = fbm(wp * 3.0 + vec3<f32>(0.0, 0.0, time)) * 0.2;
    let wingDist = wingBase + wingDisp;

    if (wingDist < d) {
        d = smin(d, wingDist, 0.1);
        matId = 1.0;
    }

    // Chrono-glass shards
    var sp = p;
    sp.y -= time * 0.5; // falling
    sp = fract(sp * 2.0) - 0.5; // repeating
    let shardDist = length(sp) - 0.05;

    // Mask shards to only appear near wings
    let mask = sdEllipsoid(p, vec3<f32>(3.0, 2.0, 1.0));
    let finalShard = max(shardDist, mask);

    if (finalShard < d) {
        d = finalShard;
        matId = 2.0;
    }

    return vec2<f32>(d, matId);
}

fn calcNormal(p: vec3<f32>, time: f32, flutter: f32, audioBass: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.001;
    return normalize(
        e.xyy * sceneSDF(p + e.xyy, time, flutter, audioBass).x +
        e.yyx * sceneSDF(p + e.yyx, time, flutter, audioBass).x +
        e.yxy * sceneSDF(p + e.yxy, time, flutter, audioBass).x +
        e.xxx * sceneSDF(p + e.xxx, time, flutter, audioBass).x
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }
    let uv = (fragCoord * 2.0 - res) / res.y;
    let coord = vec2<i32>(id.xy);

    let time = u.config.x * 0.5;

    // UI Sliders
    let flutterFreq = u.zoom_params.x;
    let stormInt = u.zoom_params.y;
    let plasmaGlow = u.zoom_params.z;
    let riftDist = u.zoom_params.w;

    let audioBass = plasmaBuffer[0].x;

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * PI;
    let mouseY = (u.zoom_config.z * 2.0 - 1.0) * PI * 0.5;

    let rotX = rot(-mouseY);
    let rotY = rot(mouseX);

    ro.y = ro.y * rotX[0][0] + ro.z * rotX[1][0];
    ro.z = ro.y * rotX[0][1] + ro.z * rotX[1][1];

    ro.x = ro.x * rotY[0][0] + ro.z * rotY[1][0];
    ro.z = ro.x * rotY[0][1] + ro.z * rotY[1][1];

    rd.y = rd.y * rotX[0][0] + rd.z * rotX[1][0];
    rd.z = rd.y * rotX[0][1] + rd.z * rotX[1][1];

    rd.x = rd.x * rotY[0][0] + rd.z * rotY[1][0];
    rd.z = rd.x * rotY[0][1] + rd.z * rotY[1][1];


    var t = 0.0;
    var hit = false;
    var hitMat = 0.0;
    var hitP = vec3<f32>(0.0);
    var glowVol = 0.0;

    for (var i = 0; i < 100; i++) {
        var p = ro + rd * t;

        // Quantum storm distortion
        p += vec3<f32>(noise(p * 2.0 + time), noise(p * 2.0 - time), noise(p * 2.0)) * stormInt * 0.1;
        // Time rift distortion
        p.x += sin(p.y * 5.0 + time) * riftDist * 0.5;

        let res = sceneSDF(p, time, flutterFreq, audioBass);
        let d = res.x;

        // Accumulate glow near wings (matId 1.0)
        if (res.y == 1.0) {
            glowVol += 0.01 / (0.1 + abs(d));
        }

        if (d < 0.001) {
            hit = true;
            hitP = p;
            hitMat = res.y;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d * 0.7; // Step size reduction for domain distortion
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(hitP, time, flutterFreq, audioBass);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = -rd;
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(n, halfDir), 0.0), 32.0);

        if (hitMat == 0.0) {
            // Thorax (Glowing liquid-aurora)
            let baseColor = vec3<f32>(0.1, 0.8, 0.6); // Auroral green
            col = baseColor * diff + vec3<f32>(1.0) * spec;
            col += baseColor * audioBass * 0.5; // Audio reactive glow
        } else if (hitMat == 1.0) {
            // Wings (Aether-Plasma)
            let baseColor = vec3<f32>(0.2, 0.4, 1.0); // Bioluminescent cyan/purple
            col = baseColor * diff + vec3<f32>(1.0) * spec;
            col += baseColor * plasmaGlow * 0.5;
        } else if (hitMat == 2.0) {
            // Chrono-glass shards
            col = vec3<f32>(0.8, 0.9, 1.0) * diff + vec3<f32>(1.0) * spec * 2.0;
        }
    } else {
        // Background Particle Storm (Void)
        let stormDens = noise(rd * 10.0 + time * 0.5) * stormInt;
        col = vec3<f32>(0.05, 0.0, 0.1) * stormDens;
    }

    // Add volumetric glow
    col += vec3<f32>(0.1, 0.5, 0.8) * glowVol * plasmaGlow * 0.2;

    col = acesToneMap(col);

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
