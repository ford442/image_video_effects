// ═══════════════════════════════════════════════════════════════════
//  Bubble Wrap
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: hex packing; neighbor sympathetic pop
//  A packing: popped flag + pop time in A.rg (raw). Display ACES RGB.
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

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec2<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0).rg;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    var uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let dims = vec2<i32>(resolution);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    let bubblesScale = max(0.01, u.zoom_params.x * 0.1);
    let popStrength = u.zoom_params.y;
    let refraction = u.zoom_params.z * 0.2;
    let highlight = u.zoom_params.w * 0.8;

    let mousePos = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseDown = u.zoom_config.w > 0.5;

    // Idea 1 — hex packing (odd rows offset half a cell)
    let hexH = bubblesScale * 0.8660254;
    let row = floor(uv.y / hexH);
    let rowOdd = (i32(row) & 1) != 0;
    let xOff = select(0.0, bubblesScale * 0.5, rowOdd);
    let col = floor((uv.x - xOff) / bubblesScale);
    let gridCenter = vec2<f32>((col + 0.5) * bubblesScale + xOff, (row + 0.5) * hexH);
    let localUV = vec2<f32>(
        (uv.x - gridCenter.x) / bubblesScale + 0.5,
        (uv.y - gridCenter.y) / hexH + 0.5
    );

    let oldData = stateAt(pixel, dims);
    let oldState = oldData.x;
    let oldPopTime = oldData.y;

    let dCenter = distance(gridCenter * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));
    let interactRadius = bubblesScale * 0.8;

    // Idea 2 — neighbor sympathetic pop (hex 6-neighborhood)
    var neighborPops = 0.0;
    let nOff = array<vec2<f32>, 6>(
        vec2<f32>(bubblesScale, 0.0),
        vec2<f32>(-bubblesScale, 0.0),
        vec2<f32>(bubblesScale * 0.5, hexH),
        vec2<f32>(-bubblesScale * 0.5, hexH),
        vec2<f32>(bubblesScale * 0.5, -hexH),
        vec2<f32>(-bubblesScale * 0.5, -hexH)
    );
    for (var i = 0; i < 6; i = i + 1) {
        let nUv = clamp(gridCenter + nOff[i], vec2<f32>(0.0), vec2<f32>(0.999));
        let nPx = vec2<i32>(nUv * resolution);
        neighborPops += step(0.5, stateAt(nPx, dims).x);
    }

    var newState = oldState;
    var popTime = oldPopTime;
    let selfPop = mouseDown && dCenter < interactRadius && oldState < 0.5;
    let chainPop = neighborPops >= 2.0 && oldState < 0.5 && dCenter < interactRadius * 2.4;
    if (selfPop || chainPop) {
        newState = 1.0;
        popTime = time;
    }

    textureStore(dataTextureA, pixel, vec4<f32>(newState, popTime, neighborPops / 6.0, 1.0));

    let agePop = time - popTime;
    let d = length(localUV - 0.5) * 2.0;
    var z = sqrt(max(0.0, 1.0 - d * d));

    let collapseT = smoothstep(0.0, 0.18, agePop);
    let jiggle = sin(agePop * 42.0) * exp(-agePop * 9.0) * 0.18;
    let poppedFlatten = clamp(mix(1.0, 0.12, collapseT) + jiggle, 0.05, 1.0);
    let neighborWeaken = 1.0 - clamp(neighborPops / 6.0, 0.0, 1.0) * 0.28 * (1.0 - newState);
    let flattening = select(1.0, mix(1.0, poppedFlatten, popStrength), newState > 0.5) * neighborWeaken;
    z = z * flattening;

    if (newState > 0.5) {
        let wr = sin(localUV.x * 60.0 + col) * sin(localUV.y * 60.0 + row);
        z = z + wr * 0.04 * collapseT;
    }

    let normal = normalize(vec3<f32>((localUV - 0.5) * flattening, z));
    let refractUV = clamp(uv - normal.xy * refraction * z, vec2<f32>(0.0), vec2<f32>(1.0));
    var imgColor = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0);
    if (newState > 0.5) {
        imgColor = vec4<f32>(imgColor.rgb * 0.9, imgColor.a);
    }

    let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
    let spec = pow(max(0.0, dot(normal, lightDir)), 20.0) * highlight * (1.0 + treble * 0.4);
    let edge = smoothstep(0.85, 0.95, d);
    var hdr = imgColor.rgb + spec;
    hdr = mix(hdr, vec3<f32>(0.05, 0.05, 0.05), edge);

    if (newState > 0.5 && agePop < 0.5) {
        let ringR = agePop * 5.0;
        let ring = exp(-pow((d - ringR) * 5.0, 2.0)) * exp(-agePop * 7.0);
        hdr = hdr + vec3<f32>(0.9, 0.95, 1.0) * ring * 1.2 * (1.0 + bass * 0.3);
    }

    let mapped = aces(hdr);
    let alpha = clamp(imgColor.a * 0.4 + z * 0.35 + spec * 0.3 + edge * 0.2, 0.0, 1.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
