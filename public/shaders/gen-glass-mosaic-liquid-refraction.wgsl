// ═══════════════════════════════════════════════════════════════════════════════
//  Glass Mosaic + Liquid Refraction — Algorithmist Upgrade
//  Category: artistic
//  Features: mouse-driven, audio-reactive, depth-aware, FBM, domain-warping,
//            curl-noise, Worley, Fresnel-Schlick, Beer-Lambert, IOR, temporal
//  Complexity: Very High
//  Upgraded: 2026-06-28
// ═══════════════════════════════════════════════════════════════════════════════
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

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const PHI: f32 = 1.618033988749895;
const IOR_AIR: f32 = 1.0;
const IOR_GLASS: f32 = 1.52;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash1(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453); }

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
    return fract(vec2<f32>(n, n * 1.618));
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let s = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash1(i), hash1(i + vec2<f32>(1.0, 0.0)), s.x),
               mix(hash1(i + vec2<f32>(0.0, 1.0)), hash1(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn fbm2(p: vec2<f32>, oct: i32) -> f32 {
    var v = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < 6; i++) { if (i >= oct) { break; } v += a * vnoise2(p * f); f *= 2.0; a *= 0.5; }
    return v;
}

fn domainWarp2(p: vec2<f32>, t: f32) -> vec2<f32> {
    return p + vec2<f32>(fbm2(p + vec2<f32>(0.0, t), 3), fbm2(p + vec2<f32>(5.2, 1.3 + t), 3)) * 0.5;
}

fn curl2(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.01;
    let n1 = vnoise2(p + vec2<f32>(e, 0.0) + t); let n2 = vnoise2(p - vec2<f32>(e, 0.0) + t);
    let n3 = vnoise2(p + vec2<f32>(0.0, e) + t); let n4 = vnoise2(p - vec2<f32>(0.0, e) + t);
    return vec2<f32>((n4 - n3) / (2.0 * e), (n1 - n2) / (2.0 * e));
}

fn voronoi(p: vec2<f32>, facetCount: f32) -> vec3<f32> {
    let n = floor(p * facetCount); let f = fract(p * facetCount);
    var md = 100.0; var md2 = 100.0; var cid = vec2<f32>(0.0);
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash2(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            if (d < md) { md2 = md; md = d; cid = n + g; }
            else if (d < md2) { md2 = d; }
        }
    }
    return vec3<f32>(sqrt(md), sqrt(md2), hash2(cid).x);
}

fn worley2(p: vec2<f32>, density: f32) -> vec2<f32> {
    let n = floor(p * density); let f = fract(p * density);
    var md = 100.0; var md2 = 100.0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j)); let o = hash2(n + g); let r = g + o - f; let d = dot(r, r);
            if (d < md) { md2 = md; md = d; } else if (d < md2) { md2 = d; }
        }
    }
    return vec2<f32>(sqrt(md), sqrt(md2) - sqrt(md));
}

fn heightMap(uv: vec2<f32>, time: f32, audioBass: f32) -> f32 {
    var h = sin(uv.x * 8.0 + time) * cos(uv.y * 6.0 - time * 0.7) * 0.3;
    h += sin(uv.x * 13.0 - time * 1.3) * sin(uv.y * 11.0 + time * 0.5) * 0.2;
    h += sin((uv.x + uv.y) * 5.0 + time * 2.0) * 0.15;
    // FBM domain-warped detail
    let dw = domainWarp2(uv * 3.0, time * 0.2);
    h += fbm2(dw, 4) * 0.25;
    // Curl noise liquid flow
    let c = curl2(uv * 2.0, time * 0.3);
    h += dot(c, vec2<f32>(sin(time), cos(time))) * 0.15;
    h *= (1.0 + audioBass * 2.0);
    return h;
}

fn refractOffset(uv: vec2<f32>, h: f32, bevel: f32) -> vec2<f32> {
    let grad = vec2<f32>(heightMap(uv + vec2<f32>(0.01, 0.0), 0.0, 0.0) - h, heightMap(uv + vec2<f32>(0.0, 0.01), 0.0, 0.0) - h);
    return grad * bevel * 0.5;
}

fn fresnel(cosTheta: f32, f0: f32) -> f32 { return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0); }

fn causticPattern(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let c1 = sin(uv.x * 30.0 + time * 4.0) * sin(uv.y * 25.0 - time * 3.0);
    let c2 = sin((uv.x + uv.y) * 20.0 + time * 2.5) * sin((uv.x - uv.y) * 15.0 + time * 1.5);
    let c3 = fbm2(uv * 8.0 + time * 0.5, 3);
    return pow(max(c1 * c2 * 0.5 + 0.5 + c3 * 0.3, 0.0), 4.0) * intensity;
}

fn glassThickness(uv: vec2<f32>, h: f32, edgeDist: f32) -> f32 {
    let baseThick = 0.5 + h * 0.3;
    let edgeThick = smoothstep(0.0, 0.1, edgeDist) * 0.8;
    return baseThick + edgeThick;
}

fn chromaticAberration(uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let dir = normalize(uv - vec2<f32>(0.5) + vec2<f32>(sin(time), cos(time)) * 0.1);
    let rOff = uv + dir * strength * 1.2;
    let gOff = uv + dir * strength * 0.6;
    let bOff = uv - dir * strength * 0.8;
    return vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rOff, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, gOff, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, bOff, 0.0).b
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }
    let coord = vec2<i32>(id.xy);
    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
    // Parameters
    let facetCount = mix(4.0, 20.0, u.zoom_params.x);
    let bevelWidth = u.zoom_params.y * 0.1 + 0.01;
    let refractionStrength = u.zoom_params.z * 0.3;
    let rippleSpeed = u.zoom_params.w * 2.0 + 0.5;
    // Mouse offset (Y-flip: screen-top = +Y/up)
    let mouseOffset = vec2<f32>(u.zoom_config.y - 0.5, u.zoom_config.z - 0.5) * 0.3;
    // Domain-warped Voronoi mosaic
    let warpUV = domainWarp2(uv + mouseOffset, time * 0.1);
    let v = voronoi(warpUV, facetCount);
    let cellDist = v.x; let edgeDist = v.y - v.x; let cellHash = v.z;
    // Worley cellular texture for glass grain
    let w = worley2(warpUV * 2.0, facetCount * 1.5);
    // Animated height field with FBM and curl
    let h = heightMap(uv, time * rippleSpeed, bass);
    // Pseudo-depth from luminance + height
    let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let lum = length(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb);
    let depth = baseDepth * 0.5 + lum * 0.3 + h * 0.2;
    // Refraction with IOR-based Snell approximation
    let eta = IOR_AIR / IOR_GLASS;
    let refractUV = uv + refractOffset(uv, h, bevelWidth) * refractionStrength * (1.0 + bass * 0.5);
    let refractUV2 = uv + refractOffset(uv, h * 0.7, bevelWidth * 0.5) * refractionStrength * eta * (1.0 + mids * 0.3);
    // Glass pane color with thin-film interference
    let phase = cellHash * TAU + time * 0.5 + treble * 2.0;
    let paneTint = vec3<f32>(
        0.7 + 0.3 * sin(phase + 0.0),
        0.7 + 0.3 * sin(phase + 2.094),
        0.7 + 0.3 * sin(phase + 4.189)
    ) * (0.8 + w.x * 0.4);
    // Refracted video with chromatic separation (RGB IOR variation)
    let videoR = textureSampleLevel(readTexture, u_sampler, refractUV + vec2<f32>(0.003 * treble, 0.0), 0.0).r;
    let videoG = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).g;
    let videoB = textureSampleLevel(readTexture, u_sampler, refractUV2 - vec2<f32>(0.003 * treble, 0.0), 0.0).b;
    var videoCol = vec3<f32>(videoR, videoG, videoB);
    // Chromatic aberration from glass thickness variation
    let thick = glassThickness(uv, h, edgeDist);
    let aberra = chromaticAberration(refractUV, 0.002 * thick * refractionStrength, time);
    videoCol = mix(videoCol, aberra, 0.3 * thick);
    // Beer-Lambert absorption through thick glass
    let absorption = exp(-thick * vec3<f32>(0.3, 0.5, 0.8) * (1.0 + mids));
    videoCol *= absorption;
    // Blend tint with video
    let tintedGlass = mix(videoCol, videoCol * paneTint, 0.4 + bass * 0.1);
    // Fresnel reflection on glass surface
    let viewDir = normalize(vec2<f32>(0.0, 1.0));
    let normal = normalize(refractOffset(uv, h, 1.0) * 10.0 + vec2<f32>(0.0, 1.0));
    let fres = fresnel(max(dot(normal, viewDir), 0.0), 0.04);
    let reflectCol = vec3<f32>(0.9, 0.95, 1.0) * fres * (0.3 + mids * 0.3);
    // Edge highlight (lead lines) with Beer-Lambert attenuation
    let edge = smoothstep(0.0, bevelWidth * 3.0, edgeDist);
    let leadCol = vec3<f32>(0.05, 0.04, 0.03);
    let attenuation = exp(-edgeDist * 8.0 * (1.0 + u.zoom_params.y));
    let withLead = mix(leadCol * attenuation + tintedGlass * (1.0 - attenuation), tintedGlass + reflectCol, edge);
    // Caustic sparkle on edges with physical dispersion
    let caustic = pow(sin(edgeDist * 50.0 + time * 3.0 + w.y * 10.0) * 0.5 + 0.5, 8.0);
    let caustic2 = causticPattern(uv * facetCount, time, 1.0 + bass * 2.0);
    let sparkle = (caustic * 0.6 + caustic2 * 0.4) * bass * 0.5 * (1.0 + treble * 2.0);
    var finalCol = withLead + vec3<f32>(0.9, 0.85, 0.7) * sparkle;
    // Glass specular with temporal shimmer
    let specAngle = sin(uv.x * 20.0 + uv.y * 15.0 + time + fbm2(uv * 5.0, 3) * TAU) * 0.5 + 0.5;
    finalCol += vec3<f32>(0.3, 0.3, 0.35) * specAngle * specAngle * 0.3 * (1.0 + mids * 0.5);
    // Temporal feedback via dataTextureC with chromatic decay
    let prev = textureLoad(dataTextureC, coord, 0);
    let decayR = 0.95 + treble * 0.02; let decayG = 0.95 + mids * 0.02; let decayB = 0.95 + bass * 0.02;
    let prevDecay = vec3<f32>(prev.r * decayR, prev.g * decayG, prev.b * decayB);
    finalCol = mix(finalCol, prevDecay, 0.03 + bass * 0.015);
    finalCol = acesToneMap(max(finalCol, vec3<f32>(0.0)) * 1.08);
    let lum2 = dot(finalCol, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(lum2 * 0.7 + 0.2, 0.0, 1.0);
    textureStore(dataTextureA, coord, vec4<f32>(finalCol, alpha));
    textureStore(writeTexture, coord, vec4<f32>(finalCol, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth, 0.0, 1.0), 0.0, 0.0, 0.0));
}
