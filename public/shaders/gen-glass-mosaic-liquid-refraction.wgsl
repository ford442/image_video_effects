// ═══════════════════════════════════════════════════════════════════════════════
//  Glass Mosaic + Liquid Refraction
//  Category: artistic
//  Description: Stained-glass polygon mosaic with pseudo-depth refraction
//               through animated height field.
//  Features: mouse-driven, audio-reactive, depth-aware
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
    return fract(vec2<f32>(n, n * 1.618));
}

fn voronoi(p: vec2<f32>, facetCount: f32) -> vec3<f32> {
    let n = floor(p * facetCount);
    let f = fract(p * facetCount);
    var md = 100.0;
    var md2 = 100.0;
    var cid = vec2<f32>(0.0);
    for (var j: i32 = -1; j <= 1; j = j + 1) {
        for (var i: i32 = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash2(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            if (d < md) {
                md2 = md;
                md = d;
                cid = n + g;
            } else if (d < md2) {
                md2 = d;
            }
        }
    }
    return vec3<f32>(sqrt(md), sqrt(md2), hash2(cid).x);
}

fn heightMap(uv: vec2<f32>, time: f32, audioBass: f32) -> f32 {
    var h = sin(uv.x * 8.0 + time) * cos(uv.y * 6.0 - time * 0.7) * 0.3;
    h = h + sin(uv.x * 13.0 - time * 1.3) * sin(uv.y * 11.0 + time * 0.5) * 0.2;
    h = h + sin((uv.x + uv.y) * 5.0 + time * 2.0) * 0.15;
    h = h * (1.0 + audioBass * 2.0);
    return h;
}

fn refractOffset(uv: vec2<f32>, h: f32, bevel: f32) -> vec2<f32> {
    let grad = vec2<f32>(
        heightMap(uv + vec2<f32>(0.01, 0.0), 0.0, 0.0) - h,
        heightMap(uv + vec2<f32>(0.0, 0.01), 0.0, 0.0) - h
    );
    return grad * bevel * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    // Parameters
    let facetCount = mix(4.0, 20.0, u.zoom_params.x);
    let bevelWidth = u.zoom_params.y * 0.1 + 0.01;
    let refractionStrength = u.zoom_params.z * 0.3;
    let rippleSpeed = u.zoom_params.w * 2.0 + 0.5;

    // Mouse offset
    let mouseOffset = (u.zoom_config.yz - 0.5) * 0.3;

    // Voronoi cell
    let v = voronoi(uv + mouseOffset, facetCount);
    let cellDist = v.x;
    let edgeDist = v.y - v.x;
    let cellHash = v.z;

    // Animated height field
    let h = heightMap(uv, time * rippleSpeed, bass);

    // Pseudo-depth from luminance + height
    let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let lum = length(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb);
    let depth = baseDepth * 0.5 + lum * 0.3 + h * 0.2;

    // Refraction
    let refractUV = uv + refractOffset(uv, h, bevelWidth) * refractionStrength;

    // Glass pane color
    let paneTint = vec3<f32>(
        0.7 + 0.3 * sin(cellHash * 6.28318 + 0.0),
        0.7 + 0.3 * sin(cellHash * 6.28318 + 2.094),
        0.7 + 0.3 * sin(cellHash * 6.28318 + 4.189)
    );

    // Refracted video
    let videoCol = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).rgb;

    // Blend tint with video
    let tintedGlass = mix(videoCol, videoCol * paneTint, 0.4);

    // Edge highlight (lead lines)
    let edge = smoothstep(0.0, bevelWidth * 3.0, edgeDist);
    let leadCol = vec3<f32>(0.05, 0.04, 0.03);
    let withLead = mix(leadCol, tintedGlass, edge);

    // Caustic sparkle on edges
    let caustic = pow(sin(edgeDist * 50.0 + time * 3.0) * 0.5 + 0.5, 8.0);
    let sparkle = caustic * bass * 0.5;
    let finalCol = withLead + vec3<f32>(0.9, 0.85, 0.7) * sparkle;

    // Glass specular
    let specAngle = sin(uv.x * 20.0 + uv.y * 15.0 + time) * 0.5 + 0.5;
    finalCol = finalCol + vec3<f32>(0.3, 0.3, 0.35) * specAngle * specAngle * 0.3;

    textureStore(writeTexture, id.xy, vec4<f32>(clamp(finalCol, vec3<f32>(0.0), vec3<f32>(2.0)), 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
