// ----------------------------------------------------------------
// Cellular Automata Tapestry (Reaction-Diffusion)
// Category: generative
// ----------------------------------------------------------------

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

    // Convolution 3x3
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

    var diffA = u.zoom_params.x;
    var diffB = u.zoom_params.y;
    var feed = u.zoom_params.z;
    var kill = u.zoom_params.w;

    // Modulate feed/kill based on video luminance
    let vidColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
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

    // Mouse interaction
    let mouseDist = distance(uv, u.zoom_config.yz);
    if (mouseDist < 0.02 && u.zoom_config.z > 0.0) {
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


    // Plasma coloring based on B concentration
    let plasmaIdx = min(u32(nextB * 255.0), 255u);
    let mappedColor = plasmaBuffer[plasmaIdx].rgb;

    // Composite
    let outColor = mix(vidColor, mappedColor, nextB * 1.5);

    textureStore(writeTexture, coord, vec4<f32>(outColor, 1.0));
}
