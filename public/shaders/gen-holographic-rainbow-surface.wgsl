// ═══════════════════════════════════════════════════════════════════
//  Holographic Rainbow Surface
//  Category: generative
//  Features: holographic, rainbow, surface, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium-High
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

// Utility functions
fn hash2(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let h = p3 + dot(p3, p3.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    let h = p3 + dot(p3, p3.yzx + 33.33);
    return fract((h.xx + h.yz) * h.zy);
}

fn hash12(p: vec3<f32>) -> f32 {
    let p3 = fract(p * 0.1031);
    let h = p3 + dot(p3, p3.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * vnoise2(pp);
        pp = pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn smoothSurfaceHeight(p: vec2<f32>, t: f32) -> f32 {
    var h = 0.0;
    h += 0.35 * fbm(p * 1.5 + t * 0.3, 3);
    h += 0.25 * fbm(p * 2.8 - t * 0.2, 3);
    h += 0.15 * fbm(p * 4.0 + t * 0.15, 2);
    h += 0.10 * fbm(p * 7.0 + vec2<f32>(t * 0.1, -t * 0.12), 2);
    return h;
}

fn computeNormal(p: vec2<f32>, t: f32, eps: f32) -> vec3<f32> {
    let hL = smoothSurfaceHeight(p + vec2<f32>(-eps, 0.0), t);
    let hR = smoothSurfaceHeight(p + vec2<f32>(eps, 0.0), t);
    let hD = smoothSurfaceHeight(p + vec2<f32>(0.0, -eps), t);
    let hU = smoothSurfaceHeight(p + vec2<f32>(0.0, eps), t);
    return normalize(vec3<f32>(hL - hR, hD - hU, 2.0 * eps));
}

fn holographicColor(theta: f32, shift: f32) -> vec3<f32> {
    let t = theta * 6.0 + shift * 6.28318530718;
    let r = 0.5 + 0.5 * sin(t + 0.0);
    let g = 0.5 + 0.5 * sin(t + 2.094);
    let b = 0.5 + 0.5 * sin(t + 4.189);
    let lum = 1.8 / (1.0 + 0.3 * dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114)));
    return vec3<f32>(r, g, b) * lum;
}

fn prismaticHighlight(normal: vec3<f32>, viewDir: vec3<f32>, time: f32) -> vec3<f32> {
    let NdotV = max(dot(normal, viewDir), 0.0);
    let fresnel = pow(1.0 - NdotV, 4.0);
    let hueShift = time * 0.4 + NdotV * 3.0;
    let col = holographicColor(NdotV + fresnel * 0.5, hueShift);
    return col * fresnel * 2.5;
}

fn spectralDiffraction(normal: vec3<f32>, lightDir: vec3<f32>, viewDir: vec3<f32>, time: f32) -> vec3<f32> {
    let H = normalize(lightDir + viewDir);
    let NdotH = max(dot(normal, H), 0.0);
    let spec = pow(NdotH, 128.0);
    let diffAngle = acos(clamp(NdotH, 0.0, 1.0));
    let waveLength = 380.0 + 400.0 * fract(diffAngle * 3.0 + time * 0.3);
    let diffColor = holographicColor(fract(diffAngle * 2.0 + time * 0.15), time * 0.1);
    return diffColor * spec * 8.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;

    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let centeredUV = vec2<f32>(uv.x * aspect - (aspect - 1.0) * 0.5, uv.y);
    let p = (centeredUV - 0.5) * (3.0 - scale * 2.5);

    let scaledP = p * (1.0 + scale * 3.0);
    let t = time * (0.3 + speed * 2.0);

    let h = smoothSurfaceHeight(scaledP, t);
    let normal = computeNormal(scaledP, t, 0.005);

    let lightDir1 = normalize(vec3<f32>(sin(t * 0.4) * 2.0, cos(t * 0.35) * 2.0, 1.5));
    let lightDir2 = normalize(vec3<f32>(cos(t * 0.3) * 1.5, sin(t * 0.25) * 1.5, 1.2));
    let lightDir3 = normalize(vec3<f32>(0.0, 0.0, 1.0));

    let viewDir = normalize(vec3<f32>(0.0, 0.0, 1.2));

    let NdotL1 = max(dot(normal, lightDir1), 0.0);
    let NdotL2 = max(dot(normal, lightDir2), 0.0);
    let NdotL3 = max(dot(normal, lightDir3), 0.0);

    let hueBase = h * 2.0 + colorShift * 3.0 + time * 0.15;
    let baseColor = holographicColor(h * 0.5, hueBase);

    let diffraction1 = spectralDiffraction(normal, lightDir1, viewDir, time);
    let diffraction2 = spectralDiffraction(normal, lightDir2, viewDir, time + 1.047);
    let highlight1 = prismaticHighlight(normal, viewDir, time);
    let highlight2 = prismaticHighlight(normal, viewDir, time + 2.094);

    let fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 3.0);
    let edgeColor = holographicColor(fresnel * 2.0, time * 0.2 + colorShift);

    let mouseEffect = mouseDown > 0.5 ? 1.0 : 0.0;
    let mouseUV = vec2<f32>(mousePos.x / res.x * aspect - (aspect - 1.0) * 0.5, mousePos.y / res.y);
    let mouseDist = length(centeredUV - mouseUV);
    let mouseWave = sin(mouseDist * 25.0 - time * 6.0) * exp(-mouseDist * 8.0) * mouseEffect;
    let mouseColor = holographicColor(mouseWave * 0.5 + 0.5, time * 0.5 + colorShift) * mouseWave * 2.0;

    var rippleDistort = 0.0;
    for (var i: i32 = 0; i < 10; i = i + 1) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rTime = ripple.z;
        let rStrength = ripple.w;
        let age = time - rTime;
        if (rStrength > 0.0 && age > 0.0 && age < 4.0) {
            let rDist = length(centeredUV - rPos);
            let waveRadius = age * 0.3;
            let wave = exp(-pow((rDist - waveRadius) * 40.0, 2.0)) * exp(-age * 0.5) * rStrength;
            rippleDistort += wave;
        }
    }
    let rippleColor = holographicColor(rippleDistort * 2.0, time * 0.3 + colorShift) * rippleDistort * 1.5;

    var color = baseColor * (NdotL1 * 0.5 + NdotL2 * 0.3 + NdotL3 * 0.2 + 0.3);
    color += diffraction1 * intensity * 1.5;
    color += diffraction2 * intensity * 0.8;
    color += highlight1 * intensity * 1.2;
    color += highlight2 * intensity * 0.6;
    color += edgeColor * fresnel * 1.5;
    color += mouseColor;
    color += rippleColor;

    let microDetail = fbm(scaledP * 20.0 + t * 0.5, 3);
    color += holographicColor(microDetail, time * 0.1 + colorShift) * microDetail * 0.15 * intensity;

    color = color / (1.0 + color * 0.15);
    color = pow(color, vec3<f32>(0.9, 0.95, 1.05));
    color *= 1.2 + intensity * 0.5;

    textureStore(writeTexture, pixel, vec4<f32>(color, 0.85));
}
