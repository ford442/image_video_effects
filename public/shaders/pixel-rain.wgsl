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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let speed = u.zoom_params.x * 2.0 + 0.1; // Range 0.1 to 2.1
    let glitchIntensity = u.zoom_params.y;   // Range 0.0 to 1.0
    let density = u.zoom_params.z * 50.0 + 10.0; // Range 10.0 to 60.0

    // Mouse
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Create grid for rain columns
    // We only grid-ify X to create columns. Y is continuous.
    let colIndex = floor(uv.x * density);

    // Random offset per column based on index
    let colRandom = fract(sin(colIndex * 12.9898) * 43758.5453);

    // Drop speed varies by column
    let dropSpeed = (colRandom * 0.5 + 0.5) * speed;

    // Calculate scroll offset
    let scrollY = time * dropSpeed;

    // Mouse interaction: repulsive force
    // Correct aspect for circular interaction
    let mouseDist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    // Interaction radius 0.2
    let mouseForce = smoothstep(0.2, 0.0, mouseDist);

    // Basic texture sampling coordinates
    var sampleUV = vec2<f32>(uv.x, fract(uv.y + scrollY));

    // Apply horizontal jitter (glitch) based on intensity
    // Only apply if we are "in" a glitchy segment
    if (fract(uv.y * density * 0.5 + time) < glitchIntensity * 0.2) {
        sampleUV.x += (fract(sin(uv.y * 100.0) * 43758.5) - 0.5) * 0.05 * glitchIntensity;
    }

    // Apply mouse distortion (push pixels away from mouse)
    if (mouseForce > 0.0) {
        let dir = normalize(uv - mouse); // Direction from mouse to pixel
        // Distort sample UV slightly away from mouse
        sampleUV -= dir * mouseForce * 0.1 * glitchIntensity;
    }

    // Sample the texture
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Aesthetic: Matrix Green Tint
    let matrixGreen = vec4<f32>(0.0, 1.0, 0.4, 1.0);
    // Mix based on glitch intensity
    color = mix(color, color * matrixGreen * 1.5, glitchIntensity * 0.6);

    // Add "rain drop head" highlight
    // The "phase" of the rain cycle at this pixel
    let rainPhase = fract(uv.y + scrollY + colRandom);
    // If phase is near start (bottom of screen visually because Y increases down? No, UV 0 is top usually in WebGPU... wait.
    // Standard UV: 0,0 top-left. +Y is down.
    // So +scrollY moves texture UP (sample lower).
    // To make rain fall DOWN, we should subtract scrollY from UV.y or add to sample?
    // If we want the image to "fall", we decrease UV.y (sample higher up over time).
    // Wait, let's just stick to "scrolling texture".

    // Brighten the leading edge
    if (rainPhase < 0.05) {
       color += vec4<f32>(0.4, 1.0, 0.4, 0.0) * glitchIntensity;
    }

    // Mouse hover highlight
    if (mouseForce > 0.0) {
        color += vec4<f32>(0.2, 0.2, 0.5, 0.0) * mouseForce;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
