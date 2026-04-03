// ----------------------------------------------------------------
// Prismatic Fractal-Dunes
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
    zoom_params: vec4<f32>,  // x=Dune Complexity, y=Prism Dispersion, z=Geyser Height, w=Wind Speed
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var mat = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = mat * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>, duneComplexity: f32, windSpeed: f32, geyserHeight: f32, audio: f32, time: f32, mousePos: vec3<f32>) -> vec2<f32> {
    var d = 1000.0;
    var mat = 0.0;

    // Domain warping for dunes
    let wp1 = p.xz * 0.5 + vec2<f32>(time * windSpeed * 0.2, time * windSpeed * 0.1);
    let warpX = fbm(wp1, 3);
    let warpY = fbm(wp1 + vec2<f32>(5.2, 1.3), 3);
    let warpedP = p.xz * (0.2 * duneComplexity) + vec2<f32>(warpX, warpY) * 2.0;

    // Base dune height
    var height = fbm(warpedP, 6) * 3.0;

    // Geyser logic (KIFS)
    var q = p;
    q.y -= height;

    // Distort space near geyser points
    let geyserGrid = fract(p.xz * 0.5) - 0.5;
    let cellId = floor(p.xz * 0.5);
    let h = hash21(cellId);

    var geyserD = 1000.0;
    if (h > 0.8) {
        // Active geyser
        let localQ = vec3<f32>(geyserGrid.x, q.y, geyserGrid.y);

        // Simple KIFS fold for shard
        var shardP = localQ;
        shardP.y -= audio * geyserHeight * 2.0;

        for (var i = 0; i < 4; i++) {
            shardP.x = abs(shardP.x);
            shardP.z = abs(shardP.z);
            let rot = rotate2D(time + f32(i));
            let rTemp = rot * shardP.xz;
            shardP.x = rTemp.x;
            shardP.z = rTemp.y;
            shardP *= 1.5;
            shardP.y -= 0.5;
        }

        geyserD = (length(shardP) - 0.1) * pow(1.5, -4.0);
    }

    // Mouse crater interaction
    let mouseDist = length(p.xz - mousePos.xz);
    let crater = smoothstep(0.0, 3.0, mouseDist) * 2.0 - 1.0;
    height += crater * 1.5;

    // Pull shards to mouse
    if (mouseDist < 3.0) {
        geyserD = smin(geyserD, length(p - mousePos) - 0.5, 1.0);
    }

    let duneD = p.y - height;

    if (duneD < geyserD) {
        d = duneD;
        mat = 1.0; // Sand
    } else {
        d = geyserD;
        mat = 2.0; // Crystal
    }

    return vec2<f32>(d, mat);
}

fn calcNormal(p: vec3<f32>, duneComplexity: f32, windSpeed: f32, geyserHeight: f32, audio: f32, time: f32, mousePos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, duneComplexity, windSpeed, geyserHeight, audio, time, mousePos).x;
    let n = vec3<f32>(
        map(p + e.xyy, duneComplexity, windSpeed, geyserHeight, audio, time, mousePos).x - d,
        map(p + e.yxy, duneComplexity, windSpeed, geyserHeight, audio, time, mousePos).x - d,
        map(p + e.yyx, duneComplexity, windSpeed, geyserHeight, audio, time, mousePos).x - d
    );
    return normalize(n);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;

    // Parameters
    let duneComplexity = u.zoom_params.x;
    let dispersion = u.zoom_params.y;
    let geyserHeight = u.zoom_params.z;
    let windSpeed = u.zoom_params.w;

    // Mouse Interaction
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);
    let mousePos = vec3<f32>(mouseX * 10.0, 0.0, mouseY * 10.0);

    // Camera setup
    var ro = vec3<f32>(0.0, 5.0, -10.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Camera pan
    ro.z += time * windSpeed;
    ro.y = 5.0 + sin(time * 0.2) * 2.0;

    // Look downward slightly
    let camRotX = rotate2D(0.4);
    let temp_rd_yz = camRotX * rd.yz;
    rd.y = temp_rd_yz.x;
    rd.z = temp_rd_yz.y;

    var col = vec3<f32>(0.0);
    var t = 0.0;
    var dMat = vec2<f32>(0.0, 0.0);

    // Raymarching
    for(var i=0; i<100; i++) {
        var p = ro + rd * t;
        dMat = map(p, duneComplexity, windSpeed, geyserHeight, audio, time, mousePos);

        if (dMat.x < 0.01 || t > 50.0) { break; }
        t += dMat.x;
    }

    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, duneComplexity, windSpeed, geyserHeight, audio, time, mousePos);

        // Lighting
        let sun1 = normalize(vec3<f32>(0.8, 0.5, 0.2));
        let sun2 = normalize(vec3<f32>(-0.8, 0.3, 0.5));

        let diff1 = max(dot(n, sun1), 0.0);
        let diff2 = max(dot(n, sun2), 0.0);

        if (dMat.y == 1.0) {
            // Sand material
            let sandBase = vec3<f32>(0.9, 0.7, 0.5);
            let chromaticShift = n.x * dispersion;
            let r = max(dot(n + vec3<f32>(chromaticShift, 0.0, 0.0), sun1), 0.0);
            let g = max(dot(n, sun1), 0.0);
            let b = max(dot(n - vec3<f32>(chromaticShift, 0.0, 0.0), sun1), 0.0);
            col = sandBase * (vec3<f32>(r, g, b) * 0.8 + diff2 * vec3<f32>(0.2, 0.4, 0.8));
        } else {
            // Crystal material
            let fre = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            col = vec3<f32>(0.2, 0.8, 1.0) * audio * 2.0;
            col += vec3<f32>(1.0, 0.2, 0.8) * fre * dispersion;
        }

        // Fog
        col = mix(col, vec3<f32>(0.1, 0.05, 0.2), 1.0 - exp(-0.02 * t));
    } else {
        // Sky
        col = vec3<f32>(0.1, 0.05, 0.2) - rd.y * 0.2;
    }

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}