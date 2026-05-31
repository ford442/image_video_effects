// ═══════════════════════════════════════════════════════════════════
//  Thermal Rainbow Topography
//  Category: generative
//  Features: thermal, topography, rainbow, audio-reactive, mouse-interactive, semantic-alpha, aces-tone-mapping, chromatic-aberration, temporal-feedback, depth-aware
//  Complexity: Medium
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

// --- Simplex noise (2D) ---
fn mod289_2(v: vec2<f32>) -> vec2<f32> { return v - floor(v * (1.0 / 289.0)) * 289.0; }
fn mod289_3f(v: vec3<f32>) -> vec3<f32> { return v - floor(v * (1.0 / 289.0)) * 289.0; }
fn mod289_4f(v: vec4<f32>) -> vec4<f32> { return v - floor(v * (1.0 / 289.0)) * 289.0; }
fn permute4(v: vec4<f32>) -> vec4<f32> { return mod289_4f(((v * 34.0) + 10.0) * v); }
fn taylorInvSqrt4(v: vec4<f32>) -> vec4<f32> { return 1.79284291400159 - 0.85373472095314 * v; }

fn snoise2(p: vec2<f32>) -> f32 {
    let C = vec4<f32>(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
    var i = floor(p + dot(p, C.yy));
    let x0 = p - i + dot(i, C.xx);
    let i1 = select(vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0), x0.x > x0.y);
    var x12 = x0.xyxy + C.xxzz;
    x12.x = x12.x - i1.x;
    x12.y = x12.y - i1.y;
    i = mod289_2(i);
    let p3 = permute4(permute4(i.y + vec4<f32>(0.0, i1.y, 1.0, 1.0)) + i.x + vec4<f32>(0.0, i1.x, 0.0, 1.0));
    var m = max(0.5 - vec4<f32>(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw), 0.0), vec4<f32>(0.0));
    m = m * m;
    m = m * m;
    let x = 2.0 * fract(p3 * C.w) - 1.0;
    let h = abs(x) - 0.5;
    let ox = floor(x + 0.5);
    let a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    var g: vec3<f32>;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.y = a0.y * x12.x + h.y * x12.y;
    g.z = a0.z * x12.z + h.z * x12.w;
    return 130.0 * dot(m, vec4<f32>(g.x, g.y, g.z, 1.0));
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * snoise2(pp);
        pp = pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn terrainHeight(p: vec2<f32>, t: f32) -> f32 {
    var h = 0.0;
    h += 0.4 * fbm(p * 1.0 + t * 0.05, 4);
    h += 0.25 * fbm(p * 2.5 - t * 0.03, 4);
    h += 0.15 * fbm(p * 5.0 + t * 0.08, 3);
    h += 0.1 * fbm(p * 10.0 + vec2<f32>(t * 0.02, -t * 0.04), 3);
    h += 0.06 * fbm(p * 20.0, 2);
    h += 0.04 * fbm(p * 40.0 + t * 0.01, 2);
    return h;
}

fn thermalColor(height: f32, colorShift: f32) -> vec3<f32> {
    let h = clamp(height + colorShift * 0.2, 0.0, 1.0);
    let palette = array<vec3<f32>, 8>(
        vec3<f32>(0.0, 0.0, 0.0),
        vec3<f32>(0.05, 0.0, 0.15),
        vec3<f32>(0.1, 0.0, 0.5),
        vec3<f32>(0.0, 0.4, 1.0),
        vec3<f32>(0.0, 1.0, 0.8),
        vec3<f32>(0.4, 1.0, 0.0),
        vec3<f32>(1.0, 1.0, 0.0),
        vec3<f32>(1.0, 0.0, 0.0)
    );
    let idx = h * 7.0;
    let i0 = i32(floor(idx));
    let i1 = min(i0 + 1, 7);
    let frac = idx - f32(i0);
    let smoothFrac = frac * frac * (3.0 - 2.0 * frac);
    return mix(palette[i0], palette[i1], smoothFrac);
}

fn neonThermalColor(height: f32, contour: f32, colorShift: f32) -> vec3<f32> {
    let baseColor = thermalColor(height, colorShift);
    var enhanced = pow(baseColor, vec3<f32>(0.7)) * 2.0;
    let whiteHot = smoothstep(0.85, 1.0, height);
    enhanced += vec3<f32>(1.0, 0.95, 0.9) * whiteHot * 3.0;
    let contourGlow = contour * vec3<f32>(0.8, 1.0, 1.0) * 2.5;
    return enhanced + contourGlow;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sampleTerrain(uv: vec2<f32>, res: vec2<f32>, time: f32, intensity: f32, speed: f32, scale: f32, colorShift: f32, mousePos: vec2<f32>, mouseDown: f32, bass: f32, depth: f32) -> vec4<f32> {
    let aspect = res.x / res.y;
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
    let terrainScale = 2.0 + scale * 4.0;
    let tp = centeredUV * terrainScale * (1.0 + bass * 0.15);
    let t = time * (0.1 + speed * 0.8);
    let h = terrainHeight(tp, t) * (1.0 + depth * 0.4);
    let heightNorm = h * 0.5 + 0.5;
    let hL = terrainHeight(tp + vec2<f32>(-0.01, 0.0), t);
    let hR = terrainHeight(tp + vec2<f32>(0.01, 0.0), t);
    let hD = terrainHeight(tp + vec2<f32>(0.0, -0.01), t);
    let hU = terrainHeight(tp + vec2<f32>(0.0, 0.01), t);
    let slope = length(vec2<f32>(hR - hL, hU - hD)) * 0.5;
    let contourInterval = 0.06 + scale * 0.08;
    let contourRaw = abs(fract(heightNorm / contourInterval) - 0.5) * 2.0;
    let contour = 1.0 - smoothstep(0.0, 0.08 + slope * 0.3, contourRaw);
    let majorContourRaw = abs(fract(heightNorm / (contourInterval * 5.0)) - 0.5) * 2.0;
    let majorContour = 1.0 - smoothstep(0.0, 0.04 + slope * 0.15, majorContourRaw);
    let mouseUV = vec2<f32>((mousePos.x / res.x - 0.5) * aspect, mousePos.y / res.y - 0.5);
    let mouseDist = length(centeredUV - mouseUV);
    let hotSpot = exp(-mouseDist * 10.0) * 0.4 * select(0.5, 1.5, mouseDown > 0.5) * (1.0 + bass * 0.5);
    let heightWithHotspot = heightNorm + hotSpot;
    let elevationGlow = smoothstep(0.7, 1.0, heightWithHotspot) * intensity;
    var color = neonThermalColor(heightWithHotspot, contour * 0.5 + majorContour * 0.5, colorShift);
    color += vec3<f32>(1.0, 0.8, 0.4) * elevationGlow * 2.0;
    color += vec3<f32>(1.0, 0.95, 0.7) * majorContour * 0.8 * intensity;
    let shadow = 1.0 - smoothstep(0.0, 0.6, slope);
    color *= 0.7 + shadow * 0.3;
    let specular = pow(max(1.0 - slope * 4.0, 0.0), 16.0) * intensity;
    color += vec3<f32>(1.0, 1.0, 0.9) * specular;
    let flow = fbm(tp * 0.3 + t * 0.1, 2) * 0.5 + 0.5;
    let flowLines = abs(sin(flow * 20.0 + heightWithHotspot * 30.0)) * 0.15;
    color += neonThermalColor(flow, 0.0, colorShift + 0.5) * flowLines * intensity;
    let hotGlow = exp(-mouseDist * 6.0) * select(0.2, 0.8, mouseDown > 0.5);
    color += vec3<f32>(1.0, 0.95, 0.8) * hotGlow * intensity;
    color += vec3<f32>(1.0, 0.5, 0.0) * hotGlow * 0.5 * intensity;
    color *= 1.0 + intensity * 1.0;
    let contourDensity = contour * 0.5 + majorContour * 0.5;
    return vec4<f32>(color, contourDensity);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let caStrength = 0.003 * intensity * (1.0 + bass);
    let rFull = sampleTerrain(uv + vec2<f32>(caStrength, 0.0), res, time, intensity, speed, scale, colorShift, mousePos, mouseDown, bass, depth);
    let gFull = sampleTerrain(uv, res, time, intensity, speed, scale, colorShift, mousePos, mouseDown, bass, depth);
    let bFull = sampleTerrain(uv - vec2<f32>(caStrength, 0.0), res, time, intensity, speed, scale, colorShift, mousePos, mouseDown, bass, depth);
    var color = vec3<f32>(rFull.r, gFull.g, bFull.b);
    let prev = textureLoad(dataTextureC, pixel, 0);
    let flowDecay = 0.12 * (1.0 + bass * 0.5);
    color = mix(color, prev.rgb, flowDecay);
    color = acesToneMap(color);
    let terrainIntensity = length(color);
    let alpha = terrainIntensity * gFull.a * depth;
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    let aspect = res.x / res.y;
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
    let tp = centeredUV * (2.0 + scale * 4.0) * (1.0 + bass * 0.15);
    let t = time * (0.1 + speed * 0.8);
    let h = terrainHeight(tp, t) * (1.0 + depth * 0.4);
    textureStore(writeDepthTexture, pixel, vec4<f32>(h * 0.5 + 0.5));
}
