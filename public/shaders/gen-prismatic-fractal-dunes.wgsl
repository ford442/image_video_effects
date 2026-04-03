// ----------------------------------------------------------------
// Prismatic Fractal-Dunes
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
    zoom_params: vec4<f32>,  // x=Dune Complexity, y=Prism Dispersion, z=Geyser Height, w=Wind Speed
    ripples: array<vec4<f32>, 50>,
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

fn map(p: vec3<f32>, time: f32, audioAmp: f32, duneComp: f32, geyserHeight: f32, mousePos: vec2<f32>, windSpeed: f32) -> vec2<f32> {
    // Dune SDF
    let wind = time * windSpeed;
    var n = fbm(p.xz * 0.2 + vec2<f32>(wind, wind * 0.5), 6) * (duneComp * 0.2);
    var d = p.y + 1.0 - n * 0.5;

    // Mouse interaction
    let md = length(p.xz - mousePos);
    let crater = exp(-md * md * 0.5) * 2.0;
    d += crater;

    // Geysers / KIFS Shards
    var shardP = p;
    shardP.y -= (-1.0 + n * 0.5);
    shardP.x -= mousePos.x * exp(-md);
    shardP.z -= mousePos.y * exp(-md);
    let shardF = fract(shardP.xz * 0.5) - 0.5;
    let distC = length(floor(shardP.xz * 0.5));
    let sync = sin(distC * 10.0 - time * 5.0) * 0.5 + 0.5;
    var q = vec3<f32>(shardF.x, shardP.y, shardF.y);
    q.y -= (audioAmp * geyserHeight * sync);

    for(var i=0; i<3; i++) {
        q.x = abs(q.x) - 0.1;
        q.z = abs(q.z) - 0.1;
        let temp_qx_qz = rotate2D(time + f32(i)) * vec2<f32>(q.x, q.z);
        q.x = temp_qx_qz.x; q.z = temp_qx_qz.y;
    }
    let shardD = max(max(abs(q.x), abs(q.z)) - 0.05, abs(q.y) - 0.5);

    if(shardD < d) {
        return vec2<f32>(shardD, 1.0); // 1.0 = Crystal Shard
    }
    return vec2<f32>(d, 0.0); // 0.0 = Sand
}

fn calcNormal(p: vec3<f32>, time: f32, audioAmp: f32, duneComp: f32, geyserHeight: f32, mousePos: vec2<f32>, windSpeed: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audioAmp, duneComp, geyserHeight, mousePos, windSpeed).x - map(p - e.xyy, time, audioAmp, duneComp, geyserHeight, mousePos, windSpeed).x,
        map(p + e.yxy, time, audioAmp, duneComp, geyserHeight, mousePos, windSpeed).x - map(p - e.yxy, time, audioAmp, duneComp, geyserHeight, mousePos, windSpeed).x,
        map(p + e.yyx, time, audioAmp, duneComp, geyserHeight, mousePos, windSpeed).x - map(p - e.yyx, time, audioAmp, duneComp, geyserHeight, mousePos, windSpeed).x
    ));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;

    let duneComplexity = u.zoom_params.x;
    let dispersion = u.zoom_params.y;
    let geyserHeight = u.zoom_params.z;
    let windSpeed = u.zoom_params.w;

    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);
    let mousePos = vec2<f32>(mouseX * 5.0, mouseY * 5.0);

    var ro = vec3<f32>(0.0, 1.0, -5.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y - 0.2, 1.0));

    let temp_ro_xz = rotate2D(time * 0.1) * ro.xz;
    ro.x = temp_ro_xz.x; ro.z = temp_ro_xz.y;
    let temp_rd_xz = rotate2D(time * 0.1) * rd.xz;
    rd.x = temp_rd_xz.x; rd.z = temp_rd_xz.y;

    var col = vec3<f32>(0.05, 0.05, 0.1) * uv.y;
    var t = 0.0;

    for(var i=0; i<80; i++) {
        let p = ro + rd * t;
        let resMap = map(p, time, audio, duneComplexity, geyserHeight, mousePos, windSpeed);
        let d = resMap.x;
        let mat = resMap.y;

        if(d < 0.01) {
            let n = calcNormal(p, time, audio, duneComplexity, geyserHeight, mousePos, windSpeed);
            if(mat > 0.5) {
                // Crystal
                col = vec3<f32>(0.0, 1.0, 1.0) * (audio * 2.0 + 0.5);
                let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
                col += vec3<f32>(1.0, 0.0, 1.0) * fresnel * dispersion;
            } else {
                // Sand
                let sun1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
                let sun2 = normalize(vec3<f32>(-1.0, 0.5, 1.0));
                let diff1 = max(dot(n, sun1), 0.0);
                let diff2 = max(dot(n, sun2), 0.0);
                col = vec3<f32>(0.8, 0.6, 0.3) * diff1 + vec3<f32>(0.2, 0.3, 0.6) * diff2;

                // Dispersion aberration rough approx
                let rx = max(dot(calcNormal(p + vec3<f32>(0.1,0.0,0.0), time, audio, duneComplexity, geyserHeight, mousePos, windSpeed), sun1), 0.0);
                let bz = max(dot(calcNormal(p - vec3<f32>(0.0,0.0,0.1), time, audio, duneComplexity, geyserHeight, mousePos, windSpeed), sun1), 0.0);
                col.r += rx * dispersion * 0.1;
                col.b += bz * dispersion * 0.1;
            }
            break;
        }
        t += d;
        if(t > 20.0) {
            break;
        }
    }

    col = mix(col, vec3<f32>(0.1, 0.1, 0.15), 1.0 - exp(-0.02 * t * t));
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
