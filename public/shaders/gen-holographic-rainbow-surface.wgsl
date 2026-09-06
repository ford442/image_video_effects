// ═══════════════════════════════════════════════════════════════════
//  Holographic Rainbow Surface
//  Category: generative
//  Features: audio-reactive, mouse-driven, click-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-06
//  Ideas: Marangoni stress flow advection; drainage-gradient multilayer interference; anisotropic micro-groove diffraction
//  A packing: ACES display RGBA
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

const TAU: f32 = 6.28318530717958647692;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Utility functions
fn hash2(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let h = p3 + dot(p3, p3.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

fn hash12(p: vec3<f32>) -> f32 {
    let p3 = fract(p * 0.1031);
    let h = p3 + dot(p3, p3.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u_val = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u_val.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u_val.x),
        u_val.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let shift = vec2<f32>(100.0);
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

// ═══ Thin-film interference (Wolfram optics) ═══
// Constructive interference: 2 n d cos(θ) = m λ
fn thinFilmIridescence(viewAngle: f32, filmThickness: f32, n: f32) -> vec3<f32> {
    let wavelengths = vec3<f32>(650.0, 530.0, 460.0);
    let phase = 2.0 * n * filmThickness * cos(viewAngle) / wavelengths;
    let intensity = 0.5 + 0.5 * cos(phase * TAU);
    return pow(intensity, vec3<f32>(0.8)) * 2.0;
}

fn holographicColor(theta: f32, shift: f32) -> vec3<f32> {
    let t = theta * 6.0 + shift * TAU;
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
    let diffColor = holographicColor(fract(diffAngle * 2.0 + time * 0.15), time * 0.1);
    return diffColor * spec * 8.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;

    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // Audio reads
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let centeredUV = vec2<f32>(uv.x * aspect - (aspect - 1.0) * 0.5, uv.y);
    let p = (centeredUV - 0.5) * (3.0 - scale * 2.5);

    let scaledP = p * (1.0 + scale * 3.0);
    let t = time * (0.3 + speed * 2.0);

    var h = smoothSurfaceHeight(scaledP, t);
    var normal = computeNormal(scaledP, t, 0.005);

    let surfaceUV = centeredUV - 0.5;
    let mouseSurface = (mousePos - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = surfaceUV - mouseSurface;
    let mouseDist = length(mouseDelta);
    let hoverWave = sin(mouseDist * 24.0 - time * 5.0) * exp(-mouseDist * 7.0);
    h += hoverWave * select(0.018, 0.075, mouseDown > 0.5);
    normal = normalize(normal + vec3<f32>(mouseDelta / max(mouseDist, 1e-4) * hoverWave * select(0.05, 0.22, mouseDown > 0.5), 0.0));

    // Expand every live click timestamp into a finite surface wave.
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleDistort = 0.0;
    var rippleSlope = vec2<f32>(0.0);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 4.0) { continue; }
        let rPos = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let delta = surfaceUV - rPos;
        let rDist = length(delta);
        let waveRadius = age * mix(0.16, 0.48, speed);
        let envelope = exp(-pow((rDist - waveRadius) * 34.0, 2.0)) * exp(-age * 0.62);
        let wave = sin((rDist - waveRadius) * 42.0) * envelope;
        rippleDistort += wave;
        rippleSlope += delta / max(rDist, 1e-4) * wave;
    }
    h += rippleDistort * 0.10;
    normal = normalize(normal + vec3<f32>(rippleSlope * 0.28, 0.0));

    let lightDir1 = normalize(vec3<f32>(sin(t * 0.4) * 2.0, cos(t * 0.35) * 2.0, 1.5));
    let lightDir2 = normalize(vec3<f32>(cos(t * 0.3) * 1.5, sin(t * 0.25) * 1.5, 1.2));
    let lightDir3 = normalize(vec3<f32>(0.0, 0.0, 1.0));

    // Mouse tilts the interference plane
    let mouseTilt = select(vec2<f32>(0.0), (mousePos - 0.5) * 0.5, mouseDown > 0.5);
    let viewDir = normalize(vec3<f32>(mouseTilt.x, mouseTilt.y, 1.2));

    let NdotL1 = max(dot(normal, lightDir1), 0.0);
    let NdotL2 = max(dot(normal, lightDir2), 0.0);
    let NdotL3 = max(dot(normal, lightDir3), 0.0);

    // ─── Native Idea 2: Drainage-gradient multilayer interference ───
    // Physical gravity/drainage thickness variation (top thinner, bottom thicker)
    let drainage = clamp((centeredUV.y + h * 0.25) * 0.8 + 0.2, 0.08, 1.2);
    let filmThickness = (480.0 + bass * 220.0) * drainage;
    let nSoap = 1.33;
    let viewAngle = acos(clamp(dot(normal, viewDir), 0.0, 1.0));
    let interferenceColor = thinFilmIridescence(viewAngle, filmThickness, nSoap);

    // ─── Native Idea 1: Marangoni stress flow advection ───
    // Surface tension gradient induces tangential swirl whorls along height contours
    let tangentFlow = vec2<f32>(-normal.y, normal.x) * (0.2 + bass * 0.3);
    let marangoniP = scaledP + tangentFlow * sin(t * 1.4 + h * 5.0);
    let marangoniWhorl = fbm(marangoniP * 3.2 + t * 0.3, 3);
    let marangoniColor = holographicColor(marangoniWhorl * 2.0, colorShift + time * 0.12 + mids * 0.3) * 0.45 * intensity;

    // Base color now driven by thin-film interference + holographic
    let hueBase = h * 2.0 + colorShift * 3.0 + time * 0.15 + mids * 0.5;
    let baseColor = holographicColor(h * 0.5, hueBase) * interferenceColor + marangoniColor;

    let diffraction1 = spectralDiffraction(normal, lightDir1, viewDir, time);
    let diffraction2 = spectralDiffraction(normal, lightDir2, viewDir, time + 1.047);
    let highlight1 = prismaticHighlight(normal, viewDir, time);
    let highlight2 = prismaticHighlight(normal, viewDir, time + 2.094);

    let fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 3.0);
    let edgeColor = holographicColor(fresnel * 2.0, time * 0.2 + colorShift);

    let mouseEffect = select(0.25, 1.0, mouseDown > 0.5);
    let mouseWave = hoverWave * mouseEffect;
    let mouseColor = holographicColor(mouseWave * 0.5 + 0.5, time * 0.5 + colorShift) * mouseWave * 2.0;
    let rippleColor = holographicColor(rippleDistort * 2.0, time * 0.3 + colorShift) * rippleDistort * 1.5;

    // ─── Native Idea 3: Anisotropic micro-groove diffraction grating ───
    // Razor-sharp rainbow sheen streaks perpendicular to surface slopes
    let slopeDir = normalize(normal.xy + vec2<f32>(1e-4, 0.0));
    let groovePhase = dot(centeredUV * res.y, slopeDir) * 0.15;
    let grooveDiffraction = pow(0.5 + 0.5 * cos(groovePhase * TAU + time * 2.0), 28.0);
    let grooveRainbow = holographicColor(groovePhase * 0.25, time * 0.2 + colorShift);
    let grooveSheen = grooveRainbow * grooveDiffraction * fresnel * 1.6 * intensity;

    var color = baseColor * (NdotL1 * 0.5 + NdotL2 * 0.3 + NdotL3 * 0.2 + 0.3);
    color += diffraction1 * intensity * 1.5;
    color += diffraction2 * intensity * 0.8;
    color += highlight1 * intensity * 1.2;
    color += highlight2 * intensity * 0.6;
    color += edgeColor * fresnel * 1.5;
    color += mouseColor;
    color += rippleColor;
    color += grooveSheen;

    let microDetail = fbm(scaledP * 20.0 + t * 0.5, 3);
    color += holographicColor(microDetail, time * 0.1 + colorShift) * microDetail * 0.15 * intensity;

    // Treble sparkles
    let sparkle = hash12(vec3<f32>(scaledP * 50.0, time * 0.1));
    color += vec3<f32>(1.0, 0.9, 0.7) * smoothstep(0.97, 1.0, sparkle) * treble * 2.0;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES is applied once to the current display path. A/C then preserves
    // that exact display RGBA with an integer history load.
    let currentDisplay = acesToneMap(color * 1.1);
    let prev = textureLoad(dataTextureC, pixel, 0);
    color = mix(prev.rgb * 0.96, currentDisplay, 0.25 + bass * 0.03);
    let alpha = max(clamp(length(currentDisplay) * 0.58 + fresnel * 0.25 + abs(rippleDistort) * 0.3, 0.08, 0.96), prev.a * 0.93);
    let surfaceDepth = clamp(0.28 + h * 0.42 + (1.0 - normal.z) * 0.30 + abs(rippleDistort) * 0.25, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(surfaceDepth, 0.0, 0.0, 0.0));
}
