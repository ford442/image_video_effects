// ═══════════════════════════════════════════════════════════════════
//  Resonant Quantum-Obsidian Scarab-Engine
//  Category: generative
//  Features: raymarched, kifs-exoskeleton, mouse-driven, audio-reactive,
//            upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration
//  Complexity: High
//  Chunks From: gen-protocell-division.wgsl (upgraded-rgba stack)
//  Upgraded: 2026-06-14
//  By: Claude Code Batch 3B
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

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn map(p: vec3<f32>, audioLevel: f32) -> vec2<f32> {
    var p_mod = p;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    p_mod.x -= mouse.x * 2.0;
    p_mod.y += mouse.y * 2.0;

    // Core pulsing Torus
    let corePulseRate = u.zoom_params.w + audioLevel * 2.0;
    let t = sdTorus(p_mod, vec2<f32>(1.0 + sin(u.config.x * corePulseRate) * 0.2, 0.5));
    var res = vec2<f32>(t, 1.0); // 1.0 = Core

    // KIFS Exoskeleton
    let exoskeletonComplexity = u.zoom_params.x;
    var p_kifs = p;
    for(var i = 0; i < 4; i++) {
        p_kifs = abs(p_kifs) - 0.5 * exoskeletonComplexity;
        let r = rot(u.config.x * 0.5 + f32(i) + audioLevel * 0.5);
        p_kifs.x = p_kifs.x * r[0][0] + p_kifs.y * r[1][0];
        p_kifs.y = p_kifs.x * r[0][1] + p_kifs.y * r[1][1];
    }
    let kifs_dist = length(p_kifs) - 0.2;

    let final_dist = smin(t, kifs_dist, 0.5);
    if(kifs_dist < t) {
        res = vec2<f32>(final_dist, 2.0); // 2.0 = Exoskeleton
    } else {
        res = vec2<f32>(final_dist, 1.0);
    }

    return res;
}

fn calcNormal(p: vec3<f32>, audioLevel: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, audioLevel).x - map(p - e.xyy, audioLevel).x,
        map(p + e.yxy, audioLevel).x - map(p - e.yxy, audioLevel).x,
        map(p + e.yyx, audioLevel).x - map(p - e.yyx, audioLevel).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }
    let coord = vec2<i32>(id.xy);
    let uv = (fragCoord - 0.5 * res) / res.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioLevel = bass;

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p, audioLevel);
        if(d.x < 0.001) {
            mat = d.y;
            break;
        }
        if(t > 20.0) {
            break;
        }
        t += d.x;
    }

    var col = vec3<f32>(0.0);
    var spec = 0.0;
    if(t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, audioLevel);

        let lightPos = vec3<f32>(2.0, 4.0, -2.0);
        let l = normalize(lightPos - p);
        let dif = clamp(dot(n, l), 0.0, 1.0);

        let plasmaIntensity = u.zoom_params.y * (1.0 + mids * 0.4);
        let obsidianReflectivity = u.zoom_params.z;

        if (mat == 1.0) { // Core
             col = vec3<f32>(0.0, 1.0, 1.0) * plasmaIntensity * dif;
        } else if (mat == 2.0) { // Exoskeleton
             let refl = reflect(rd, n);
             spec = pow(clamp(dot(refl, l), 0.0, 1.0), 32.0);
             col = vec3<f32>(0.1) * dif + vec3<f32>(1.0) * spec * obsidianReflectivity;
        }
    }

    // Quantum Dust
    let dustDensity = u.zoom_config.w * 0.1 + treble * 0.05;
    let dust = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453) * dustDensity;
    col += vec3<f32>(0.5, 0.0, 1.0) * dust;

    // ═══ CHUNK: temporal-feedback (dataTextureC → dataTextureA) ═══
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.92, 0.05 + bass * 0.01);

    // ═══ CHUNK: chromatic-aberration ═══
    let caStr = 0.003 * (1.0 + bass) + spec * 0.002;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    col = acesToneMap(col * 1.2);

    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(lum * 1.5 + dust * 0.5, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    let depthVal = clamp(t / 20.0, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
