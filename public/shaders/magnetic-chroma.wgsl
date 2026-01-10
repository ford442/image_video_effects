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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Twist, w=Falloff
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let strength = u.zoom_params.x * 2.0;       // -2.0 to 2.0 ideally, but slider 0-1 maps to effect
    // To allow push and pull, we might map 0.0-1.0 to -1.0 to 1.0 in shader?
    // Usually params are 0-1. Let's make it pull only for now, or use mapped val.
    // Let's assume input is 0-1, mapped to 0-2 strength.

    let radius = max(0.01, u.zoom_params.y * 0.8);
    let twist = (u.zoom_params.z - 0.5) * 10.0; // -5 to 5
    let falloff = u.zoom_params.w;

    // Vector to mouse
    let toMouse = mousePos - uv;
    let distVec = toMouse * vec2<f32>(aspect, 1.0); // Aspect corrected distance
    let dist = length(distVec);

    // Calculate influence
    // smoothstep from Radius+Falloff down to Radius?
    // Let's use exp falloff
    let influence = smoothstep(radius, radius * (1.0 - falloff), dist);
    // if dist > radius, 0. if dist < radius * (1-falloff), 1.

    // Calculate displacement
    // We want R to pull more, B less.
    let pull = strength * influence * dist; // Stronger near mouse? Or uniform pull?
    // Usually magnetic pull is stronger closer. 1/dist^2.
    // Let's do displacement = normalize(toMouse) * strength * influence.

    var dir = vec2<f32>(0.0);
    if (dist > 0.001) {
        dir = normalize(toMouse);
    }

    // Twist
    // Rotate dir based on dist
    let angle = twist * (1.0 - dist/radius) * influence;
    let c = cos(angle);
    let s = sin(angle);
    let twistedDir = vec2<f32>(
        dir.x * c - dir.y * s,
        dir.x * s + dir.y * c
    );

    // Separation
    let offsetR = twistedDir * strength * influence * 1.0 * 0.05;
    let offsetG = twistedDir * strength * influence * 0.5 * 0.05;
    let offsetB = twistedDir * strength * influence * 0.0 * 0.05;
    // Or maybe slightly push B away?
    // Let's Make R pull, G stay, B push.
    // offsetR = ... * 1.0
    // offsetG = ... * 0.0
    // offsetB = ... * -0.5

    let uvR = uv + offsetR;
    let uvG = uv + offsetG;
    let uvB = uv - offsetR * 0.5; // Opposite direction

    // Sample
    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));

    // Depth pass
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
