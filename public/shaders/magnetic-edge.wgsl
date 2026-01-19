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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=Width, w=Height
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

// Magnetic Edge
// Detects edges and pulls them towards the mouse.

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Params
    let pullStrength = 0.05 + u.zoom_params.x * 0.2;
    let radius = 0.3 + u.zoom_params.y * 0.5;
    let edgeThreshold = 0.1 + u.zoom_params.z * 0.4; // Sensitivity
    let glow = u.zoom_params.w;

    // Edge Detection (Sobel-ish)
    let texel = 1.0 / resolution;
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;

    let dX = length(r - l);
    let dY = length(b - t);
    let edge = sqrt(dX*dX + dY*dY);

    var finalUV = uv;

    // If pixel is an edge, and near mouse, displace it
    if (edge > edgeThreshold && mouse.x >= 0.0) {
        let aspect = resolution.x / resolution.y;
        let dVec = mouse - uv; // Vector pointing TO mouse
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        if (dist < radius) {
            let influence = smoothstep(radius, 0.0, dist); // 1 at center, 0 at radius
            // Pull towards mouse
            finalUV = uv + dVec * influence * pullStrength;

            if (mouseDown > 0.5) {
                finalUV = uv + dVec * influence * pullStrength * 2.0;
            }
        }
    }

    var finalColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Highlight edges that are being pulled
    if (glow > 0.0 && edge > edgeThreshold) {
         let aspect = resolution.x / resolution.y;
         let dVec = mouse - uv;
         let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
         if (dist < radius) {
             finalColor += vec4<f32>(glow * (1.0 - dist/radius), glow * 0.5, 0.0, 0.0);
         }
    }

    textureStore(writeTexture, global_id.xy, finalColor);
}
