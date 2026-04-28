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
    zoom_params: vec4<f32>,  // x=DiffusionA, y=DiffusionB, z=Feed, w=Kill
    ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(u.config.z, u.config.w);

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let uv = vec2<f32>(coords) / vec2<f32>(res);

    // Ping-pong determination via dataTextureC
    let center = textureLoad(dataTextureC, coords, 0).xy; // x=A, y=B
    var a = center.x;
    var b = center.y;

    if (u.config.x < 0.1) {
        a = 1.0;
        b = 0.0;
    }

    // Laplacian
    var lapl = vec2<f32>(0.0);
    let weightAdj = 0.2;
    let weightDiag = 0.05;
    let weightCenter = -1.0;

    lapl += center * weightCenter;
    lapl += textureLoad(dataTextureC, coords + vec2<i32>(1, 0), 0).xy * weightAdj;
    lapl += textureLoad(dataTextureC, coords + vec2<i32>(-1, 0), 0).xy * weightAdj;
    lapl += textureLoad(dataTextureC, coords + vec2<i32>(0, 1), 0).xy * weightAdj;
    lapl += textureLoad(dataTextureC, coords + vec2<i32>(0, -1), 0).xy * weightAdj;
    lapl += textureLoad(dataTextureC, coords + vec2<i32>(1, 1), 0).xy * weightDiag;
    lapl += textureLoad(dataTextureC, coords + vec2<i32>(-1, 1), 0).xy * weightDiag;
    lapl += textureLoad(dataTextureC, coords + vec2<i32>(1, -1), 0).xy * weightDiag;
    lapl += textureLoad(dataTextureC, coords + vec2<i32>(-1, -1), 0).xy * weightDiag;

    let vidColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(vidColor, vec3<f32>(0.299, 0.587, 0.114));

    let feed = 0.055 + luma * 0.02;
    let kill = 0.062 + luma * 0.01;

    // Default values if params are 0
    var diffA = u.zoom_params.x;
    if (diffA == 0.0) { diffA = 1.0; }
    var diffB = u.zoom_params.y;
    if (diffB == 0.0) { diffB = 0.5; }

    let dt = 1.0 + u.config.y * 2.0;

    let reaction = a * b * b;

    var nextA = a + (diffA * lapl.x - reaction + feed * (1.0 - a)) * dt;
    var nextB = b + (diffB * lapl.y + reaction - (kill + feed) * b) * dt;

    let mousePos = u.zoom_config.yz * vec2<f32>(res);
    if (distance(vec2<f32>(coords), mousePos) < 20.0) {
        nextB = 1.0;
    }

    nextA = clamp(nextA, 0.0, 1.0);
    nextB = clamp(nextB, 0.0, 1.0);

    textureStore(dataTextureA, coords, vec4<f32>(nextA, nextB, 0.0, 1.0));

    let val = abs(nextA - nextB);
    let colorIndex = i32(val * 255.0) % 256;
    let mappedColor = plasmaBuffer[colorIndex];

    let finalColor = mix(vec4<f32>(vidColor, 1.0), mappedColor, val * 2.0);
    textureStore(writeTexture, coords, finalColor);
}
