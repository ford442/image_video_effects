// ═══════════════════════════════════════════════════════════════════
//  Hex Circuit
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-10
//  Ideas: via pads at hex nuclei; exact-C contour persist
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hexEdgeDist(p: vec2<f32>) -> f32 {
    var q = abs(p);
    return max(q.x * 0.5 + q.y * 0.866025, q.x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / dims;
    let coord = vec2<i32>(global_id.xy);
    let aspect = dims.x / max(dims.y, 0.001);
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let gridSize = mix(10.0, 50.0, u.zoom_params.x);
    let glowStrength = mix(0.5, 3.0, u.zoom_params.y) * (1.0 + bass * 0.5);
    let pulseSpeed = u.zoom_params.z * 5.0 * (1.0 + mids * 0.35);
    let edgeSens = u.zoom_params.w;

    var p = uvCorrected * gridSize;

    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;

    let fractA = fract(p / r) * r - h;
    let fractB = (fract((p / r) + 0.5) * r) - h;

    var localUV = vec2<f32>(0.0);
    if (dot(fractA, fractA) < dot(fractB, fractB)) {
        localUV = fractA;
    } else {
        localUV = fractB;
    }

    var q = abs(localUV);
    let distToCenter = max(q.x * 0.5 + q.y * 0.866025, q.x);
    let distToEdge = 0.5 - distToCenter;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let c = src.rgb;
    let texel = 1.0 / dims;
    let cR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let cU = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    let luma = dot(c, vec3<f32>(0.333));
    let lumaR = dot(cR, vec3<f32>(0.333));
    let lumaU = dot(cU, vec3<f32>(0.333));

    let imgEdge = sqrt(pow(luma - lumaR, 2.0) + pow(luma - lumaU, 2.0));
    let prev = textureLoad(dataTextureC, coord, 0);
    let persist = max(imgEdge, prev.a * 0.82);

    var mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseDist = distance(uvCorrected, vec2<f32>(mouse.x * aspect, mouse.y));
    let pulseTime = u.config.x * pulseSpeed;
    let wave = sin(mouseDist * 10.0 - pulseTime);
    let pulse = smoothstep(0.8 - treble * 0.08, 1.0, wave);

    var color = c * 0.7;

    let lineThickness = 0.02;
    let isHexLine = 1.0 - smoothstep(0.0, lineThickness, distToEdge);
    let via = 1.0 - smoothstep(0.0, lineThickness * 1.8, distToCenter);

    let hexColor = mix(vec3<f32>(0.0, 0.5, 1.0), vec3<f32>(1.0, 0.0, 0.5), pulse + bass * 0.15);

    let liveEdge = max(imgEdge, persist * 0.85);
    let activeHex = step(edgeSens * 0.1, liveEdge) * (0.7 + treble * 0.3) + pulse * (0.45 + bass * 0.45);

    color = mix(color, hexColor * glowStrength, isHexLine * clamp(activeHex + 0.2, 0.2, 1.0));
    color += (1.0 - isHexLine) * hexColor * activeHex * 0.2;
    color += hexColor * via * activeHex * 0.45;

    let mouseHover = 1.0 - smoothstep(0.0, 0.2, mouseDist);
    color += mouseHover * vec3<f32>(0.1, 0.1, 0.2);

    let finalAlpha = clamp(0.14 + isHexLine * clamp(activeHex + 0.15, 0.0, 1.0) * 0.45 + pulse * 0.18 + bass * 0.08 + via * activeHex * 0.12, 0.08, 0.96);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + isHexLine * 0.05 + pulse * 0.02, 0.0, 1.0);

    let outColor = vec4<f32>(acesToneMap(color), finalAlpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
