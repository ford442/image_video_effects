// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Chroma Vortex
// Param1: Twist Amount
// Param2: RGB Separation (Spread)
// Param3: Radius
// Param4: Center Bias (how much the center stays intact)

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let twist = u.zoom_params.x * 3.14159 * 2.0; // +/- 2 PI
    let spread = u.zoom_params.y * 0.1;
    let radius = max(u.zoom_params.z, 0.01);
    let centerBias = u.zoom_params.w;

    let diff = uv - mousePos;
    // Aspect corrected distance for circular effect
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));

    // Calculate rotation angle based on distance
    // smoothstep from Radius to 0 creates a soft falloff
    var factor = smoothstep(radius, 0.0, dist);

    // Bias: factor^power. If bias > 1, factor drops off quicker.
    // If bias < 1, factor stays high longer.
    // Let's map param4 (0..1) to power (0.2..5.0)
    let power = centerBias * 4.8 + 0.2;
    factor = pow(factor, power);

    // Three different angles for RGB
    let angleBase = factor * twist;
    let angleR = angleBase - spread * factor * 10.0;
    let angleG = angleBase;
    let angleB = angleBase + spread * factor * 10.0;

    // To rotate around mouse:
    // 1. diff = UV - Mouse
    // 2. rotate diff
    // 3. NewUV = Mouse + rotatedDiff

    // We adjust diff for aspect before rotation? No, rotation is 2D.
    // Ideally we rotate in square space.
    let diffSq = vec2<f32>(diff.x * aspect, diff.y);

    let rotR_sq = rotate(diffSq, angleR);
    let rotG_sq = rotate(diffSq, angleG);
    let rotB_sq = rotate(diffSq, angleB);

    // Convert back to UV space
    let rotR = vec2<f32>(rotR_sq.x / aspect, rotR_sq.y);
    let rotG = vec2<f32>(rotG_sq.x / aspect, rotG_sq.y);
    let rotB = vec2<f32>(rotB_sq.x / aspect, rotB_sq.y);

    let uvR = clamp(mousePos + rotR, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(mousePos + rotG, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(mousePos + rotB, vec2<f32>(0.0), vec2<f32>(1.0));

    let colR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(colR, colG, colB, 1.0));
}
