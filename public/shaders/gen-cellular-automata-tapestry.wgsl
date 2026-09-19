// ═══════════════════════════════════════════════════════════════════
//  Cellular Automata Tapestry
//  Category: generative
//  Features: multi-state-ca, evolving-rules, audio-mutation, mouse-nutrient, tapestry-weave, depth-pattern, temporal-texture, organic-evolution, semantic-alpha, temporal, chromatic, depth-aware, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-31, 2026-09-15
//  Ideas: kill-rate contour banding on the growth front; slow-rotating diffusion-anisotropy striping
//  A packing: raw sim (nextA, nextB, 0, 1)
//  By: Grok (deep visual/audio flourish — seasonal plasma color climate, stronger mouse nutrient injector, semantic alpha from chemical energy + glow, richer final glaze)
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=diffA, y=diffB, z=feed, w=kill
    ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
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

    var sumA = 0.0;
    var sumB = 0.0;
    let weightCenter = -1.0;
    let weightAdjacent = 0.2;
    let weightDiagonal = 0.05;

    let currentCenter = textureLoad(dataTextureC, coord, 0).xy;

    // Convolution 3x3 — exact loads: C is rgba32float history, never filtered.
    for(var i = -1; i <= 1; i++) {
        for(var j = -1; j <= 1; j++) {
            let offsetCoord = coord + vec2<i32>(i, j);
            // periodic boundary or clamp, let's clamp
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

    // Idea 2 — diffusion-anisotropy warp: a slow-rotating directional bias on
    // the axis taps grows oriented Turing stripes. Weights still sum to 1.0,
    // so the solver stays stable while the pattern gains a grain direction.
    let anisoPh = u.config.x * 0.12;
    let wAx = 0.25 + 0.12 * cos(anisoPh);
    let wAy = 0.25 - 0.12 * cos(anisoPh);
    let eC = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), res - vec2<i32>(1)), 0).xy;
    let wC = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), res - vec2<i32>(1)), 0).xy;
    let nC = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), res - vec2<i32>(1)), 0).xy;
    let sC = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), res - vec2<i32>(1)), 0).xy;
    sumA += (eC.x + wC.x) * (wAx - weightAdjacent) + (nC.x + sC.x) * (wAy - weightAdjacent);
    sumB += (eC.y + wC.y) * (wAx - weightAdjacent) + (nC.y + sC.y) * (wAy - weightAdjacent);

    var diffA = u.zoom_params.x;
    var diffB = u.zoom_params.y;
    var feed = u.zoom_params.z;
    var kill = u.zoom_params.w;

    // Modulate feed/kill based on video luminance
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x; let mids = audio.y; let treble = audio.z;

    // ═══ Chromatic dispersion on video input ═══
    let chromStrength = 0.005 + bass * 0.01;
    let vidR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chromStrength, 0.0), 0.0).r;
    let vidG = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, chromStrength), 0.0).g;
    let vidB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(chromStrength * 0.5, chromStrength * 0.5), 0.0).b;
    let vidColor = vec3<f32>(vidR, vidG, vidB);

    let luminance = dot(vidColor, vec3<f32>(0.299, 0.587, 0.114));
    feed += (luminance * 0.02 - 0.01);
    kill -= (luminance * 0.01);

    // Modulate speed by audio
    let dt = 1.0 + u.config.y * 0.5;

    let A = currentCenter.x;
    let B = currentCenter.y;
    let reaction = A * B * B;

    var nextA = A + (diffA * sumA - reaction + feed * (1.0 - A)) * dt;
    var nextB = B + (diffB * sumB + reaction - (kill + feed) * B) * dt;

    // Mouse interaction — nutrient injector gated on press (zoom_config.w),
    // preserving the injector intent without flooding B whenever the cursor
    // merely rests near the canvas.
    let mouseDown = u.zoom_config.w > 0.5;
    let mouseDist = distance(uv, u.zoom_config.yz);
    if (mouseDist < 0.02 && mouseDown) {
        nextB = 1.0; // Inject chemical B at mouse
    }


    // Initial state
    if (frame < 5) {
        nextA = 1.0;
        nextB = select(0.0, 1.0, fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453) > 0.99);
    }

    nextA = clamp(nextA, 0.0, 1.0);
    nextB = clamp(nextB, 0.0, 1.0);

    // Write back ping pong
    textureStore(dataTextureA, coord, vec4<f32>(nextA, nextB, 0.0, 1.0));

    // ═══ Deep seasonal plasma + semantic alpha (visual/audio flourish) ═══
    let season = fract(u.config.x * 0.018 + bass * 0.6); // slow evolving climate

    // Richer color: seasonal tint + audio energy on the chemical B
    let plasmaIdx = min(u32(nextB * 255.0), 255u);
    var mappedColor = plasmaBuffer[plasmaIdx].rgb;
    // Seasonal hue rotation + mids/treble for liveliness
    let seasonTint = vec3<f32>(0.6 + season * 0.5, 0.7 - season * 0.3, 0.9 - mids * 0.2);
    mappedColor = mix(mappedColor, mappedColor * seasonTint, 0.35 + treble * 0.25);

    // Composite with audio-reactive weight
    let energy = nextB * (0.9 + bass * 0.4 + treble * 0.25);
    var outColor = mix(vidColor, mappedColor, energy * 1.35);
    outColor = acesToneMap(outColor);

    // Idea 1 — kill-rate contour banding: isochrone bands of B concentration
    // over the growth front, so band spacing reads local wave speed — a native
    // reaction-diffusion visualization, not a palette overlay.
    let bandF = fract(nextB * 6.0 + mids * 0.2);
    let bandEdge = smoothstep(0.0, 0.10, bandF) * smoothstep(1.0, 0.90, bandF);
    outColor = outColor + vec3<f32>(0.10, 0.14, 0.20) * (1.0 - bandEdge) * energy;

    // ═══ Temporal feedback (exact load: C is rgba32float history) ═══
    let prev = textureLoad(dataTextureC, coord, 0);
    outColor = mix(outColor, prev.rgb * 0.9, 0.03 + bass * 0.01);

    // Semantic alpha: chemical concentration + audio "glow" gives transparent background areas
    let semantic_alpha = clamp(0.35 + energy * 0.7 + mids * 0.15, 0.25, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(outColor, semantic_alpha));

    // Depth write (was unbound despite binding — enables depth-aware stacking)
    let ca_depth = 0.2 + nextB * 0.6 + (1.0 - energy) * 0.2;
    textureStore(writeDepthTexture, coord, vec4<f32>(ca_depth, 0.0, 0.0, 0.0));
}
