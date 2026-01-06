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
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Glass Wipes
// A simulation of rain on glass that distorts the image.
// The mouse acts as a wiper, clearing the rain.
//
// State (dataTextureA):
// R: Current Wetness Amount (0.0 to 1.0)
// G: Droplet Offset X (accumulated)
// B: Droplet Offset Y (accumulated)
// A: Unused

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let rainIntensity = 0.005 + u.zoom_params.x * 0.05; // How fast it gets wet
    let wiperSize = 0.05 + u.zoom_params.y * 0.25;    // Radius of wiper
    let distortionScale = u.zoom_params.z * 0.05;     // Strength of refraction
    let evaporation = 0.001 + u.zoom_params.w * 0.01; // Drying speed naturally

    // Read previous state from dataTextureC (binding 9 is the history buffer for binding 7)
    let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var wetness = prevState.r;

    // Add Rain
    // Use pseudo-random noise to add droplets randomly
    let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (noise > (1.0 - rainIntensity)) {
        wetness = min(1.0, wetness + 0.3);
    }

    // Natural evaporation
    wetness = max(0.0, wetness - evaporation);

    // Mouse Wiper Interaction
    if (mousePos.x >= 0.0) { // Check if mouse is active
        let dVec = uv - mousePos;
        // Correct distance for aspect ratio
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        if (dist < wiperSize) {
             let wipeFactor = smoothstep(wiperSize, wiperSize * 0.5, dist);
             wetness = wetness * (1.0 - wipeFactor);
        }
    }

    // Droplet physics (simplified)
    // If wetness is high, gravity pulls it down?
    // Implementing proper fluid simulation is hard in one pass without neighbor sampling loop,
    // so we'll just simulate the visual effect via distortion noise.

    // Calculate distortion vector based on wetness
    // Create a "drip" texture pattern using noise
    let dripNoiseX = fract(sin(dot(uv + vec2<f32>(0.0, time * 0.1), vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5;
    let dripNoiseY = fract(sin(dot(uv + vec2<f32>(0.0, time * 0.1), vec2<f32>(39.346, 11.135))) * 43758.5453) - 0.5;

    let distortion = vec2<f32>(dripNoiseX, dripNoiseY) * wetness * distortionScale;

    // Save state
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(wetness, 0.0, 0.0, 1.0));

    // Render
    // Distort UVs
    let distortedUV = clamp(uv + distortion, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Add specular highlight for water
    let lightDir = normalize(vec2<f32>(0.5, 0.5) - uv);
    let normal = normalize(vec3<f32>(distortion * 100.0, 1.0));
    let light = max(0.0, dot(normal, normalize(vec3<f32>(lightDir, 1.0))));
    let specular = pow(light, 20.0) * wetness * 0.5;

    color = color + vec4<f32>(specular, specular, specular, 0.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
