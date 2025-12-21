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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Neon Warp
// Param1: Distortion Strength
// Param2: Neon Intensity
// Param3: Color Shift Speed
// Param4: Warp Decay

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Params
    let warpStrength = u.zoom_params.x * 2.0;
    let neonIntensity = u.zoom_params.y * 5.0;
    let colorSpeed = u.zoom_params.z;
    let decay = mix(0.9, 0.99, u.zoom_params.w);

    // Read previous displacement field
    // xy = displacement
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).xy;

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let dVec = uv - mousePos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    var displacement = prev * decay;

    // Create a repulsive field around mouse
    if (dist < 0.2) {
        let push = normalize(dVec) * (1.0 - dist / 0.2) * 0.01 * warpStrength;
        // Check for NaN or zero length
        if (dist > 0.001) {
            displacement = displacement + push;
        }
    }

    // Write state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(displacement, 0.0, 0.0));

    // Rendering
    let warpedUV = uv - displacement; // Inverse mapping for warp

    // Clamp to avoid artifacts at edges
    let clampedUV = clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let centerColor = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0).rgb;

    // Edge detection (Sobel-ish) on warped coords
    let step = 1.0 / resolution;
    let c1 = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(step.x, 0.0), 0.0).rgb;
    let c2 = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(-step.x, 0.0), 0.0).rgb;
    let c3 = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(0.0, step.y), 0.0).rgb;
    let c4 = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(0.0, -step.y), 0.0).rgb;

    let edgeX = length(c1 - c2);
    let edgeY = length(c3 - c4);
    let edge = sqrt(edgeX*edgeX + edgeY*edgeY);

    // Neon color generation
    let hue = fract(time * colorSpeed + length(displacement) * 10.0);
    let neon = hsv2rgb(vec3<f32>(hue, 0.8, 1.0));

    var finalColor = centerColor;
    if (edge > 0.1) {
        finalColor = mix(finalColor, neon, edge * neonIntensity);
    }

    // Add some glow from displacement intensity
    finalColor = finalColor + neon * length(displacement) * 5.0;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
