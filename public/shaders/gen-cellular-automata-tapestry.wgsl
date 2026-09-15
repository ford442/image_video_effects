// ═══════════════════════════════════════════════════════════════════
//  Cellular Automata Tapestry
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: warp/weft from A/B chemicals; Pearson spots/worms/maze glaze
//  A packing: raw (nextA, nextB, weave, 1) — C is read as .xy chemicals; ACES on writeTexture only
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, yz=mouse_uv, w=MouseDown
    zoom_params: vec4<f32>,  // x=diffA, y=diffB, z=feed, w=kill
    ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));
    if (coord.x >= res.x || coord.y >= res.y) {
        return;
    }

    let uv = vec2<f32>(f32(coord.x) / f32(res.x), f32(coord.y) / f32(res.y));
    let frame = i32(u.config.x * 60.0);
    let time = u.config.x;
    let aspect = u.config.z / max(u.config.w, 1.0);

    var sumA = 0.0;
    var sumB = 0.0;
    let weightCenter = -1.0;
    let weightAdjacent = 0.2;
    let weightDiagonal = 0.05;

    let currentCenter = textureLoad(dataTextureC, coord, 0).xy;

    for (var i = -1; i <= 1; i = i + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            let offsetCoord = coord + vec2<i32>(i, j);
            let clampedCoord = clamp(offsetCoord, vec2<i32>(0), res - vec2<i32>(1));
            let val = textureLoad(dataTextureC, clampedCoord, 0).xy;

            var weight = 0.0;
            if (i == 0 && j == 0) { weight = weightCenter; }
            else if (abs(i) == 1 && abs(j) == 1) { weight = weightDiagonal; }
            else { weight = weightAdjacent; }

            sumA += val.x * weight;
            sumB += val.y * weight;
        }
    }

    var diffA = u.zoom_params.x;
    var diffB = u.zoom_params.y;
    var feed = u.zoom_params.z;
    var kill = u.zoom_params.w;

    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let chromStrength = 0.005 + bass * 0.01;
    let vidR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chromStrength, 0.0), 0.0).r;
    let vidG = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, chromStrength), 0.0).g;
    let vidB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(chromStrength * 0.5, chromStrength * 0.5), 0.0).b;
    let vidColor = vec3<f32>(vidR, vidG, vidB);

    let luminance = dot(vidColor, vec3<f32>(0.299, 0.587, 0.114));
    feed += (luminance * 0.02 - 0.01);
    kill -= (luminance * 0.01);

    // dt from bass — config.y is ripple count, not audio.
    let dt = 1.0 + bass * 0.5;

    let A = currentCenter.x;
    let B = currentCenter.y;
    let reaction = A * B * B;

    var nextA = A + (diffA * sumA - reaction + feed * (1.0 - A)) * dt;
    var nextB = B + (diffB * sumB + reaction - (kill + feed) * B) * dt;

    let mouseDist = distance(uv, u.zoom_config.yz);
    let held = u.zoom_config.w > 0.5;
    let nutrient = smoothstep(0.04, 0.0, mouseDist);
    nextB = mix(nextB, 1.0, nutrient * select(0.35, 1.0, held));

    var inoc = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age < 0.0 || age > 2.8) { continue; }
        let delta = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
        let dist = length(delta);
        let ring = abs(dist - age * 0.18);
        inoc = max(inoc, (1.0 - smoothstep(0.0, 0.018, ring)) * exp(-age * 0.9));
    }
    nextB = mix(nextB, 1.0, inoc * 0.85);

    if (frame < 5) {
        nextA = 1.0;
        nextB = select(0.0, 1.0, fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453) > 0.99);
    }

    nextA = clamp(nextA, 0.0, 1.0);
    nextB = clamp(nextB, 0.0, 1.0);

    // Idea 1 — warp (A, vertical) × weft (B, horizontal) woven from the two chemicals.
    let warp = abs(sin(uv.y * 72.0 + nextA * 6.2831853));
    let weft = abs(sin(uv.x * 72.0 + nextB * 6.2831853));
    let weave = mix(warp * weft, 0.5 * (warp + weft), 0.35);

    textureStore(dataTextureA, coord, vec4<f32>(nextA, nextB, weave, 1.0));

    let season = fract(time * 0.018 + bass * 0.6);

    // Native A/B colormap — do not index plasmaBuffer as a LUT.
    let chem = vec3<f32>(
        nextB * (0.85 + season * 0.35),
        nextA * 0.55 + nextB * 0.25 * (1.0 - season),
        mix(0.15, 0.75, nextA) * (0.9 - mids * 0.2)
    );

    // Idea 2 — Pearson glaze from (kill − feed): spots / worms / maze.
    let fk = kill - feed;
    let spots = 1.0 - smoothstep(0.008, 0.014, fk);
    let worms = smoothstep(0.010, 0.016, fk) * (1.0 - smoothstep(0.020, 0.028, fk));
    let maze  = smoothstep(0.022, 0.030, fk);
    let pearsonTint = vec3<f32>(1.0, 0.72, 0.55) * spots
                    + vec3<f32>(0.45, 0.82, 0.70) * worms
                    + vec3<f32>(0.55, 0.48, 0.95) * maze;
    var mappedColor = mix(chem, chem * pearsonTint, 0.40 + treble * 0.15);
    mappedColor = mappedColor * (0.75 + weave * 0.55);

    let energy = nextB * (0.9 + bass * 0.4 + treble * 0.25);
    var outColor = mix(vidColor, mappedColor, clamp(energy * 1.35, 0.0, 1.0));
    outColor = acesToneMap(outColor);

    let semantic_alpha = clamp(0.35 + energy * 0.7 + weave * 0.15 + mids * 0.1, 0.25, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(outColor, semantic_alpha));

    let ca_depth = 0.2 + nextB * 0.6 + (1.0 - energy) * 0.2;
    textureStore(writeDepthTexture, coord, vec4<f32>(ca_depth, 0.0, 0.0, 0.0));
}
