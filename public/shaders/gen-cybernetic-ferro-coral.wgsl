// ═══════════════════════════════════════════════════════════════════
//  Cybernetic Ferro-Coral
//  Category: generative
//  Features: raymarched, iridescence, audio-reactive, mouse-interactive, semantic-alpha, aces-tone-mapping, chromatic-aberration, temporal-feedback, depth-aware
//  Complexity: High
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
// ═══════════════════════════════════════════════════════════════════

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

fn map(p: vec3<f32>, time: f32, bass: f32, density: f32, spikeIntensity: f32, mousePos: vec3<f32>) -> vec2<f32> {
    var op = p;
    let md = distance(op, mousePos);
    let repulse = select(0.0, (3.0 - md) * 0.5, md < 3.0);
    op += normalize(op - mousePos) * repulse;
    let c = vec3<f32>(2.0 / density);
    var q = op - c * floor(op / c) - c * 0.5;
    var d = length(q) - 0.5;
    let n = noise3D(op * 2.0 + vec3<f32>(time * 0.5));
    let spikes = n * spikeIntensity * (1.0 + bass * 2.0);
    let spikeMult = clamp((md - 1.0) / 2.0, 0.0, 1.0);
    d -= spikes * spikeMult;
    let q2 = op - c * floor((op + c * 0.5) / c) - c * 0.5;
    let d2 = length(q2) - 0.4;
    d = smin(d, d2, 0.5);
    let mat = clamp(d / 0.1, 0.0, 1.0);
    return vec2<f32>(d, mat);
}

fn calcNormal(p: vec3<f32>, time: f32, bass: f32, density: f32, spikeIntensity: f32, mousePos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, bass, density, spikeIntensity, mousePos).x - map(p - e.xyy, time, bass, density, spikeIntensity, mousePos).x,
        map(p + e.yxy, time, bass, density, spikeIntensity, mousePos).x - map(p - e.yxy, time, bass, density, spikeIntensity, mousePos).x,
        map(p + e.yyx, time, bass, density, spikeIntensity, mousePos).x - map(p - e.yyx, time, bass, density, spikeIntensity, mousePos).x
    );
    return normalize(n);
}

fn pal(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn marchRay(ro: vec3<f32>, rd: vec3<f32>, time: f32, bass: f32, mids: f32, density: f32, spikeIntensity: f32, coreGlow: f32, iridescence: f32, mousePos: vec3<f32>, depth: f32) -> vec4<f32> {
    var col = vec3<f32>(0.0);
    var t = 0.0;
    var glow = vec3<f32>(0.0);
    for(var i=0; i<100; i++) {
        var p = ro + rd * t;
        let resMap = map(p, time, bass, density, spikeIntensity, mousePos);
        let d = resMap.x;
        let mat = resMap.y;
        if (d < 0.01) {
            let n = calcNormal(p, time, bass, density, spikeIntensity, mousePos);
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let iriColor = pal(fresnel * iridescence + time * 0.1 + mids,
                               vec3<f32>(0.5, 0.5, 0.5),
                               vec3<f32>(0.5, 0.5, 0.5),
                               vec3<f32>(1.0, 1.0, 1.0),
                               vec3<f32>(0.0, 0.33, 0.67));
            let shellCol = mix(vec3<f32>(0.05), iriColor, fresnel) * max(dot(n, normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.1);
            let coreColor = pal(time * 0.5 + bass,
                                vec3<f32>(0.8, 0.5, 0.4),
                                vec3<f32>(0.2, 0.4, 0.2),
                                vec3<f32>(2.0, 1.0, 1.0),
                                vec3<f32>(0.0, 0.25, 0.25));
            let coreEmission = coreColor * coreGlow * (1.0 + bass * 2.0);
            col = mix(coreEmission, shellCol, mat);
            break;
        }
        if (mat < 0.5 && d < 0.1) {
             glow += pal(time * 0.5 + bass, vec3<f32>(0.8, 0.5, 0.4), vec3<f32>(0.2, 0.4, 0.2), vec3<f32>(2.0, 1.0, 1.0), vec3<f32>(0.0, 0.25, 0.25)) * (0.01 * coreGlow) / (abs(d) + 0.05);
        }
        t += d * 0.5;
        if(t > 20.0) { break; }
    }
    col += glow;
    col = mix(col, vec3<f32>(0.0), 1.0 - exp(-0.05 * t * (1.0 + depth * 2.0)));
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    return vec4<f32>(col, t);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let pixel = vec2<i32>(id.xy);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv = (fragCoord * 2.0 - res) / res.y;
    let texUV = (vec2<f32>(pixel) + 0.5) / res;

    let density = u.zoom_params.x;
    let spikeIntensity = u.zoom_params.y;
    let coreGlow = u.zoom_params.z;
    let iridescence = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let time = u.config.x;

    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = u.zoom_config.z * 2.0 - 1.0;
    var mousePos = vec3<f32>(mouseX * 5.0, mouseY * 5.0, 0.0);

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    let temp_ro_xz = rot(time * 0.1) * ro.xz;
    ro.x = temp_ro_xz.x; ro.z = temp_ro_xz.y;
    let temp_rd_xz = rot(time * 0.1) * rd.xz;
    rd.x = temp_rd_xz.x; rd.z = temp_rd_xz.y;

    let temp_mp_xz = rot(-time * 0.1) * mousePos.xz;
    mousePos.x = temp_mp_xz.x; mousePos.z = temp_mp_xz.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, texUV, 0.0).r;

    let caStrength = 0.003 * (1.0 + bass);
    var rdR = normalize(vec3<f32>(uv.x + caStrength, uv.y, 1.0));
    var rdB = normalize(vec3<f32>(uv.x - caStrength, uv.y, 1.0));
    let temp_rdR_xz = rot(time * 0.1) * rdR.xz;
    rdR.x = temp_rdR_xz.x; rdR.z = temp_rdR_xz.y;
    let temp_rdB_xz = rot(time * 0.1) * rdB.xz;
    rdB.x = temp_rdB_xz.x; rdB.z = temp_rdB_xz.y;

    let rRes = marchRay(ro, rdR, time, bass, mids, density, spikeIntensity, coreGlow, iridescence, mousePos, depth);
    let gRes = marchRay(ro, rd, time, bass, mids, density, spikeIntensity, coreGlow, iridescence, mousePos, depth);
    let bRes = marchRay(ro, rdB, time, bass, mids, density, spikeIntensity, coreGlow, iridescence, mousePos, depth);

    var color = vec3<f32>(rRes.r, gRes.g, bRes.b);

    let prev = textureLoad(dataTextureC, pixel, 0);
    color = mix(color, prev.rgb, 0.12 * (1.0 + bass));

    color = acesToneMap(color);

    let surfaceProximity = 1.0 / (1.0 + gRes.a * 0.1);
    let glowIntensity = length(color);
    let alpha = surfaceProximity * glowIntensity * depth;

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(1.0 / (1.0 + gRes.a * 0.05)));
}
