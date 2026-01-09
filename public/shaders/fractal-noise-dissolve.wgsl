// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Hash function for noise
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash22(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                   dot(hash22(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(hash22(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                   dot(hash22(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Params
    let noiseScale = u.zoom_params.x * 20.0 + 5.0; // x: Noise Scale
    let radius = u.zoom_params.y * 0.5;            // y: Dissolve Radius
    let edgeWidth = u.zoom_params.z * 0.2;         // z: Edge Softness
    let burnColor = u.zoom_params.w;               // w: Burn Intensity

    // Noise generation
    var n = noise(uv * noiseScale + time);
    n += noise(uv * noiseScale * 2.0 - time) * 0.5;
    n = n * 0.5 + 0.5; // range 0-1

    // Distance from mouse
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    // Threshold calculation
    // If dist is small (near mouse), threshold is high -> dissolve
    // We want a circular hole.
    // Normalized dist 0..1
    let mask = smoothstep(radius, radius + edgeWidth, dist + (n * 0.2 - 0.1));

    // Original Color
    let col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Burn effect at the edge
    let edge = 1.0 - smoothstep(radius, radius + edgeWidth * 2.0, dist + (n * 0.2 - 0.1));
    let burn = vec3<f32>(1.0, 0.5, 0.2) * edge * burnColor * 5.0 * (1.0 - mask);

    // Final Mix: mask=1 means show image, mask=0 means dissolved (black or transparent)
    // The problem is storage texture must be written. We can't "discard".
    // We'll write black/transparent.

    var finalColor = col * mask + vec4<f32>(burn, 0.0);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
