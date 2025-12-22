// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let splitDist = u.zoom_params.x * 0.1; // Max split distance
    let angleOffset = u.zoom_params.y * 6.28; // Rotation of split
    let noiseAmt = u.zoom_params.z;
    let radius = 0.1 + (u.zoom_params.w * 0.5);

    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));

    // Influence factor based on mouse distance
    // Glitch gets stronger closer to mouse? Or maybe global but controlled by mouse.
    // Let's make it stronger closer to mouse.
    let influence = smoothstep(radius, 0.0, dist); // 1.0 at mouse, 0.0 at radius

    var offsetR = vec2<f32>(0.0);
    var offsetG = vec2<f32>(0.0);
    var offsetB = vec2<f32>(0.0);

    if (influence > 0.001) {
        let t = u.config.x;

        // Jitter/Noise
        let noise = (hash12(uv * 100.0 + t) - 0.5) * noiseAmt * influence * 0.1;

        // Directional Split
        let dir = vec2<f32>(cos(angleOffset), sin(angleOffset));
        let shift = dir * splitDist * influence;

        offsetR = shift + vec2<f32>(noise);
        offsetG = -shift * 0.5; // Green stays somewhat central or moves opposite
        offsetB = -shift + vec2<f32>(-noise);
    }

    let r = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
