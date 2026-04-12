// ----------------------------------------------------------------
// Cybernetic Ferro-Coral
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
    zoom_params: vec4<f32>,  // x=Density, y=Spike Intensity, z=Core Glow, w=Iridescence
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash31(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(17.1, 31.7, 47.9));
    return fract(q.x * q.y * q.z * 103.1);
}

fn noise3D(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash31(p + vec3<f32>(0.0,0.0,0.0)), hash31(p + vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(hash31(p + vec3<f32>(0.0,1.0,0.0)), hash31(p + vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(hash31(p + vec3<f32>(0.0,0.0,1.0)), hash31(p + vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(hash31(p + vec3<f32>(0.0,1.0,1.0)), hash31(p + vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>, time: f32, audioAmp: f32, density: f32, spikeIntensity: f32, mousePos: vec3<f32>) -> vec2<f32> {
    var op = p;

    // Mouse repulsion
    let md = distance(op, mousePos);
    if (md < 3.0) {
        op += normalize(op - mousePos) * (3.0 - md) * 0.5;
    }

    // Domain repetition
    let c = vec3<f32>(2.0 / density);
    var q = op - c * floor(op / c) - c * 0.5;

    // Base shape
    var d = length(q) - 0.5;

    // Noise spikes
    let n = noise3D(op * 2.0 + vec3<f32>(time * 0.5));
    let spikes = n * spikeIntensity * (1.0 + audioAmp * 2.0);

    // Flatten spikes near mouse
    let spikeMult = clamp((md - 1.0) / 2.0, 0.0, 1.0);
    d -= spikes * spikeMult;

    // Smooth min with other shapes
    let q2 = op - c * floor((op + c * 0.5) / c) - c * 0.5;
    let d2 = length(q2) - 0.4;
    d = smin(d, d2, 0.5);

    // Material ID: 1.0 = Shell, 0.0 = Core
    let mat = clamp(d / 0.1, 0.0, 1.0);

    return vec2<f32>(d, mat);
}

fn calcNormal(p: vec3<f32>, time: f32, audioAmp: f32, density: f32, spikeIntensity: f32, mousePos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audioAmp, density, spikeIntensity, mousePos).x - map(p - e.xyy, time, audioAmp, density, spikeIntensity, mousePos).x,
        map(p + e.yxy, time, audioAmp, density, spikeIntensity, mousePos).x - map(p - e.yxy, time, audioAmp, density, spikeIntensity, mousePos).x,
        map(p + e.yyx, time, audioAmp, density, spikeIntensity, mousePos).x - map(p - e.yyx, time, audioAmp, density, spikeIntensity, mousePos).x
    );
    return normalize(n);
}

fn pal(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;

    // Parameters
    let density = u.zoom_params.x;
    let spikeIntensity = u.zoom_params.y;
    let coreGlow = u.zoom_params.z;
    let iridescence = u.zoom_params.w;

    let audioAmp = u.config.y;
    let time = u.config.x;

    // Mouse Interaction
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);
    var mousePos = vec3<f32>(mouseX * 5.0, mouseY * 5.0, 0.0);

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Camera rotation
    let temp_ro_xz = rot(time * 0.1) * ro.xz;
    ro.x = temp_ro_xz.x; ro.z = temp_ro_xz.y;
    let temp_rd_xz = rot(time * 0.1) * rd.xz;
    rd.x = temp_rd_xz.x; rd.z = temp_rd_xz.y;

    // Rotate mouse position as well to match world space
    let temp_mp_xz = rot(-time * 0.1) * mousePos.xz;
    mousePos.x = temp_mp_xz.x; mousePos.z = temp_mp_xz.y;

    var col = vec3<f32>(0.0);
    var t = 0.0;
    var glow = vec3<f32>(0.0);

    for(var i=0; i<100; i++) {
        var p = ro + rd * t;

        let resMap = map(p, time, audioAmp, density, spikeIntensity, mousePos);
        let d = resMap.x;
        let mat = resMap.y;

        if (d < 0.01) {
            let n = calcNormal(p, time, audioAmp, density, spikeIntensity, mousePos);

            // Material 1: Shell (Iridescent Metal)
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let iriColor = pal(fresnel * iridescence + time * 0.1,
                               vec3<f32>(0.5, 0.5, 0.5),
                               vec3<f32>(0.5, 0.5, 0.5),
                               vec3<f32>(1.0, 1.0, 1.0),
                               vec3<f32>(0.0, 0.33, 0.67));

            let shellCol = mix(vec3<f32>(0.05), iriColor, fresnel) * max(dot(n, normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.1);

            // Material 0: Core (Plasma)
            let coreColor = pal(time * 0.5 + audioAmp,
                                vec3<f32>(0.8, 0.5, 0.4),
                                vec3<f32>(0.2, 0.4, 0.2),
                                vec3<f32>(2.0, 1.0, 1.0),
                                vec3<f32>(0.0, 0.25, 0.25));
            let coreEmission = coreColor * coreGlow * (1.0 + audioAmp * 2.0);

            col = mix(coreEmission, shellCol, mat);
            break;
        }

        // Volumetric glow from fissures
        if (mat < 0.5 && d < 0.1) {
             glow += pal(time * 0.5 + audioAmp, vec3<f32>(0.8, 0.5, 0.4), vec3<f32>(0.2, 0.4, 0.2), vec3<f32>(2.0, 1.0, 1.0), vec3<f32>(0.0, 0.25, 0.25)) * (0.01 * coreGlow) / (abs(d) + 0.05);
        }

        t += d * 0.5;
        if(t > 20.0) { break; }
    }

    col += glow;
    col = mix(col, vec3<f32>(0.0), 1.0 - exp(-0.05 * t)); // Fog
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}